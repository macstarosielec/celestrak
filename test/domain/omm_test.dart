import 'package:celestrak/src/domain/omm.dart';
import 'package:test/test.dart';

void main() {
  Omm buildOmm() => Omm(
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

  group('Omm value equality', () {
    test('identical instances are equal', () {
      final omm = buildOmm();
      expect(omm, equals(omm));
    });

    test('same field values are equal', () {
      expect(buildOmm(), equals(buildOmm()));
    });

    test('hashCode consistent with equality', () {
      expect(buildOmm().hashCode, equals(buildOmm().hashCode));
    });

    test('different noradCatId -> not equal', () {
      expect(buildOmm(), isNot(equals(buildOmm().copyWith(noradCatId: 99999))));
    });

    test('different objectName -> not equal', () {
      expect(
        buildOmm(),
        isNot(equals(buildOmm().copyWith(objectName: 'RENAMED'))),
      );
    });

    test('different epoch -> not equal', () {
      expect(
        buildOmm(),
        isNot(equals(buildOmm().copyWith(epoch: DateTime.utc(2025, 1, 1)))),
      );
    });

    test('null objectName vs non-null not equal', () {
      expect(buildOmm(), isNot(equals(buildOmm().copyWith(objectName: null))));
    });
  });

  group('Omm.copyWith', () {
    test('no args returns equal copy', () {
      final base = buildOmm();
      expect(base.copyWith(), equals(base));
    });

    test('replaces single field', () {
      final updated = buildOmm().copyWith(noradCatId: 12345);
      expect(updated.noradCatId, equals(12345));
      expect(updated.bstar, equals(buildOmm().bstar));
    });

    test('original unchanged', () {
      final base = buildOmm()..copyWith(noradCatId: 1);
      expect(base.noradCatId, equals(25544));
    });

    test('can clear objectName to null', () {
      final cleared = buildOmm().copyWith(objectName: null);
      expect(cleared.objectName, isNull);
      expect(cleared.objectId, isNotNull);
    });

    test('can clear objectId to null', () {
      final cleared = buildOmm().copyWith(objectId: null);
      expect(cleared.objectId, isNull);
      expect(cleared.objectName, isNotNull);
    });

    test('clearing both nullable fields', () {
      final cleared = buildOmm().copyWith(objectName: null, objectId: null);
      expect(cleared.objectName, isNull);
      expect(cleared.objectId, isNull);
    });

    test('omitting a nullable arg keeps a null value', () {
      final analyst = buildOmm().copyWith(objectName: null);
      final renamedId = analyst.copyWith(noradCatId: 80001);
      expect(renamedId.objectName, isNull);
    });

    test('clears bstar to zero', () {
      final updated = buildOmm().copyWith(bstar: 0);
      expect(updated.bstar, equals(0));
      expect(updated.bstar, isNot(equals(buildOmm().bstar)));
    });
  });

  group('Omm.toString', () {
    test('output contains noradCatId and objectName', () {
      final s = buildOmm().toString();
      expect(s, contains('25544'));
      expect(s, contains('ISS (ZARYA)'));
    });
  });
}
