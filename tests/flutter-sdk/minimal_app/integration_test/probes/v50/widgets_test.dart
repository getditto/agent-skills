import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// snippet:start flutter-anti-patterns-1
// Anti-pattern: the widget tree subscribes directly to an observer's
// single-subscription `changes` stream.
class LeakyCarsRepository {
  LeakyCarsRepository(Ditto ditto)
    : observer = ditto.store.registerObserver('SELECT * FROM cars');

  final StoreObserver observer;

  Stream<QueryResult> get changes => observer.changes;
}

class LeakyCarsScreen extends StatelessWidget {
  const LeakyCarsScreen({super.key, required this.repository});

  final LeakyCarsRepository repository;

  @override
  Widget build(BuildContext context) => StreamBuilder<QueryResult>(
    // Disposing this StreamBuilder cancels its listener but not the observer;
    // building the screen again listens a second time and throws StateError.
    stream: repository.changes,
    builder: (context, snapshot) =>
        Text('${snapshot.data?.items.length ?? 0} cars'),
  );
}
// snippet:end flutter-anti-patterns-1

// snippet:start flutter-observers-2
/// Owns the observer for as long as the data is needed, independent of any
/// one widget. Screens listen to [cars]; [dispose] stops observing.
class CarsRepository {
  CarsRepository(Ditto ditto) {
    // No onChange (it would also buffer every result in the unlistened
    // `changes` stream, 5.0.0 through 5.2.0). This class holds the one
    // `changes` listener, started right away.
    _observer = ditto.store.registerObserver('SELECT * FROM cars');
    _changes = _observer.changes.listen((result) {
      cars.value = result.items.map((item) => item.value).toList();
    });
  }

  final cars = ValueNotifier<List<Map<String, dynamic>>>(const []);
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;

  bool get isObserving => !_observer.isCancelled;

  /// Call while Ditto is still open: the listener first, then the observer.
  Future<void> dispose() async {
    await _changes.cancel();
    _observer.cancel();
    cars.dispose();
  }
}

class CarsScreen extends StatelessWidget {
  const CarsScreen({super.key, required this.repository});

  final CarsRepository repository;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repository.cars,
    builder: (context, _) => Text('${repository.cars.value.length} cars'),
  );
}
// snippet:end flutter-observers-2

// snippet:start flutter-widgets-1
/// Owns the app's one Ditto instance. Open it once, before runApp; close it
/// only when the app exits.
class DittoService {
  DittoService._(this.ditto);

  final Ditto ditto;

  /// Opens Ditto, then runs [configure]: the license or expiration handler,
  /// transports, sync.start(). If [configure] throws, the instance is closed
  /// again, so its persistence directory is not left locked.
  static Future<DittoService> open({
    DittoConfig config = const DittoConfig(),
    required Future<void> Function(Ditto ditto) configure,
  }) async {
    // Required on 5.0.x, automatic from 5.1.0; memoized.
    await Ditto.init();
    final ditto = await Ditto.open(config);
    try {
      await configure(ditto);
    } catch (_) {
      await ditto.close();
      rethrow;
    }
    return DittoService._(ditto);
  }

  /// Closes Ditto. Cancel observers first, while it is still open.
  Future<void> close() => ditto.close();
}

