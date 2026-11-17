import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness.dart';

// snippet:start flutter-anti-patterns-1
// Anti-pattern: the widget tree subscribes directly to an observer's
// single-subscription `changes` stream.
class LeakyRepository {
  LeakyRepository(Ditto ditto)
    : observer = ditto.store.registerObserver('SELECT * FROM probes');

  final StoreObserver observer;

  Stream<QueryResult> get changes => observer.changes;
}

class LeakyScreen extends StatelessWidget {
  const LeakyScreen({super.key, required this.repository});

  final LeakyRepository repository;

  @override
  Widget build(BuildContext context) => StreamBuilder<QueryResult>(
    // Disposing this StreamBuilder cancels its listener but not the observer;
    // building the screen again listens a second time and throws StateError.
    stream: repository.changes,
    builder:
        (context, snapshot) => Text('${snapshot.data?.items.length ?? 0} docs'),
  );
}
// snippet:end flutter-anti-patterns-1

// snippet:start flutter-observers-2
/// Owns the observer for as long as the data is needed, independent of any
/// one widget. Screens listen to [docs]; [dispose] cancels the observer.
class ProbesRepository {
  ProbesRepository(Ditto ditto) {
    _observer = ditto.store.registerObserver(
      'SELECT * FROM probes',
      onChange: (result) {
        docs.value = result.items.map((item) => item.value).toList();
      },
    );
  }

  final docs = ValueNotifier<List<Map<String, dynamic>>>(const []);
  late final StoreObserver _observer;

  bool get isObserving => !_observer.isCancelled;

  void dispose() {
    _observer.cancel();
    docs.dispose();
  }
}

class ProbesScreen extends StatelessWidget {
  const ProbesScreen({super.key, required this.repository});

  final ProbesRepository repository;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repository.docs,
    builder: (context, _) => Text('${repository.docs.value.length} docs'),
  );
}
// snippet:end flutter-observers-2

Widget _app(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reentered widget leaks v1 observer and second listen throws', (
    t,
  ) async {
    await withDitto(t, (ditto) async {
      final leaky = LeakyRepository(ditto);
      try {
        await t.pumpWidget(_app(LeakyScreen(repository: leaky)));
        expect(t.takeException(), isNull);

        // Leave the screen, then enter it again.
        await t.pumpWidget(_app(const SizedBox()));
        expect(leaky.observer.isCancelled, isFalse);
        await t.pumpWidget(_app(LeakyScreen(repository: leaky)));
        expect(
          t.takeException(),
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Stream has already been listened to.',
          ),
        );
        expect(leaky.observer.isCancelled, isFalse);
      } finally {
        await t.pumpWidget(_app(const SizedBox()));
        leaky.observer.cancel();
      }

      // The corrected pattern: the repository owns the observer.
      final repository = ProbesRepository(ditto);
      await t.pumpWidget(_app(ProbesScreen(repository: repository)));
      await ditto.store.execute(
        'INSERT INTO probes DOCUMENTS (:doc)',
        arguments: {
          'doc': {'_id': 'a'},
        },
      );
      await waitUntil(() => repository.docs.value.length == 1);
      await t.pump();
      expect(find.text('1 docs'), findsOneWidget);

      await t.pumpWidget(_app(const SizedBox()));
      await t.pumpWidget(_app(ProbesScreen(repository: repository)));
      expect(t.takeException(), isNull);
      expect(find.text('1 docs'), findsOneWidget);
      expect(repository.isObserving, isTrue);

      await t.pumpWidget(_app(const SizedBox()));
      repository.dispose();
      expect(repository.isObserving, isFalse);
    });
  });
}
