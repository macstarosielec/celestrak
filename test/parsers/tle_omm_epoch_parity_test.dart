import 'dart:convert';
import 'dart:io';

import 'package:celestrak/src/data/parsers/omm_parser.dart';
import 'package:celestrak/src/data/parsers/tle_parser.dart';
import 'package:test/test.dart';

void main() {
  group('TLE/OMM epoch parity', () {
    test('ISS TLE and OMM fixtures yield identical noradId and UTC epoch', () {
      final tleContent = File('test/fixtures/iss_25544.tle').readAsStringSync();
      final tleLines = tleContent
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final parsedTle = const TleParser().parse(
        tleLines[0],
        tleLines[1],
        tleLines[2],
      );

      final ommContent =
          File('test/fixtures/iss_25544_omm.json').readAsStringSync();
      final ommArray = jsonDecode(ommContent) as List<dynamic>;
      final parsedOmm =
          const OmmParser().parse(ommArray.first as Map<String, dynamic>);

      expect(parsedTle.noradId, equals(parsedOmm.noradCatId));

      // The TLE epoch field ('26152.54166667') is parsed via a floating-point
      // chain (double.parse → fractional-day arithmetic) that can accumulate
      // rounding error of up to ~1 µs across platforms and compiler
      // optimisations.  The OMM epoch is an ISO-8601 string parsed with
      // sub-millisecond precision ('2026-06-01T13:00:00.000288Z').  Both
      // encode the same instant (13:00:00.000288 UTC on day 152 of 2026), but
      // strict DateTime equality would flake on a 1-µs discrepancy.  We
      // therefore accept any agreement within 1 millisecond.
      const epochTolerance = Duration(milliseconds: 1);
      expect(
        parsedTle.epoch.difference(parsedOmm.epoch).abs(),
        lessThan(epochTolerance),
        reason: 'TLE and OMM epochs must agree within 1 ms',
      );

      expect(parsedTle.epoch.isUtc, isTrue);
      expect(parsedOmm.epoch.isUtc, isTrue);
    });
  });
}
