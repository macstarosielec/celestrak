/// Smoke tests verifying that all example programs pass `dart analyze` and
/// meet the structural requirements for pub.dev (## Example section, no
/// internal tracking markers).
///
/// These tests do not make any network calls; they only inspect the source
/// text and invoke the Dart analyzer as a subprocess.
library;

import 'dart:io' show Directory, File, Process, ProcessResult;

import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helper — run dart analyze on a single file
// ---------------------------------------------------------------------------

Future<ProcessResult> _analyzeFile(String path) =>
    Process.run('dart', ['analyze', path]);

// ---------------------------------------------------------------------------
// Helper — read example source, resolving relative paths from the repo root
// ---------------------------------------------------------------------------

String _readExample(String filename) {
  // Tests run from the package root, so paths are relative to there.
  final file = File(filename);
  return file.readAsStringSync();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Sanity-check that we are running from the package root.
  setUpAll(() {
    expect(
      Directory('example').existsSync(),
      isTrue,
      reason: 'Tests must run from the package root.',
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Compilation checks — dart analyze must exit 0 for every example.
  // ═══════════════════════════════════════════════════════════════════════════

  group('example programs pass dart analyze', () {
    test('fetch_iss.dart compiles without errors', () async {
      final result = await _analyzeFile('example/fetch_iss.dart');

      expect(
        result.exitCode,
        equals(0),
        reason: 'dart analyze example/fetch_iss.dart failed:\n'
            '${result.stdout}${result.stderr}',
      );
    });

    test('offline_allow_stale.dart compiles without errors', () async {
      final result = await _analyzeFile('example/offline_allow_stale.dart');

      expect(
        result.exitCode,
        equals(0),
        reason: 'dart analyze example/offline_allow_stale.dart failed:\n'
            '${result.stdout}${result.stderr}',
      );
    });

    test('cache_inspect_clear.dart compiles without errors', () async {
      final result = await _analyzeFile('example/cache_inspect_clear.dart');

      expect(
        result.exitCode,
        equals(0),
        reason: 'dart analyze example/cache_inspect_clear.dart failed:\n'
            '${result.stdout}${result.stderr}',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Structural checks — ## Example dartdoc section for pub.dev points.
  // ═══════════════════════════════════════════════════════════════════════════

  group('example programs contain a ## Example dartdoc section', () {
    test('fetch_iss.dart has ## Example', () {
      final source = _readExample('example/fetch_iss.dart');
      expect(source, contains('## Example'));
    });

    test('offline_allow_stale.dart has ## Example', () {
      final source = _readExample('example/offline_allow_stale.dart');
      expect(source, contains('## Example'));
    });

    test('cache_inspect_clear.dart has ## Example', () {
      final source = _readExample('example/cache_inspect_clear.dart');
      expect(source, contains('## Example'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Hygiene checks — no internal tracking markers (CEL-xx).
  // ═══════════════════════════════════════════════════════════════════════════

  group('example programs contain no internal tracking markers', () {
    const markerPattern = r'CEL-\d+';

    test('fetch_iss.dart has no CEL-xx markers', () {
      final source = _readExample('example/fetch_iss.dart');
      expect(
        RegExp(markerPattern).hasMatch(source),
        isFalse,
        reason: 'Internal CEL-xx markers must not appear in example files.',
      );
    });

    test('offline_allow_stale.dart has no CEL-xx markers', () {
      final source = _readExample('example/offline_allow_stale.dart');
      expect(
        RegExp(markerPattern).hasMatch(source),
        isFalse,
        reason: 'Internal CEL-xx markers must not appear in example files.',
      );
    });

    test('cache_inspect_clear.dart has no CEL-xx markers', () {
      final source = _readExample('example/cache_inspect_clear.dart');
      expect(
        RegExp(markerPattern).hasMatch(source),
        isFalse,
        reason: 'Internal CEL-xx markers must not appear in example files.',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Content checks — examples reference the correct public API.
  // ═══════════════════════════════════════════════════════════════════════════

  group('example programs use the expected public API', () {
    test('fetch_iss.dart references fetchByNoradId and CelestrakClient', () {
      final source = _readExample('example/fetch_iss.dart');
      expect(source, contains('fetchByNoradId'));
      expect(source, contains('CelestrakClient'));
    });

    test('offline_allow_stale.dart references allowStale and fetchCategory',
        () {
      final source = _readExample('example/offline_allow_stale.dart');
      expect(source, contains('allowStale'));
      expect(source, contains('fetchCategory'));
    });

    test('cache_inspect_clear.dart references cacheAge and clearCache', () {
      final source = _readExample('example/cache_inspect_clear.dart');
      expect(source, contains('cacheAge'));
      expect(source, contains('clearCache'));
    });
  });
}
