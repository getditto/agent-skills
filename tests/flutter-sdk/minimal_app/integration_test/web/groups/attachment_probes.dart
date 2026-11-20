// Web probes: attachments are bytes-only on web.
import 'dart:typed_data';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../web_harness.dart';

final _bytes = Uint8List.fromList(List<int>.generate(1024, (i) => i % 256));

void attachmentProbes() {
  testWidgets('newAttachment(path) throws DittoException', (t) async {
    await withWebDitto((ditto) async {
      final outcome = await outcomeOf(
        () => ditto.store.newAttachment('/photos/photo.jpg'),
      );
      record('newAttachment(path)', outcome);
      // The returned Future fails; nothing is thrown at the call.
      expect(
        outcome,
        'async DittoException: DittoException(Creating attachments from files '
        'is not supported on Flutter Web.)',
      );
    });
  });

  testWidgets('newAttachment(Uint8List) succeeds', (t) async {
    await withWebDitto((ditto) async {
      final attachment = await ditto.store.newAttachment(
        _bytes,
        AttachmentMetadata({'name': 'photo.jpg'}),
      );
      record('newAttachment(Uint8List) len', attachment.len);
      expect(attachment.len, _bytes.length);
      expect(attachment.metadata.metadata, {'name': 'photo.jpg'});
    });
  });

  testWidgets('copyToPath throws', (t) async {
    await withWebDitto((ditto) async {
      final attachment = await ditto.store.newAttachment(_bytes);
      final outcome = await outcomeOf(
        () => attachment.copyToPath('/photos/copy.jpg'),
      );
      record('copyToPath', outcome);
      // A DittoException from the returned Future, not an UnsupportedError.
      expect(
        outcome,
        'async DittoException: DittoException(Retrieving a filesystem path '
        'for attachments is not supported on the Web.)',
      );
    });
  });

  testWidgets('Attachment.data works', (t) async {
    await withWebDitto((ditto) async {
      final attachment = await ditto.store.newAttachment(_bytes);
      final data = await attachment.data;
      record('Attachment.data length', data.length);
      expect(data, _bytes);
    });
  });
}
