import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// snippet:start flutter-attachments-1
/// Creates an attachment from bytes, on every platform. The metadata is an
/// optional positional AttachmentMetadata that wraps a String map.
Future<Attachment> attachPhotoBytes(Ditto ditto, Uint8List jpeg) =>
    ditto.store.newAttachment(jpeg, AttachmentMetadata({'name': 'photo.jpg'}));

/// Creates an attachment from a file path. Not on web, which has no files.
Future<Attachment> attachPhotoFile(Ditto ditto, String path) =>
    ditto.store.newAttachment(path);
// snippet:end flutter-attachments-1

// snippet:start flutter-attachments-2
/// Stores [photo] on the car [carId] and returns the attachment token that
/// a query returns for it.
Future<Map<String, dynamic>> savePhoto(
  Ditto ditto,
  String carId,
  Attachment photo,
) async {
  await ditto.store.execute(
    'INSERT INTO COLLECTION cars (photo ATTACHMENT) DOCUMENTS (:car)',
    arguments: {
      'car': {'_id': carId, 'photo': photo},
    },
  );
  final result = await ditto.store.execute(
    'SELECT * FROM COLLECTION cars (photo ATTACHMENT) WHERE _id = :id',
    arguments: {'id': carId},
  );
  return result.items.first.value['photo'] as Map<String, dynamic>;
}

/// Fetches the attachment behind [token]. The future completes with it; the
/// fetcher stops by itself once the fetch completes.
(AttachmentFetcher, Future<Attachment>) fetchPhoto(
  Ditto ditto,
  Map<String, dynamic> token,
) {
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
  return (fetcher, fetched.future);
}
// snippet:end flutter-attachments-2

final _photoBytes = Uint8List.fromList(
  List<int>.generate(1024, (i) => i % 256),
);

void main() {
  ensureProbeBinding();

  testWidgets('newAttachment from bytes and path with AttachmentMetadata '
      'wrapper', (t) async {
    await withDitto(t, (ditto) async {
      final directory = await Directory.systemTemp.createTemp('ditto_file_');
      try {
        final path = '${directory.path}/photo.bin';
        await File(path).writeAsBytes(_photoBytes);

        final fromBytes = await attachPhotoBytes(ditto, _photoBytes);
        final fromPath = await attachPhotoFile(ditto, path);

        expect(fromBytes.len, _photoBytes.length);
        expect(fromBytes.metadata, AttachmentMetadata({'name': 'photo.jpg'}));
        expect(fromBytes.metadata.metadata, {'name': 'photo.jpg'});
        expect(fromPath.len, _photoBytes.length);
        expect(fromPath.metadata.metadata, isEmpty);
        expect(await fromPath.data, _photoBytes);
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
      final attachment = await ditto.store.newAttachment(_photoBytes);
      final token = await savePhoto(ditto, 'car-1', attachment);

      final (fetcher, fetched) = fetchPhoto(ditto, token);
      expect(fetcher.isStopped, isFalse);
      final completed = await fetched.timeout(const Duration(seconds: 10));
      expect(completed.id, attachment.id);
      expect(await completed.data, _photoBytes);
      expect(fetcher.isStopped, isTrue);
      expect(ditto.store.attachmentFetchers, isNot(contains(fetcher)));
    });
  });
}
