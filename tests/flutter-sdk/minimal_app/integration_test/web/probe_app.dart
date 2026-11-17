// The app scripts/web-probe.py builds in release mode (dart2js or --wasm)
// and loads in headless Chrome. Not a test: it runs one probe, chosen by the
// page's query string, and publishes the transcript as a JSON string in
// `globalThis.dittoProbe` ({"status": "done" | "error", "lines": [...]}).
//
//   ?mode=smoke          open, write, read back (the default)
//   ?mode=reload-write   write one document; the next page load reads it
//   ?mode=reload-read    count the documents left after a reload
//   ?mode=jank           insert 5,000 documents, then time SELECTs
//   &shim=relative       initialize with initDittoForSubpath() instead of
//                        Ditto.init()
//
// Web only (dart:js_interop). The license arrives as a define, like every
// fixture; the compiled bundle embeds it, so web-probe.py deletes the build.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const _license = String.fromEnvironment('DITTO_LICENSE');

// snippet:start flutter-web-2
/// Initializes Ditto for a web app served below the site root
/// (`flutter build web --base-href /app/`). Ditto loads its JavaScript
/// shim from the absolute path /assets/packages/ditto_live/lib/assets/
/// by default, which is outside /app/. A relative URL resolves against the
/// app's own script, next to its assets. Keep the `./`: a bare `assets/`
/// path is not a valid module specifier.
Future<void> initDittoForSubpath() => Ditto.init(
  wasmShimUrl: kIsWeb
      ? './assets/packages/ditto_live/lib/assets/ditto.wasm.js'
      : null,
);
// snippet:end flutter-web-2

void main() => runApp(const _ProbeApp());

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  final _lines = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  void _add(String line) {
    if (mounted) setState(() => _lines.add(line));
  }

  void _publish(String status) {
    final json = jsonEncode({'status': status, 'lines': _lines});
    globalContext.setProperty('dittoProbe'.toJS, json.toJS);
  }

  Future<void> _run() async {
    final query = Uri.base.queryParameters;
    try {
      _add('compiler: ${kIsWasm ? 'dart2wasm' : 'dart2js'}');
      _add('release: $kReleaseMode');
      _add('crossOriginIsolated: ${_jsBool('crossOriginIsolated')}');
      // ditto_live's web bridge keys its pointer registry on
      // Object.hashAll([JSString, JSNumber]); record the raw hash codes of
      // two JS strings and two JS numbers under this compiler.
      _add(
        'js hashCode: a=${'a'.toJS.hashCode} b=${'b'.toJS.hashCode} '
        '1=${1.toJS.hashCode} 2=${2.toJS.hashCode}',
      );
      if (query['shim'] == 'relative') {
        await initDittoForSubpath();
      } else {
        await Ditto.init();
      }
      _add('init: ok');
      final ditto = await Ditto.open(DittoConfig());
      try {
        ditto.setOfflineOnlyLicenseToken(_license);
        await switch (query['mode'] ?? 'smoke') {
          'reload-write' => _reloadWrite(ditto),
          'reload-read' => _reloadRead(ditto),
          'jank' => _jank(ditto),
          _ => _smoke(ditto),
        };
      } finally {
        await ditto.close();
      }
      _publish('done');
    } catch (error) {
      _add('error: $error');
      _publish('error');
    }
  }

  Future<void> _smoke(Ditto ditto) async {
    final inserted = await ditto.store.execute(
      'INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE',
      arguments: {
        'car': {'_id': 'blue-toyota', 'make': 'Toyota'},
      },
    );
    _add('insert mutated: ${inserted.mutatedDocumentIDs()}');
    final literal = await ditto.store.execute(
      "INSERT INTO cars DOCUMENTS ({'_id': 'red-honda', 'make': 'Honda'}) "
      'ON ID CONFLICT DO UPDATE',
    );
    _add('literal insert mutated: ${literal.mutatedDocumentIDs()}');
    final result = await ditto.store.execute('SELECT * FROM cars');
    _add('select items: ${result.items.length}');
    final makes = result.items.map((item) => item.value['make']).toList();
    _add('select makes: $makes');
    final blue = result.items.where(
      (item) => item.value['_id'] == 'blue-toyota',
    );
    _add('read-back make: ${blue.firstOrNull?.value['make']}');
    final version = RegExp(r'\d+\.\d+\.\d+').firstMatch(Ditto.version);
    _add('SDK version: ${version?.group(0)}');
  }

  Future<void> _reloadWrite(Ditto ditto) async {
    await ditto.store.execute(
      'INSERT INTO reload DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE',
      arguments: {
        'doc': {'_id': 'before-reload'},
      },
    );
    final result = await ditto.store.execute('SELECT * FROM reload');
    _add('documents before reload: ${result.items.length}');
  }

  Future<void> _reloadRead(Ditto ditto) async {
    final result = await ditto.store.execute('SELECT * FROM reload');
    _add('documents after reload: ${result.items.length}');
  }

  Future<void> _jank(Ditto ditto) async {
    const total = 5000;
    const batch = 100;
    final notes = 'x' * 200;
    for (var start = 0; start < total; start += batch) {
      final arguments = <String, dynamic>{};
      final values = <String>[];
      for (var i = start; i < start + batch; i++) {
        arguments['d$i'] = {
          '_id': 'car-$i',
          'make': 'make-${i % 17}',
          'year': 1990 + i % 30,
          'notes': notes,
        };
        values.add('(:d$i)');
      }
      await ditto.store.execute(
        'INSERT INTO jank DOCUMENTS ${values.join(', ')}',
        arguments: arguments,
      );
    }
    _add('inserted: $total');
    // Let a few frames render, so the page's frame log has a baseline.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    for (final (label, query, decode) in [
      ('select all', 'SELECT * FROM jank', false),
      ('select all + values', 'SELECT * FROM jank', true),
      ('select limit 50 + values', 'SELECT * FROM jank LIMIT 50', true),
    ]) {
      final startedAt = _now();
      final watch = Stopwatch()..start();
      final result = await ditto.store.execute(query);
      // Items decode lazily: `.value` parses each one's JSON, synchronously,
      // on this (the page's only) thread.
      final items = decode
          ? result.items.map((item) => item.value).toList().length
          : result.items.length;
      watch.stop();
      final endedAt = _now();
      _add(
        '$label: items=$items ms=${watch.elapsedMilliseconds} '
        'window=${startedAt.toStringAsFixed(1)}-${endedAt.toStringAsFixed(1)}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  double _now() => (globalContext.getProperty<JSObject>(
    'performance'.toJS,
  )).callMethod<JSNumber>('now'.toJS).toDartDouble;

  bool? _jsBool(String name) =>
      globalContext.getProperty<JSBoolean?>(name.toJS)?.toDart;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _lines.join('\n'),
          style: const TextStyle(color: Color(0xFF000000), fontSize: 16),
        ),
      ),
    ),
  );
}
