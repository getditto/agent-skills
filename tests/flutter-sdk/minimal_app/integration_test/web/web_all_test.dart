// The Flutter Web probes, as one `flutter drive` target (it takes a single
// file):
//
//   tests/flutter-sdk/scripts/run-fixture.sh minimal_app chrome 5.2 \
//     integration_test/web/web_all_test.dart
//
// Compiles against ditto_live 5.0.4 and later. The 5.1+ probes are in
// web_51_test.dart, and `bad offline license on web` in
// web_license_test.dart (a fresh page), separate targets. The driver prints every recorded
// value as `transcript: <probe>: <value>`.
import 'groups/attachment_probes.dart';
import 'groups/lifecycle_probes.dart';
import 'groups/platform_probes.dart';
import 'web_harness.dart';

void main() {
  ensureWebProbeBinding();
  platformProbes();
  attachmentProbes();
  lifecycleProbes();
}
