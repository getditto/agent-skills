import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness.dart';

final _bytes = Uint8List.fromList(List<int>.generate(1024, (i) => i % 256));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('newAttachment from bytes and path with AttachmentMetadata '
      'wrapper', (t) async {
    await withDitto(t, (ditto) async {
      final directory = await Directory.systemTemp.createTemp('ditto_file_');
      try {
        final path = '${directory.path}/photo.bin';
        await File(path).writeAsBytes(_bytes);

        // snippet:start flutter-attachments-1
        // Bytes (all targets) or a file path (not web). Metadata is an
        // optional positional AttachmentMetadata wrapping a String map.
        final fromBytes = await ditto.store.newAttachment(
          _bytes,
          AttachmentMetadata({'name': 'photo.jpg'}),
        );
        final fromPath = await ditto.store.newAttachment(path);
        // snippet:end flutter-attachments-1

        expect(fromBytes.len, _bytes.length);
        expect(fromBytes.metadata, AttachmentMetadata({'name': 'photo.jpg'}));
        expect(fromBytes.metadata.metadata, {'name': 'photo.jpg'});
        expect(fromPath.len, _bytes.length);
        expect(fromPath.metadata.metadata, isEmpty);
        expect(await fromPath.data, _bytes);
        await expectLater(
          ditto.store.newAttachment(42),
          throwsA(isA<DittoException>()),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });

  testWidgets('INSERT (photo ATTACHMENT) then fetchAttachment completes and '
      'auto-stops', (t) async {
    await withDitto(t, (ditto) async {
      final attachment = await ditto.store.newAttachment(_bytes);

      // snippet:start flutter-attachments-2
      await ditto.store.execute(
        'INSERT INTO COLLECTION probes (photo ATTACHMENT) DOCUMENTS (:doc)',
        arguments: {
          'doc': {'_id': 'a', 'photo': attachment},
        },
      );

      final result = await ditto.store.execute(
        'SELECT * FROM COLLECTION probes (photo ATTACHMENT) WHERE _id = :id',
        arguments: {'id': 'a'},
      );
      final token = result.items.first.value['photo'] as Map<String, dynamic>;

      final fetched = Completer<Attachment>();
      final fetcher = ditto.store.fetchAttachment(token, (event) {
        switch (event) {
          case AttachmentFetchEventCompleted(:final attachment):
            fetched.complete(attachment);
          case AttachmentFetchEventProgress():
            break; // downloadedBytes / totalBytes
          case AttachmentFetchEventDeleted():
            fetched.completeError(StateError('attachment deleted'));
        }
      });
      // snippet:end flutter-attachments-2

      expect(fetcher.isStopped, isFalse);
      final completed = await fetched.future.timeout(
        const Duration(seconds: 10),
      );
      expect(completed.id, attachment.id);
      expect(await completed.data, _bytes);
      expect(fetcher.isStopped, isTrue);
      expect(ditto.store.attachmentFetchers, isNot(contains(fetcher)));
    });
  });
}
