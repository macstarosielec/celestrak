// TLE fixture strings necessarily exceed 80 chars; suppressed for readability.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:celestrak/src/data/parsers/tle_parser.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/satellite_tle.dart';
import 'package:test/test.dart';

import '../../support/recording_benchmark_hook.dart';

String loadFixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  const parser = TleParser();

  group('TleParser.parseAllLazy — stations group', () {
    late String body;

    setUp(() => body = loadFixture('stations_group.txt'));

    test('is an Iterable<SatelliteTle>', () {
      final result = parser.parseAllLazy(body);
      expect(result, isA<Iterable<SatelliteTle>>());
    });

    test('yields 3 satellites', () {
      expect(parser.parseAllLazy(body), hasLength(3));
    });

    test('first satellite is ISS (noradId 25544)', () {
      final first = parser.parseAllLazy(body).first;
      expect(first.noradId, equals(25544));
      expect(first.name, equals('ISS (ZARYA)'));
    });

    test('second satellite is HUBBLE (noradId 20580)', () {
      final second = parser.parseAllLazy(body).elementAt(1);
      expect(second.noradId, equals(20580));
    });

    test('third satellite is TIANGONG (noradId 48274)', () {
      final third = parser.parseAllLazy(body).elementAt(2);
      expect(third.noradId, equals(48274));
    });

    test('all satellites share the same fetchedAt timestamp', () {
      final ts = DateTime.utc(2026, 6, 1, 12);
      final sats = parser.parseAllLazy(body, fetchedAt: ts).toList();
      expect(sats.every((s) => s.fetchedAt == ts), isTrue);
    });

    test('parseAllLazy and parseAll yield identical records', () {
      final ts = DateTime.utc(2026, 6, 1, 12);
      final lazy = parser.parseAllLazy(body, fetchedAt: ts).toList();
      final eager = parser.parseAll(body, fetchedAt: ts);
      expect(lazy, equals(eager));
    });

    test('handles CRLF line endings', () {
      final crlf = body.replaceAll('\n', '\r\n');
      final sats = parser.parseAllLazy(crlf).toList();
      expect(sats, hasLength(3));
      expect(sats[0].noradId, equals(25544));
      expect(sats[0].line1, isNot(contains('\r')));
    });

    test('returns empty iterable for empty body', () {
      expect(parser.parseAllLazy(''), isEmpty);
      expect(parser.parseAllLazy('  \n  '), isEmpty);
    });

    test(
      'throws TleParseException for non-multiple-of-3 lines',
      () {
        const twoLineBody = 'ISS (ZARYA)\n'
            '1 25544U 98067A   26152.54166667  .00010768  00000-0  17455-4 0  9995\n';
        expect(
          () => parser.parseAllLazy(twoLineBody).toList(),
          throwsA(
            isA<TleParseException>().having((e) => e.field, 'field', isNull),
          ),
        );
      },
    );

    test('verifyChecksum:false passes bad checksum records', () {
      final lines = loadFixture('bad_checksum.tle');
      expect(
        () => parser.parseAllLazy(lines, verifyChecksum: false).toList(),
        returnsNormally,
      );
    });
  });

  group('TleParser.parseAllLazy — benchmark hook', () {
    late RecordingBenchmarkHook hook;
    late TleParser hookedParser;
    late String body;

    setUp(() {
      hook = RecordingBenchmarkHook();
      hookedParser = TleParser(benchmarkHook: hook);
      body = loadFixture('stations_group.txt');
    });

    test('onParseStart is called once with label "tle"', () {
      hookedParser.parseAllLazy(body).toList();
      expect(hook.starts, equals(['tle']));
    });

    test('onParseEnd is called once with correct recordCount', () {
      hookedParser.parseAllLazy(body).toList();
      expect(hook.ends, hasLength(1));
      expect(hook.ends.first.$1, equals('tle'));
      expect(hook.ends.first.$2, equals(3));
    });

    test('onParseEnd elapsed is non-negative', () {
      hookedParser.parseAllLazy(body).toList();
      expect(hook.ends.first.$3.inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('hook is not called for empty body', () {
      hookedParser.parseAllLazy('').toList();
      expect(hook.starts, isEmpty);
      expect(hook.ends, isEmpty);
    });

    test(
      'hook is not called when TleParseException is thrown by guard check',
      () {
        // The non-multiple-of-3 guard fires before onParseStart, so neither
        // start nor end signals are emitted — the body was structurally
        // invalid before any parsing began.
        const twoLineBody = 'ISS\n'
            '1 25544U 98067A   26152.54166667  .00010768  00000-0  17455-4 0  9995\n';
        expect(
          () => hookedParser.parseAllLazy(twoLineBody).toList(),
          throwsA(isA<TleParseException>()),
        );
        expect(hook.starts, isEmpty);
        expect(hook.ends, isEmpty);
      },
    );

    test('NullParseBenchmarkHook is the default (no crash)', () {
      const defaultParser = TleParser();
      expect(
        () => defaultParser.parseAllLazy(body).toList(),
        returnsNormally,
      );
    });
  });
}
