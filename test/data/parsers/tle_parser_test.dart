// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:celestrak/src/data/parsers/tle_parser.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:test/test.dart';

void main() {
  const parser = TleParser();

  String loadFixture(String name) =>
      File('test/fixtures/$name').readAsStringSync();

  List<String> tleLines(String name) {
    final lines = loadFixture(name)
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    return lines;
  }

  group('TleParser.parse - ISS fixture', () {
    late List<String> lines;

    setUp(() => lines = tleLines('iss_25544.tle'));

    test('parses NORAD ID correctly', () {
      final tle = parser.parse(lines[0], lines[1], lines[2]);
      expect(tle.noradId, equals(25544));
    });

    test('parses name correctly', () {
      final tle = parser.parse(lines[0], lines[1], lines[2]);
      expect(tle.name, equals('ISS (ZARYA)'));
    });

    test('epoch is UTC', () {
      final tle = parser.parse(lines[0], lines[1], lines[2]);
      expect(tle.epoch.isUtc, isTrue);
    });

    test('epoch is June 1 2026', () {
      final tle = parser.parse(lines[0], lines[1], lines[2]);
      expect(tle.epoch.year, equals(2026));
      expect(tle.epoch.month, equals(6));
      expect(tle.epoch.day, equals(1));
    });

    test('classification is U', () {
      final tle = parser.parse(lines[0], lines[1], lines[2]);
      expect(tle.classification, equals('U'));
    });

    test('line1 and line2 are preserved verbatim (trimmed)', () {
      final tle = parser.parse(lines[0], lines[1], lines[2]);
      expect(tle.line1, equals(lines[1].trimRight()));
      expect(tle.line2, equals(lines[2].trimRight()));
    });

    test('fetchedAt defaults to a UTC timestamp', () {
      final before = DateTime.now().toUtc();
      final tle = parser.parse(lines[0], lines[1], lines[2]);
      final after = DateTime.now().toUtc();
      expect(tle.fetchedAt.isUtc, isTrue);
      expect(
        tle.fetchedAt.millisecondsSinceEpoch,
        inInclusiveRange(
          before.millisecondsSinceEpoch,
          after.millisecondsSinceEpoch,
        ),
      );
    });

    test('accepts explicit fetchedAt', () {
      final ts = DateTime.utc(2026, 6, 1, 12, 0);
      final tle = parser.parse(lines[0], lines[1], lines[2], fetchedAt: ts);
      expect(tle.fetchedAt, equals(ts));
    });

    test('verifyChecksum defaults to true (valid TLE passes)', () {
      expect(
        () => parser.parse(lines[0], lines[1], lines[2]),
        returnsNormally,
      );
    });
  });

  group('TleParser.parse - bad checksum', () {
    late List<String> lines;

    setUp(() => lines = tleLines('bad_checksum.tle'));

    test('throws TleParseException when checksum is wrong', () {
      expect(
        () => parser.parse(lines[0], lines[1], lines[2]),
        throwsA(isA<TleParseException>()),
      );
    });

    test('TleParseException.field is set to line1 on bad line1 checksum', () {
      expect(
        () => parser.parse(lines[0], lines[1], lines[2]),
        throwsA(
          isA<TleParseException>().having((e) => e.field, 'field', 'line1'),
        ),
      );
    });

    test('passes when verifyChecksum is false', () {
      expect(
        () => parser.parse(
          lines[0],
          lines[1],
          lines[2],
          verifyChecksum: false,
        ),
        returnsNormally,
      );
    });
  });

  group('TleParser.parseAll - stations group', () {
    late String body;

    setUp(() => body = loadFixture('stations_group.txt'));

    test('returns 3 satellites', () {
      final sats = parser.parseAll(body);
      expect(sats, hasLength(3));
    });

    test('first satellite is ISS with noradId 25544', () {
      final sats = parser.parseAll(body);
      expect(sats[0].noradId, equals(25544));
      expect(sats[0].name, equals('ISS (ZARYA)'));
    });

    test('second satellite is HUBBLE with noradId 20580', () {
      final sats = parser.parseAll(body);
      expect(sats[1].noradId, equals(20580));
      expect(sats[1].name, equals('HUBBLE'));
    });

    test('third satellite is TIANGONG with noradId 48274', () {
      final sats = parser.parseAll(body);
      expect(sats[2].noradId, equals(48274));
      expect(sats[2].name, equals('TIANGONG'));
    });

    test('throws TleParseException for body with non-multiple-of-3 lines', () {
      const oneRecord = 'ISS (ZARYA)\n'
          '1 25544U 98067A   26152.54166667  .00010768  00000-0  17455-4 0  9995\n';
      expect(
        () => parser.parseAll(oneRecord),
        throwsA(
            isA<TleParseException>().having((e) => e.field, 'field', isNull),),
      );
    });

    test('all satellites share the same fetchedAt timestamp', () {
      final ts = DateTime.utc(2026, 6, 1, 12);
      final sats = parser.parseAll(body, fetchedAt: ts);
      expect(sats.every((s) => s.fetchedAt == ts), isTrue);
    });

    test('parseAll with null fetchedAt stamps all satellites identically', () {
      final sats = parser.parseAll(body);
      expect(sats.map((s) => s.fetchedAt).toSet(), hasLength(1));
    });

    test('handles CRLF line endings', () {
      final crlf = body.replaceAll('\n', '\r\n');
      final sats = parser.parseAll(crlf);
      expect(sats, hasLength(3));
      expect(sats[0].noradId, equals(25544));
      expect(sats[0].line1, isNot(contains('\r')));
      expect(sats[0].line2, isNot(contains('\r')));
    });

    test('returns empty list for empty body', () {
      expect(parser.parseAll(''), isEmpty);
      expect(parser.parseAll('  \n  \n'), isEmpty);
    });
  });

  group('TleParser.parse - bad line2 checksum', () {
    // line1 is valid ISS; line2 has last digit changed from 1 → 9 (wrong checksum)
    const line0 = 'ISS (ZARYA)';
    const line1 =
        '1 25544U 98067A   26152.54166667  .00010768  00000-0  17455-4 0  9995';
    const badLine2 =
        '2 25544  51.6400 337.6640 0001234  90.0000 270.0000 15.49796647484939';

    test('throws TleParseException when line2 checksum is wrong', () {
      expect(
        () => parser.parse(line0, line1, badLine2),
        throwsA(isA<TleParseException>()),
      );
    });

    test('TleParseException.field is line2', () {
      expect(
        () => parser.parse(line0, line1, badLine2),
        throwsA(
            isA<TleParseException>().having((e) => e.field, 'field', 'line2'),),
      );
    });

    test('passes when verifyChecksum is false', () {
      expect(
        () => parser.parse(line0, line1, badLine2, verifyChecksum: false),
        returnsNormally,
      );
    });
  });

  group('TleParser.parse - alpha-5 NORAD IDs', () {
    // Replace NORAD field with 'A0001' (= 100001 in alpha-5). Checksum skipped.
    const line0 = 'STARLINK-X';
    const alpha5Line1 =
        '1 A0001U 20001A   26152.54166667  .00001000  00000-0  10000-4 0  9990';
    const line2 =
        '2 99999  53.0000 100.0000 0001000  45.0000 315.0000 15.00000000000001';

    test('decodes alpha-5 NORAD ID correctly', () {
      final tle =
          parser.parse(line0, alpha5Line1, line2, verifyChecksum: false);
      expect(tle.noradId, equals(100001));
    });

    test('throws TleParseException for truly invalid NORAD field', () {
      const invalidLine1 =
          '1 !0001U 20001A   26152.54166667  .00001000  00000-0  10000-4 0  9990';
      expect(
        () => parser.parse(line0, invalidLine1, line2, verifyChecksum: false),
        throwsA(
            isA<TleParseException>().having((e) => e.field, 'field', 'line1'),),
      );
    });

    test('throws TleParseException for noradId 0', () {
      const zeroLine1 =
          '1 00000U 20001A   26152.54166667  .00001000  00000-0  10000-4 0  9990';
      expect(
        () => parser.parse(line0, zeroLine1, line2, verifyChecksum: false),
        throwsA(
            isA<TleParseException>().having((e) => e.field, 'field', 'line1'),),
      );
    });
  });

  group('TleParser.parse - name trimming', () {
    const paddedLine0 = '  ISS (ZARYA)  ';
    const line1 =
        '1 25544U 98067A   26152.54166667  .00010768  00000-0  17455-4 0  9995';
    const line2 =
        '2 25544  51.6400 337.6640 0001234  90.0000 270.0000 15.49796647484931';

    test('strips leading and trailing whitespace from name', () {
      final tle = parser.parse(paddedLine0, line1, line2);
      expect(tle.name, equals('ISS (ZARYA)'));
    });
  });

  group('TleParseException', () {
    test('toString includes field when set', () {
      const e = TleParseException('bad data', field: 'line1');
      expect(e.toString(), contains('line1'));
      expect(e.toString(), contains('bad data'));
    });

    test('toString without field omits parentheses', () {
      const e = TleParseException('bad data');
      expect(e.toString(), equals('TleParseException: bad data'));
    });

    test('field is null when not provided', () {
      const e = TleParseException('something went wrong');
      expect(e.field, isNull);
    });

    test('is a CelestrakException', () {
      const e = TleParseException('msg');
      expect(e, isA<CelestrakException>());
    });
  });
}
