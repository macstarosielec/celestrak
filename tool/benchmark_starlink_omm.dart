/// Worst-case category parse benchmark — Starlink OMM JSON.
///
/// Generates a synthetic Starlink OMM JSON body of [_targetCount] entries
/// (matching the real Starlink constellation size) and measures the time
/// to JSON-decode + OmmParser.parseAllLazy on the main isolate.
///
/// Decision threshold: 16 ms (one Flutter frame budget on a mid-range device).
///
/// Run with:
///   dart run tool/benchmark_starlink_omm.dart
library;

import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:celestrak/src/data/parsers/omm_parser.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Number of OMM records to synthesise.
///
/// The live Starlink constellation sat at ~6 900 active satellites in mid-2026.
/// Using 7 000 as a conservative worst-case ceiling.
const _targetCount = 7000;

/// Frame-budget threshold in milliseconds.
const _budgetMs = 16;

/// Number of warm-up iterations (discarded).
const _warmupRuns = 3;

/// Number of measured iterations.
const _measuredRuns = 10;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main() {
  print('Celestrak Starlink OMM parse benchmark');
  print('========================================');
  print('Generating $_targetCount synthetic OMM records...');

  final json = _buildJsonString(_targetCount);
  final byteCount = json.length;
  print(
    'Payload size: ${(byteCount / 1024).toStringAsFixed(1)} kB '
    '(${(byteCount / 1024 / 1024).toStringAsFixed(2)} MB)',
  );
  print('');

  // Warm up the JIT / parse pipeline.
  print('Warming up ($_warmupRuns runs, discarded)...');
  for (var i = 0; i < _warmupRuns; i++) {
    _parseAll(json);
  }
  print('');

  // Measured runs.
  print('Measuring ($_measuredRuns runs)...');
  final durations = <int>[];
  for (var i = 0; i < _measuredRuns; i++) {
    final elapsed = _parseAll(json);
    durations.add(elapsed);
    print('  run ${i + 1}: $elapsed ms');
  }
  print('');

  durations.sort();
  // Lower-median for even N: index (N/2 - 1) is the middle-lower element.
  final median = durations[(_measuredRuns ~/ 2) - 1];
  final mean = durations.reduce((a, b) => a + b) ~/ _measuredRuns;
  final min = durations.first;
  final max = durations.last;
  final p99Index = (_measuredRuns * 0.99).ceil().clamp(0, durations.length - 1);
  final p99 = durations[p99Index];

  print('Results ($_targetCount records)');
  print('  min  : $min ms');
  print('  median: $median ms');
  print('  mean : $mean ms');
  print('  max  : $max ms');
  print('  p99  : $p99 ms');
  print('  budget: $_budgetMs ms');
  print('');

  if (median <= _budgetMs) {
    print(
      'DECISION: median ($median ms) <= budget ($_budgetMs ms) — '
      'synchronous parsing is safe. No isolate opt-in required.',
    );
  } else {
    print(
      'DECISION: median ($median ms) > budget ($_budgetMs ms) — '
      'isolate opt-in (useIsolate flag) MUST be added to CelestrakClient.',
    );
  }
}

// ---------------------------------------------------------------------------
// Benchmark helpers
// ---------------------------------------------------------------------------

/// Returns milliseconds elapsed for one full parse of [jsonString].
int _parseAll(String jsonString) {
  final sw = Stopwatch()..start();

  // Step 1: JSON decode.
  final decoded = jsonDecode(jsonString) as List<dynamic>;
  final jsonList = decoded.cast<Map<String, dynamic>>();

  // Step 2: OmmParser lazy parse (forces full materialisation via toList).
  const parser = OmmParser();
  parser.parseAllLazy(jsonList).toList();

  sw.stop();
  return sw.elapsedMilliseconds;
}

// ---------------------------------------------------------------------------
// Fixture generation
// ---------------------------------------------------------------------------

String _buildJsonString(int count) {
  final records = List.generate(count, _buildRecord);
  return jsonEncode(records);
}

Map<String, dynamic> _buildRecord(int i) {
  final noradId = 44713 + i;
  final satNum = 1007 + i;
  final objectId = '2019-${(74 + i ~/ 60).toString().padLeft(3, '0')}'
      '${String.fromCharCode(65 + i % 26)}';
  return {
    'OBJECT_NAME': 'STARLINK-$satNum',
    'OBJECT_ID': objectId,
    'CENTER_NAME': 'EARTH',
    'REF_FRAME': 'TEME',
    'TIME_SYSTEM': 'UTC',
    'MEAN_ELEMENT_THEORY': 'SGP4',
    'EPOCH': '2026-06-01T13:00:00.000000Z',
    'MEAN_MOTION': 15.06391419 + i * 0.000001,
    'ECCENTRICITY': 0.00012 - (i % 100) * 0.0000001,
    'INCLINATION': 53.054 + (i % 10) * 0.001,
    'RA_OF_ASC_NODE': 45.234 + (i % 360) * 0.001,
    'ARG_OF_PERICENTER': 100.0 + (i % 360),
    'MEAN_ANOMALY': 260.0 + (i % 360),
    'EPHEMERIS_TYPE': 0,
    'CLASSIFICATION_TYPE': 'U',
    'NORAD_CAT_ID': noradId,
    'ELEMENT_SET_NO': 999,
    'REV_AT_EPOCH': 38000 + i,
    'BSTAR': 0.00001 + i * 0.000000001,
    'MEAN_MOTION_DOT': 0.00001200 - i * 0.000000001,
    'MEAN_MOTION_DDOT': 0.0,
  };
}
