import 'dart:convert';
import 'dart:io';

import 'package:celestrak/src/data/parsers/omm_parser.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/omm.dart';
import 'package:test/test.dart';

import '../../support/recording_benchmark_hook.dart';

List<Map<String, dynamic>> loadOmmFixture(String name) {
  final content = File('test/fixtures/$name').readAsStringSync();
  return (jsonDecode(content) as List<dynamic>).cast<Map<String, dynamic>>();
}

void main() {
  const parser = OmmParser();

  group('OmmParser.parseAllLazy — stations group', () {
    late List<Map<String, dynamic>> jsonList;

    setUp(() => jsonList = loadOmmFixture('stations_group_omm.json'));

    test('is an Iterable<Omm>', () {
      expect(parser.parseAllLazy(jsonList), isA<Iterable<Omm>>());
    });

    test('yields 3 Omm records', () {
      expect(parser.parseAllLazy(jsonList), hasLength(3));
    });

    test('first record is ISS (noradCatId 25544)', () {
      final first = parser.parseAllLazy(jsonList).first;
      expect(first.noradCatId, equals(25544));
      expect(first.objectName, equals('ISS (ZARYA)'));
    });

    test('second record is HUBBLE (noradCatId 20580)', () {
      final second = parser.parseAllLazy(jsonList).elementAt(1);
      expect(second.noradCatId, equals(20580));
      expect(second.objectName, equals('HUBBLE'));
    });

    test('third record is TIANGONG (noradCatId 48274)', () {
      final third = parser.parseAllLazy(jsonList).elementAt(2);
      expect(third.noradCatId, equals(48274));
    });

    test('parseAllLazy and manual map(parse) yield identical records', () {
      final lazy = parser.parseAllLazy(jsonList).toList();
      final eager = jsonList.map(parser.parse).toList();
      for (var i = 0; i < eager.length; i++) {
        expect(lazy[i].noradCatId, equals(eager[i].noradCatId));
        expect(lazy[i].objectName, equals(eager[i].objectName));
        expect(lazy[i].epoch, equals(eager[i].epoch));
      }
    });

    test('returns empty iterable for empty list', () {
      expect(parser.parseAllLazy([]), isEmpty);
    });

    test(
      'throws OmmParseException on first malformed entry',
      () {
        final bad = [
          <String, dynamic>{'OBJECT_NAME': 'BAD'},
          ...jsonList,
        ];
        expect(
          () => parser.parseAllLazy(bad).toList(),
          throwsA(isA<OmmParseException>()),
        );
      },
    );

    test(
      'processes entries before the bad one successfully',
      () {
        // Good entry first, then bad entry.
        final mixed = [
          jsonList[0],
          <String, dynamic>{'OBJECT_NAME': 'BAD'},
        ];
        final emitted = <Omm>[];
        expect(
          () {
            for (final omm in parser.parseAllLazy(mixed)) {
              emitted.add(omm);
            }
          },
          throwsA(isA<OmmParseException>()),
        );
        // The first (good) record was already yielded before the exception.
        expect(emitted, hasLength(1));
        expect(emitted.first.noradCatId, equals(25544));
      },
    );
  });

  group('OmmParser.parseAllLazy — benchmark hook', () {
    late RecordingBenchmarkHook hook;
    late OmmParser hookedParser;
    late List<Map<String, dynamic>> jsonList;

    setUp(() {
      hook = RecordingBenchmarkHook();
      hookedParser = OmmParser(benchmarkHook: hook);
      jsonList = loadOmmFixture('stations_group_omm.json');
    });

    test('onParseStart is called once with label "omm"', () {
      hookedParser.parseAllLazy(jsonList).toList();
      expect(hook.starts, equals(['omm']));
    });

    test('onParseEnd is called once with correct recordCount', () {
      hookedParser.parseAllLazy(jsonList).toList();
      expect(hook.ends, hasLength(1));
      expect(hook.ends.first.$1, equals('omm'));
      expect(hook.ends.first.$2, equals(3));
    });

    test('onParseEnd elapsed is non-negative', () {
      hookedParser.parseAllLazy(jsonList).toList();
      expect(hook.ends.first.$3.inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('hook is not called for empty list', () {
      hookedParser.parseAllLazy([]).toList();
      expect(hook.starts, isEmpty);
      expect(hook.ends, isEmpty);
    });

    test(
      'onParseEnd is called after OmmParseException (finally block)',
      () {
        final bad = [
          <String, dynamic>{'OBJECT_NAME': 'BAD'},
        ];
        expect(
          () => hookedParser.parseAllLazy(bad).toList(),
          throwsA(isA<OmmParseException>()),
        );
        expect(hook.ends, hasLength(1));
        expect(hook.ends.first.$2, equals(0));
      },
    );

    test('NullParseBenchmarkHook is the default (no crash)', () {
      const defaultParser = OmmParser();
      expect(
        () => defaultParser.parseAllLazy(jsonList).toList(),
        returnsNormally,
      );
    });
  });
}