/// The app's entry point, e.g.
/// `Future<void> main() => startCarsApp(configureDitto);`
/// Pass [config] only to change the connect mode or, in debug builds, the
/// directory; an app keeps the SDK default persistence directory.
Future<void> startCarsApp(
  Future<void> Function(Ditto ditto) configure, {
  DittoConfig config = const DittoConfig(),
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final service = await DittoService.open(config: config, configure: configure);
  runApp(CarsApp(service: service));
}
// snippet:end flutter-widgets-1

// snippet:start flutter-widgets-2
/// Presentation state for the cars screen, derived from the repository.
class CarsViewModel extends ChangeNotifier {
  CarsViewModel(this._repository) {
    _repository.cars.addListener(notifyListeners);
  }

  final CarsRepository _repository;

  int get carCount => _repository.cars.value.length;

  @override
  void dispose() {
    _repository.cars.removeListener(notifyListeners);
    super.dispose();
  }
}

/// The root widget. Owns the repository and view model, and ties sync and
/// shutdown to the app lifecycle.
class CarsApp extends StatefulWidget {
  const CarsApp({
    super.key,
    required this.service,
    this.syncInBackground = false,
  });

  final DittoService service;

  /// Whether sync keeps running while a mobile app is paused.
  final bool syncInBackground;

  @override
  State<CarsApp> createState() => _CarsAppState();
}

class _CarsAppState extends State<CarsApp> {
  late final _repository = CarsRepository(widget.service.ditto);
  late final _viewModel = CarsViewModel(_repository);
  late final AppLifecycleListener _lifecycle;

  // Cancels the observer once, on exit or unmount, whichever comes first.
  late final Future<void> _stopObserving = _repository.dispose();

  @override
  void initState() {
    super.initState();
    final sync = widget.service.ditto.sync;
    _lifecycle = AppLifecycleListener(
      // Called on iOS and Android only.
      onPause: widget.syncInBackground ? null : sync.stop,
      onRestart: widget.syncInBackground ? null : sync.start,
      // Called only for exits the platform lets the app cancel (desktop).
      onExitRequested: () async {
        await _stopObserving;
        await widget.service.close();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _viewModel.dispose();
    unawaited(_stopObserving);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    // Your WidgetsApp or MaterialApp goes here.
    textDirection: TextDirection.ltr,
    child: CarsPage(viewModel: _viewModel),
  );
}

class CarsPage extends StatelessWidget {
  const CarsPage({super.key, required this.viewModel});

  final CarsViewModel viewModel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) => Text('${viewModel.carCount} cars'),
  );
}
// snippet:end flutter-widgets-2

// snippet:start flutter-widgets-3
/// A small app: the screen owns its observer.
class CarCountScreen extends StatefulWidget {
  const CarCountScreen({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<CarCountScreen> createState() => _CarCountScreenState();
}

class _CarCountScreenState extends State<CarCountScreen> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  var _count = 0;

  @override
  void initState() {
    super.initState();
    // No onChange: this state holds the one `changes` listener.
    _observer = widget.ditto.store.registerObserver('SELECT * FROM cars');
    _changes = _observer.changes.listen((result) {
      if (!mounted) return;
      setState(() => _count = result.items.length);
    });
  }

  @override
  void dispose() {
    // dispose() cannot await. Ditto must still be open here.
    unawaited(_changes.cancel());
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('$_count cars');
}
// snippet:end flutter-widgets-3

/// Pumps frames until [finder] matches, for up to 10 s.
Future<void> _pumpUntilFound(WidgetTester t, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('not found: $finder');
    await t.pump(const Duration(milliseconds: 50));
  }
}

Widget _app(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  ensureProbeBinding();

  testWidgets('reentered widget leaks v1 observer and second listen throws', (
    t,
  ) async {
    await withDitto(t, (ditto) async {
      final leaky = LeakyCarsRepository(ditto);
      try {
        await t.pumpWidget(_app(LeakyCarsScreen(repository: leaky)));
        expect(t.takeException(), isNull);

        // Leave the screen, then enter it again.
        await t.pumpWidget(_app(const SizedBox()));
        expect(leaky.observer.isCancelled, isFalse);
        await t.pumpWidget(_app(LeakyCarsScreen(repository: leaky)));
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
      final repository = CarsRepository(ditto);
      await t.pumpWidget(_app(CarsScreen(repository: repository)));
      await ditto.store.execute(
        'INSERT INTO cars DOCUMENTS (:car)',
        arguments: {
          'car': {'_id': 'car-1'},
        },
      );
      await waitUntil(() => repository.cars.value.length == 1);
      await t.pump();
      expect(find.text('1 cars'), findsOneWidget);

      await t.pumpWidget(_app(const SizedBox()));
      await t.pumpWidget(_app(CarsScreen(repository: repository)));
      expect(t.takeException(), isNull);
      expect(find.text('1 cars'), findsOneWidget);
      expect(repository.isObserving, isTrue);

      await t.pumpWidget(_app(const SizedBox()));
      await repository.dispose();
      expect(repository.isObserving, isFalse);
    });
  });

  testWidgets('DittoService closes the instance when configure throws', (
    t,
  ) async {
    await withProbeDirectory((path) async {
      final config = DittoConfig(persistenceDirectory: path);
      await expectLater(
        DittoService.open(
          config: config,
          configure: (ditto) async => throw StateError('configure failed'),
        ),
        throwsA(isA<StateError>()),
      );
      // The directory is not locked: the failed instance was closed.
      final service = await DittoService.open(
        config: config,
        configure: (ditto) async {
          ditto.setOfflineOnlyLicenseToken(license);
          disablePeerToPeer(ditto);
          ditto.sync.start();
        },
      );
      final p2p = service.ditto.transportConfig.peerToPeer;
      expect([
        p2p.bluetoothLE.isEnabled,
        p2p.lan.isEnabled,
        p2p.awdl.isEnabled,
        p2p.wifiAware.isEnabled,
      ], everyElement(isFalse));
      await service.close();
    });
  });

  testWidgets('CarsApp: lifecycle stops and restarts sync, exit closes', (
    t,
  ) async {
    await withProbeDirectory((path) async {
      final service = await DittoService.open(
        config: DittoConfig(persistenceDirectory: path),
        configure: (ditto) async {
          ditto.setOfflineOnlyLicenseToken(license);
          disablePeerToPeer(ditto);
          ditto.sync.start();
        },
      );
      try {
        final ditto = service.ditto;
        await t.pumpWidget(CarsApp(service: service));
        await ditto.store.execute(
          'INSERT INTO cars DOCUMENTS (:car)',
          arguments: {
            'car': {'_id': 'car-1'},
          },
        );
        await _pumpUntilFound(t, find.text('1 cars'));
        expect(ditto.sync.isActive, isTrue);

        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          t.binding.handleAppLifecycleStateChanged(state);
        }
        expect(ditto.sync.isActive, isFalse);
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          t.binding.handleAppLifecycleStateChanged(state);
        }
        expect(ditto.sync.isActive, isTrue);

        expect(await t.binding.handleRequestAppExit(), AppExitResponse.exit);
        expect(ditto.isClosed, isTrue);
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      } finally {
        await service.close();
      }
    });
  });

  testWidgets('CarCountScreen: re-entering works, dispose cancels', (t) async {
    await withDitto(t, (ditto) async {
      ditto.sync.start();
      await t.pumpWidget(_app(CarCountScreen(ditto: ditto)));
      await ditto.store.execute(
        'INSERT INTO cars DOCUMENTS (:car)',
        arguments: {
          'car': {'_id': 'car-1'},
        },
      );
      await _pumpUntilFound(t, find.text('1 cars'));
      StoreObserver observerOf() =>
          t.state<_CarCountScreenState>(find.byType(CarCountScreen))._observer;
      final first = observerOf();
      expect(first.isCancelled, isFalse);
      await t.pumpWidget(_app(const SizedBox()));
      expect(first.isCancelled, isTrue);

      await t.pumpWidget(_app(CarCountScreen(ditto: ditto)));
      expect(t.takeException(), isNull);
      await _pumpUntilFound(t, find.text('1 cars'));
      final second = observerOf();
      expect(second, isNot(same(first)));
      await t.pumpWidget(_app(const SizedBox()));
      expect(t.takeException(), isNull);
      expect(second.isCancelled, isTrue);
    });
  });
}
