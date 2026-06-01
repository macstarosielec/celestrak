import 'dart:convert';
import 'dart:io';

import 'package:celestrak/src/data/parsers/omm_parser.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:test/test.dart';

void main() {
  const parser = OmmParser();

  Map<String, dynamic> loadFixture(String name) {
    final content = File('test/fixtures/$name').readAsStringSync();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  group('OmmParser.parse - ISS fixture', () {
    late Map<String, dynamic> json;

    setUp(() => json = loadFixture('iss_omm.json'));

    test('parses all fields correctly', () {
      final omm = parser.parse(json);

      expect(omm.objectName, equals('ISS (ZARYA)'));
      expect(omm.objectId, equals('1998-067A'));
      expect(omm.epoch, equals(DateTime.utc(2026, 6, 1, 13, 0)));
      expect(omm.epoch.isUtc, isTrue);
      expect(omm.centerName, equals('EARTH'));
      expect(omm.refFrame, equals('TEME'));
      expect(omm.timeSystem, equals('UTC'));
      expect(omm.meanElementTheory, equals('SGP4'));
      expect(omm.meanMotion, equals(15.49796647));
      expect(omm.eccentricity, equals(0.0005801));
      expect(omm.inclination, equals(51.6416));
      expect(omm.raOfAscNode, equals(201.9363));
      expect(omm.argOfPericenter, equals(66.0061));
      expect(omm.meanAnomaly, equals(310.0484));
      expect(omm.ephemerisType, equals(0));
      expect(omm.classificationType, equals('U'));
      expect(omm.noradCatId, equals(25544));
      expect(omm.elementSetNo, equals(999));
      expect(omm.revAtEpoch, equals(48936));
      expect(omm.bstar, equals(-0.00017455));
      expect(omm.meanMotionDot, equals(0.00010768));
      // JSON integer 0 parsed into the double field.
      expect(omm.meanMotionDdot, equals(0));
    });

    test('throws OmmParseException on missing string field', () {
      json.remove('CENTER_NAME');
      expect(() => parser.parse(json), throwsA(isA<OmmParseException>()));
    });

    test('throws OmmParseException on missing int field', () {
      json.remove('NORAD_CAT_ID');
      expect(() => parser.parse(json), throwsA(isA<OmmParseException>()));
    });

    test('throws OmmParseException on missing double field', () {
      json.remove('MEAN_MOTION');
      expect(() => parser.parse(json), throwsA(isA<OmmParseException>()));
    });

    test('throws OmmParseException on missing EPOCH', () {
      json.remove('EPOCH');
      expect(() => parser.parse(json), throwsA(isA<OmmParseException>()));
    });

    test('OmmParseException names the offending field', () {
      json.remove('NORAD_CAT_ID');
      expect(
        () => parser.parse(json),
        throwsA(
          isA<OmmParseException>().having(
            (e) => e.field,
            'field',
            'NORAD_CAT_ID',
          ),
        ),
      );
    });

    test('accepts a numeric string for an int field', () {
      json['NORAD_CAT_ID'] = '25544';
      expect(parser.parse(json).noradCatId, equals(25544));
    });

    test('accepts a numeric string for a double field', () {
      json['MEAN_MOTION'] = '15.49796647';
      expect(parser.parse(json).meanMotion, equals(15.49796647));
    });

    test('throws OmmParseException on a non-numeric int field', () {
      json['NORAD_CAT_ID'] = 'not-a-number';
      expect(() => parser.parse(json), throwsA(isA<OmmParseException>()));
    });

    test('parses a zoneless EPOCH as UTC', () {
      json['EPOCH'] = '2026-06-01T13:00:00.000000';
      final omm = parser.parse(json);
      expect(omm.epoch, equals(DateTime.utc(2026, 6, 1, 13, 0)));
      expect(omm.epoch.isUtc, isTrue);
    });

    test('throws OmmParseException on a malformed EPOCH', () {
      json['EPOCH'] = 'definitely-not-a-date';
      expect(() => parser.parse(json), throwsA(isA<OmmParseException>()));
    });
  });

  group('OmmParser.parse - analyst null-name fixture', () {
    late Map<String, dynamic> json;

    setUp(() => json = loadFixture('analyst_null_name.json'));

    test('tolerates null OBJECT_NAME and OBJECT_ID', () {
      final omm = parser.parse(json);
      expect(omm.objectName, isNull);
      expect(omm.objectId, isNull);
    });

    test('parses analyst noradCatId', () {
      expect(parser.parse(json).noradCatId, equals(80001));
    });

    test('epoch parsed as UTC', () {
      final omm = parser.parse(json);
      expect(omm.epoch, equals(DateTime.utc(2026, 1, 1)));
      expect(omm.epoch.isUtc, isTrue);
    });
  });
}
