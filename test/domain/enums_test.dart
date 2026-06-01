import 'package:celestrak/src/domain/enums.dart';
import 'package:test/test.dart';

void main() {
  group('TleSource', () {
    test('has exactly three values', () {
      expect(TleSource.values, hasLength(3));
    });

    test('contains celestrak, spacetrack, local', () {
      expect(
        TleSource.values,
        containsAll([
          TleSource.celestrak,
          TleSource.spacetrack,
          TleSource.local,
        ]),
      );
    });
  });

  group('CelestrakFormat', () {
    test('has exactly two values', () {
      expect(CelestrakFormat.values, hasLength(2));
    });

    test('contains tle and omm', () {
      expect(
        CelestrakFormat.values,
        containsAll([CelestrakFormat.tle, CelestrakFormat.omm]),
      );
    });
  });

  group('SatelliteCategory.group — CelesTrak GROUP string mapping', () {
    // These are the authoritative group strings verified against the
    // CelesTrak GP API. P4 will additionally verify each against a
    // fixture response; this test guards the mapping itself.
    const expected = {
      SatelliteCategory.stations: 'stations',
      SatelliteCategory.starlink: 'starlink',
      SatelliteCategory.weather: 'weather',
      SatelliteCategory.amateur: 'amateur',
      SatelliteCategory.visual: 'visual',
      SatelliteCategory.gps: 'gps-ops',
      SatelliteCategory.galileo: 'galileo',
      SatelliteCategory.glonass: 'glo-ops',
      SatelliteCategory.debris: 'cosmos-2251-debris',
      SatelliteCategory.active: 'active',
      SatelliteCategory.lastThirtyDays: 'last-30-days',
    };

    for (final entry in expected.entries) {
      test('${entry.key.name}.group == "${entry.value}"', () {
        expect(entry.key.group, equals(entry.value));
      });
    }

    test('every SatelliteCategory value is covered', () {
      for (final category in SatelliteCategory.values) {
        expect(
          expected,
          contains(category),
          reason: '${category.name} is missing from the expected map',
        );
      }
    });

    test('group strings are non-empty', () {
      for (final category in SatelliteCategory.values) {
        expect(category.group, isNotEmpty);
      }
    });

    test('group strings are unique', () {
      final groups = SatelliteCategory.values.map((c) => c.group).toList();
      expect(groups.toSet(), hasLength(groups.length));
    });
  });
}
