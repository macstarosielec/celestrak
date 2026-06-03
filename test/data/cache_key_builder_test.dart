import 'package:celestrak/src/data/local/cache_key_builder.dart';
import 'package:celestrak/src/domain/enums.dart';
import 'package:test/test.dart';

void main() {
  group('CacheKeyBuilder.forNoradId', () {
    test('produces expected key for OMM / celestrak', () {
      final key = CacheKeyBuilder.forNoradId(
        25544,
        format: CelestrakFormat.omm,
      );
      expect(key, equals('norad:25544~fmt:omm~src:celestrak'));
    });

    test('produces expected key for TLE / celestrak', () {
      final key = CacheKeyBuilder.forNoradId(
        25544,
        format: CelestrakFormat.tle,
      );
      expect(key, equals('norad:25544~fmt:tle~src:celestrak'));
    });

    test('source override: spacetrack', () {
      final key = CacheKeyBuilder.forNoradId(
        25544,
        format: CelestrakFormat.omm,
        source: TleSource.spacetrack,
      );
      expect(key, equals('norad:25544~fmt:omm~src:spacetrack'));
    });

    test('source override: local', () {
      final key = CacheKeyBuilder.forNoradId(
        25544,
        format: CelestrakFormat.omm,
        source: TleSource.local,
      );
      expect(key, equals('norad:25544~fmt:omm~src:local'));
    });

    test('large norad id (6 digits)', () {
      final key = CacheKeyBuilder.forNoradId(
        123456,
        format: CelestrakFormat.omm,
      );
      expect(key, startsWith('norad:123456~'));
    });

    test('key contains only valid characters', () {
      final key = CacheKeyBuilder.forNoradId(
        99999,
        format: CelestrakFormat.tle,
      );
      expect(key, matches(RegExp(r'^[A-Za-z0-9:_\-~]+$')));
    });

    test('different norad ids produce different keys', () {
      final k1 = CacheKeyBuilder.forNoradId(
        25544,
        format: CelestrakFormat.omm,
      );
      final k2 = CacheKeyBuilder.forNoradId(
        25545,
        format: CelestrakFormat.omm,
      );
      expect(k1, isNot(equals(k2)));
    });
  });

  group('CacheKeyBuilder.forName', () {
    test('lower-cases the name', () {
      final key = CacheKeyBuilder.forName(
        'STARLINK',
        format: CelestrakFormat.omm,
      );
      expect(key, startsWith('name:starlink~'));
    });

    test('replaces spaces with underscores', () {
      final key = CacheKeyBuilder.forName(
        'ISS (ZARYA)',
        format: CelestrakFormat.omm,
      );
      // Parentheses are stripped; spaces become underscores.
      expect(key, startsWith('name:iss_zarya~'));
    });

    test('key contains only valid characters', () {
      final key = CacheKeyBuilder.forName(
        'Starlink-1234',
        format: CelestrakFormat.tle,
      );
      expect(key, matches(RegExp(r'^[A-Za-z0-9:_\-~]+$')));
    });

    test(
        'names differing only in stripped characters produce the same key '
        '(documented collision — see forName doc comment)', () {
      // "ISS (ZARYA)" and "ISS ZARYA" both normalise to "iss_zarya";
      // callers must be aware that CelesTrak may return different results
      // for these two queries despite them sharing a cache key.
      final k1 = CacheKeyBuilder.forName(
        'ISS (ZARYA)',
        format: CelestrakFormat.omm,
      );
      final k2 = CacheKeyBuilder.forName(
        'ISS ZARYA',
        format: CelestrakFormat.omm,
      );
      expect(k1, equals(k2));
    });
  });

  group('CacheKeyBuilder.forCategory', () {
    test('stations produces expected key', () {
      final key = CacheKeyBuilder.forCategory(
        SatelliteCategory.stations,
        format: CelestrakFormat.omm,
      );
      expect(key, equals('group:stations~fmt:omm~src:celestrak'));
    });

    test('gps uses correct group string', () {
      final key = CacheKeyBuilder.forCategory(
        SatelliteCategory.gps,
        format: CelestrakFormat.omm,
      );
      // gps.group == 'gps-ops'; hyphen is preserved.
      expect(key, equals('group:gps-ops~fmt:omm~src:celestrak'));
    });

    test('cosmos2251Debris uses correct group string', () {
      final key = CacheKeyBuilder.forCategory(
        SatelliteCategory.cosmos2251Debris,
        format: CelestrakFormat.omm,
      );
      expect(key, equals('group:cosmos-2251-debris~fmt:omm~src:celestrak'));
    });

    test('different categories produce different keys', () {
      final k1 = CacheKeyBuilder.forCategory(
        SatelliteCategory.starlink,
        format: CelestrakFormat.omm,
      );
      final k2 = CacheKeyBuilder.forCategory(
        SatelliteCategory.weather,
        format: CelestrakFormat.omm,
      );
      expect(k1, isNot(equals(k2)));
    });

    test('format difference produces different keys', () {
      final k1 = CacheKeyBuilder.forCategory(
        SatelliteCategory.stations,
        format: CelestrakFormat.omm,
      );
      final k2 = CacheKeyBuilder.forCategory(
        SatelliteCategory.stations,
        format: CelestrakFormat.tle,
      );
      expect(k1, isNot(equals(k2)));
    });
  });

  group('CacheKeyBuilder.forGroup', () {
    test('arbitrary group string', () {
      final key = CacheKeyBuilder.forGroup(
        'oneweb',
        format: CelestrakFormat.omm,
      );
      expect(key, equals('group:oneweb~fmt:omm~src:celestrak'));
    });

    test('normalises upper-case group', () {
      final key = CacheKeyBuilder.forGroup(
        'GEO',
        format: CelestrakFormat.omm,
      );
      expect(key, equals('group:geo~fmt:omm~src:celestrak'));
    });
  });

  group('CacheKeyBuilder.forIntlDesignator', () {
    test('normalises the designator', () {
      final key = CacheKeyBuilder.forIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
      );
      // Upper-case letters become lower-case; hyphens preserved.
      expect(key, equals('intdes:1998-067a~fmt:omm~src:celestrak'));
    });

    test('key contains only valid characters', () {
      final key = CacheKeyBuilder.forIntlDesignator(
        '2020-001B',
        format: CelestrakFormat.tle,
      );
      expect(key, matches(RegExp(r'^[A-Za-z0-9:_\-~]+$')));
    });
  });

  group('CacheKeyBuilder - isolation (different query types differ)', () {
    test('norad and name keys never collide', () {
      final noradKey = CacheKeyBuilder.forNoradId(
        25544,
        format: CelestrakFormat.omm,
      );
      final nameKey = CacheKeyBuilder.forName(
        '25544',
        format: CelestrakFormat.omm,
      );
      expect(noradKey, isNot(equals(nameKey)));
    });

    test('name and group keys never collide on same value', () {
      final nameKey = CacheKeyBuilder.forName(
        'stations',
        format: CelestrakFormat.omm,
      );
      final groupKey = CacheKeyBuilder.forGroup(
        'stations',
        format: CelestrakFormat.omm,
      );
      expect(nameKey, isNot(equals(groupKey)));
    });
  });

  group('CacheKeyBuilder.forNoradId - validation', () {
    test('zero noradId throws ArgumentError', () {
      expect(
        () => CacheKeyBuilder.forNoradId(
          0,
          format: CelestrakFormat.omm,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            'noradId',
          ),
        ),
      );
    });

    test('negative noradId throws ArgumentError', () {
      expect(
        () => CacheKeyBuilder.forNoradId(
          -1,
          format: CelestrakFormat.omm,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            'noradId',
          ),
        ),
      );
    });
  });
}
