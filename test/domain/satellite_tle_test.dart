import 'package:celestrak/src/domain/satellite_tle.dart';
import 'package:test/test.dart';

void main() {
  const line1 =
      '1 25544U 98067A   26152.54148148  .00010768  00000+0  17455-3 0  9993';
  const line2 =
      '2 25544  51.6416 201.9363 0005801  66.0061 310.0484 15.4979664748937';
  final epoch = DateTime.utc(2026, 6, 1);
  final fetchedAt = DateTime.utc(2026, 6, 1);

  group('SatelliteTle value equality', () {
    final tleA = SatelliteTle(
      noradId: 25544,
      name: 'ISS (ZARYA)',
      line1: line1,
      line2: line2,
      epoch: epoch,
      fetchedAt: fetchedAt,
      source: TLESource.celestrak,
    );

    test('identical instances are equal', () {
      expect(tleA, equals(tleA));
    });

    test('two instances with same fields are equal', () {
      final tleB = SatelliteTle(
        noradId: 25544,
        name: 'ISS (ZARYA)',
        line1: line1,
        line2: line2,
        epoch: epoch,
        fetchedAt: fetchedAt,
        source: TLESource.celestrak,
      );
      expect(tleA, equals(tleB));
    });

    test('different noradId -> not equal', () {
      final c = tleA.copyWith(noradId: 99999);
      expect(tleA, isNot(equals(c)));
    });

    test('different name -> not equal', () {
      final c = tleA.copyWith(name: 'OTHER');
      expect(tleA, isNot(equals(c)));
    });

    test('different line1 -> not equal', () {
      final c = tleA.copyWith(line1: '1 40XXXX');
      expect(tleA, isNot(equals(c)));
    });

    test('different epoch -> not equal', () {
      final c = tleA.copyWith(epoch: DateTime.utc(2025, 1, 1));
      expect(tleA, isNot(equals(c)));
    });

    test('different source -> not equal', () {
      final c = tleA.copyWith(source: TLESource.local);
      expect(tleA, isNot(equals(c)));
    });

    test('hashCode is consistent with equality', () {
      final tleB = SatelliteTle(
        noradId: 25544,
        name: 'ISS (ZARYA)',
        line1: line1,
        line2: line2,
        epoch: epoch,
        fetchedAt: fetchedAt,
        source: TLESource.celestrak,
      );
      expect(tleA.hashCode, equals(tleB.hashCode));
    });
  });

  group('SatelliteTle.copyWith', () {
    final base = SatelliteTle(
      noradId: 25544,
      name: 'ISS (ZARYA)',
      line1: line1,
      line2: line2,
      epoch: epoch,
      fetchedAt: fetchedAt,
      source: TLESource.celestrak,
    );

    test('no args returns equal copy', () {
      expect(base.copyWith(), equals(base));
    });

    test('replaces single field', () {
      final updated = base.copyWith(name: 'NEW NAME');
      expect(updated.name, equals('NEW NAME'));
      expect(updated.noradId, equals(base.noradId));
    });

    test('original unchanged (immutability)', () {
      base.copyWith(noradId: 123);
      expect(base.noradId, equals(25544));
    });
  });

  group('SatelliteTle computed fields', () {
    final base = SatelliteTle(
      noradId: 25544,
      name: 'ISS (ZARYA)',
      line1: line1,
      line2: line2,
      epoch: DateTime.utc(2026, 1, 1),
      fetchedAt: fetchedAt,
      source: TLESource.local,
    );

    test('age is positive for past epoch', () {
      expect(base.age.inDays, greaterThanOrEqualTo(150));
    });

    test('isStale defaults to 3-day threshold', () {
      expect(base.isStale(), isTrue);
    });

    test('isStale respects custom threshold', () {
      expect(base.isStale(staleThreshold: const Duration(days: 400)), isFalse);
    });

    test('classification returns U for unclassified', () {
      expect(base.classification, equals('U'));
    });

    test('classification returns null for short line1', () {
      final short = base.copyWith(line1: '1 25544');
      expect(short.classification, isNull);
    });
  });

  group('SatelliteTle immutability', () {
    test('fields cannot be reassigned (compile-time guarantee)', () {
      final tle = SatelliteTle(
        noradId: 25544,
        name: 'ISS',
        line1: line1,
        line2: line2,
        epoch: epoch,
        fetchedAt: fetchedAt,
        source: TLESource.celestrak,
      );
      expect(tle.noradId, isNotNull);
    });
  });

  group('SatelliteTle toString', () {
    test('output contains noradId and name', () {
      final tle = SatelliteTle(
        noradId: 25544,
        name: 'ISS (ZARYA)',
        line1: line1,
        line2: line2,
        epoch: epoch,
        fetchedAt: fetchedAt,
        source: TLESource.celestrak,
      );
      final s = tle.toString();
      expect(s, contains('25544'));
      expect(s, contains('ISS (ZARYA)'));
    });
  });
}
