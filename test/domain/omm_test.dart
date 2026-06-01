import 'dart:convert';
import 'dart:io';

import 'package:celestrak/src/domain/omm.dart';
import 'package:test/test.dart';

void main() {
  group('Omm.fromCelestrakJson - ISS fixture', () {
    late Map<String, dynamic> json;

    setUp(() {
      final content = File('test/fixtures/iss_omm.json').readAsStringSync();
      json = jsonDecode(content) as Map<String, dynamic>;
    });

    test('parses all fields correctly', () {
      final omm = Omm.fromCelestrakJson(json);

      expect(omm.objectName, equals('ISS (ZARYA)'));
      expect(omm.objectId, equals('1998-067A'));
      expect(omm.epoch, equals(DateTime.utc(2026, 6, 1, 13, 0)));
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
      expect(omm.meanMotionDdot, equals(0));
    });

    test('throws on missing required string field', () {
      json.remove('CENTER_NAME');
      expect(
        () => Omm.fromCelestrakJson(json),
        throwsA(isA<StateError>()),
      );
    });

    test('throws on missing required int field', () {
      json.remove('NORAD_CAT_ID');
      expect(
        () => Omm.fromCelestrakJson(json),
        throwsA(isA<StateError>()),
      );
    });

    test('throws on missing required double field', () {
      json.remove('MEAN_MOTION');
      expect(
        () => Omm.fromCelestrakJson(json),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Omm.fromCelestrakJson - null name fixture', () {
    late Map<String, dynamic> json;

    setUp(() {
      final content =
          File('test/fixtures/analyst_null_name.json').readAsStringSync();
      json = jsonDecode(content) as Map<String, dynamic>;
    });

    test('tolerates null OBJECT_NAME', () {
      final omm = Omm.fromCelestrakJson(json);
      expect(omm.objectName, isNull);
    });

    test('tolerates null OBJECT_ID', () {
      final omm = Omm.fromCelestrakJson(json);
      expect(omm.objectId, isNull);
    });

    test('parses analyst noradCatId correctly', () {
      final omm = Omm.fromCelestrakJson(json);
      expect(omm.noradCatId, equals(80001));
    });

    test('epoch parsed as UTC', () {
      final omm = Omm.fromCelestrakJson(json);
      expect(omm.epoch, equals(DateTime.utc(2026, 1, 1)));
      expect(omm.epoch.isUtc, isTrue);
    });
  });

  group('Omm value equality', () {
    final ommA = Omm(
      objectName: 'ISS (ZARYA)',
      objectId: '1998-067A',
      epoch: DateTime.utc(2026, 6, 1, 13, 0),
      centerName: 'EARTH',
      refFrame: 'TEME',
      timeSystem: 'UTC',
      meanElementTheory: 'SGP4',
      meanMotion: 15.49796647,
      eccentricity: 0.0005801,
      inclination: 51.6416,
      raOfAscNode: 201.9363,
      argOfPericenter: 66.0061,
      meanAnomaly: 310.0484,
      ephemerisType: 0,
      classificationType: 'U',
      noradCatId: 25544,
      elementSetNo: 999,
      revAtEpoch: 48936,
      bstar: -0.00017455,
      meanMotionDot: 0.00010768,
      meanMotionDdot: 0,
    );

    test('identical instances are equal', () {
      expect(ommA, equals(ommA));
    });

    test('same field values are equal', () {
      final ommB = Omm(
        objectName: 'ISS (ZARYA)',
        objectId: '1998-067A',
        epoch: DateTime.utc(2026, 6, 1, 13, 0),
        centerName: 'EARTH',
        refFrame: 'TEME',
        timeSystem: 'UTC',
        meanElementTheory: 'SGP4',
        meanMotion: 15.49796647,
        eccentricity: 0.0005801,
        inclination: 51.6416,
        raOfAscNode: 201.9363,
        argOfPericenter: 66.0061,
        meanAnomaly: 310.0484,
        ephemerisType: 0,
        classificationType: 'U',
        noradCatId: 25544,
        elementSetNo: 999,
        revAtEpoch: 48936,
        bstar: -0.00017455,
        meanMotionDot: 0.00010768,
        meanMotionDdot: 0,
      );
      expect(ommA, equals(ommB));
    });

    test('hashCode consistent with equality', () {
      final ommB = Omm(
        objectName: 'ISS (ZARYA)',
        objectId: '1998-067A',
        epoch: DateTime.utc(2026, 6, 1, 13, 0),
        centerName: 'EARTH',
        refFrame: 'TEME',
        timeSystem: 'UTC',
        meanElementTheory: 'SGP4',
        meanMotion: 15.49796647,
        eccentricity: 0.0005801,
        inclination: 51.6416,
        raOfAscNode: 201.9363,
        argOfPericenter: 66.0061,
        meanAnomaly: 310.0484,
        ephemerisType: 0,
        classificationType: 'U',
        noradCatId: 25544,
        elementSetNo: 999,
        revAtEpoch: 48936,
        bstar: -0.00017455,
        meanMotionDot: 0.00010768,
        meanMotionDdot: 0,
      );
      expect(ommA.hashCode, equals(ommB.hashCode));
    });

    test('different noradCatId -> not equal', () {
      final other = ommA.copyWith(noradCatId: 99999);
      expect(ommA, isNot(equals(other)));
    });

    test('different objectName -> not equal', () {
      final other = ommA.copyWith(updateObjectName: 'RENAMED');
      expect(ommA, isNot(equals(other)));
    });

    test('different epoch -> not equal', () {
      final other = ommA.copyWith(epoch: DateTime.utc(2025, 1, 1));
      expect(ommA, isNot(equals(other)));
    });

    test('null objectName vs non-null not equal', () {
      final other = ommA.copyWith(updateObjectName: null);
      expect(ommA, isNot(equals(other)));
    });
  });

  group('Omm.copyWith', () {
    final base = Omm(
      objectName: 'ISS (ZARYA)',
      objectId: '1998-067A',
      epoch: DateTime.utc(2026, 6, 1, 13, 0),
      centerName: 'EARTH',
      refFrame: 'TEME',
      timeSystem: 'UTC',
      meanElementTheory: 'SGP4',
      meanMotion: 15.49796647,
      eccentricity: 0.0005801,
      inclination: 51.6416,
      raOfAscNode: 201.9363,
      argOfPericenter: 66.0061,
      meanAnomaly: 310.0484,
      ephemerisType: 0,
      classificationType: 'U',
      noradCatId: 25544,
      elementSetNo: 999,
      revAtEpoch: 48936,
      bstar: -0.00017455,
      meanMotionDot: 0.00010768,
      meanMotionDdot: 0,
    );

    test('no args returns equal copy', () {
      expect(base.copyWith(), equals(base));
    });

    test('replaces single field', () {
      final updated = base.copyWith(noradCatId: 12345);
      expect(updated.noradCatId, equals(12345));
      expect(updated.bstar, equals(base.bstar));
    });

    test('original unchanged', () {
      base.copyWith(noradCatId: 1);
      expect(base.noradCatId, equals(25544));
    });

    test('can clear objectName to null', () {
      final cleared = base.copyWith(updateObjectName: null);
      expect(cleared.objectName, isNull);
      expect(cleared.objectId, isNotNull);
    });

    test('can clear objectId to null', () {
      final cleared = base.copyWith(updateObjectId: null);
      expect(cleared.objectId, isNull);
      expect(cleared.objectName, isNotNull);
    });

    test('clearing both nullable fields', () {
      final cleared = base.copyWith(
        updateObjectName: null,
        updateObjectId: null,
      );
      expect(cleared.objectName, isNull);
      expect(cleared.objectId, isNull);
    });

    test('clears bstar to zero', () {
      final updated = base.copyWith(bstar: 0);
      expect(updated.bstar, equals(0));
      expect(updated.bstar, isNot(equals(base.bstar)));
    });
  });

  group('Omm.toString', () {
    final omm = Omm(
      objectName: 'ISS (ZARYA)',
      objectId: '1998-067A',
      epoch: DateTime.utc(2026, 6, 1, 13, 0),
      centerName: 'EARTH',
      refFrame: 'TEME',
      timeSystem: 'UTC',
      meanElementTheory: 'SGP4',
      meanMotion: 15.49796647,
      eccentricity: 0.0005801,
      inclination: 51.6416,
      raOfAscNode: 201.9363,
      argOfPericenter: 66.0061,
      meanAnomaly: 310.0484,
      ephemerisType: 0,
      classificationType: 'U',
      noradCatId: 25544,
      elementSetNo: 999,
      revAtEpoch: 48936,
      bstar: -0.00017455,
      meanMotionDot: 0.00010768,
      meanMotionDdot: 0,
    );

    test('output contains noradCatId and objectName', () {
      final s = omm.toString();
      expect(s, contains('25544'));
      expect(s, contains('ISS (ZARYA)'));
    });
  });
}
