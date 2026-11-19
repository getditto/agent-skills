// snippet:start flutter-minimal-main
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'minimal_app.dart';

const _license = String.fromEnvironment('DITTO_LICENSE');

void main() => runApp(const TranscriptApp());

/// Runs [runMinimalApp] once and renders its transcript.
class TranscriptApp extends StatefulWidget {
  const TranscriptApp({super.key});

  @override
  State<TranscriptApp> createState() => _TranscriptAppState();
}

class _TranscriptAppState extends State<TranscriptApp> {
  final _lines = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(
      runMinimalApp(license: _license, onLine: _add).catchError((Object error) {
        _add('error: $error');
        return _lines;
      }),
    );
  }

  void _add(String line) {
    // Also on stdout, so a build run from the command line shows it.
    debugPrint('transcript: $line');
    if (mounted) setState(() => _lines.add(line));
  }

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
// snippet:end flutter-minimal-main
