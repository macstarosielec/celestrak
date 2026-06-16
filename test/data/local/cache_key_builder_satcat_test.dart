/// CEL-141: SATCAT cache-key construction.
///
/// Verifies the dataset-discriminated SATCAT key factories: exact output
/// strings, no collision with the GP key for the same NORAD id, validity
/// against [CacheStore.validateKey], normalisation of group / INTDES inputs,
/// and the deliberate fetchAll == fetchByGroup('active') key equality.
library;

import 'package:celestrak/celestrak.dart' show CacheStore, CelestrakFormat;
import 'package:celestrak/src/data/local/cache_key_builder.dart';
import 'package:test/test.dart';

void main() {
  group('CacheKeyBuilder SATCAT factories - exact strings', () {
    test('forSatcatNoradId', () {
      expect(
        CacheKeyBuilder.forSatcatNoradId(25544),
        equals('dataset:satcat~norad:25544~fmt:json'),
      );
    });

    test('forSatcatGroup', () {
      expect(
        CacheKeyBuilder.forSatcatGroup('stations'),
        equals('dataset:satcat~group:stations~fmt:json'),
      );
    });

    test('forSatcatIntlDesignator preserves hyphens', () {
      expect(
        CacheKeyBuilder.forSatcatIntlDesignator('1998-067A'),
        equals('dataset:satcat~intdes:1998-067a~fmt:json'),
      );
    });

    test('forSatcatAll uses the active full-catalogue form', () {
      expect(
        CacheKeyBuilder.forSatcatAll(),
        equals('dataset:satcat~group:active~fmt:json'),
      );
    });
  });

  group('CacheKeyBuilder SATCAT factories - normalisation', () {
    test('group is lower-cased and spaces become underscores', () {
      expect(
        CacheKeyBuilder.forSatcatGroup('Active DEBris'),
        equals('dataset:satcat~group:active_debris~fmt:json'),
      );
    });

    test('INTDES is lower-cased', () {
      expect(
        CacheKeyBuilder.forSatcatIntlDesignator('1998-067'),
        equals('dataset:satcat~intdes:1998-067~fmt:json'),
      );
    });
  });

  group('CacheKeyBuilder SATCAT factories - no GP collision', () {
    test('SATCAT NORAD key differs from the GP NORAD key', () {
      final satcatKey = CacheKeyBuilder.forSatcatNoradId(25544);
      final gpOmmKey =
          CacheKeyBuilder.forNoradId(25544, format: CelestrakFormat.omm);
      final gpTleKey =
          CacheKeyBuilder.forNoradId(25544, format: CelestrakFormat.tle);

      expect(satcatKey, isNot(equals(gpOmmKey)));
      expect(satcatKey, isNot(equals(gpTleKey)));
      expect(satcatKey, startsWith('dataset:satcat'));
      expect(gpOmmKey, isNot(startsWith('dataset:')));
    });

    test('SATCAT group key differs from the GP group key', () {
      final satcatKey = CacheKeyBuilder.forSatcatGroup('stations');
      final gpKey =
          CacheKeyBuilder.forGroup('stations', format: CelestrakFormat.omm);
      expect(satcatKey, isNot(equals(gpKey)));
    });
  });

  group('CacheKeyBuilder SATCAT factories - validity and sharing', () {
    test('every SATCAT key passes CacheStore.validateKey', () {
      final keys = <String>[
        CacheKeyBuilder.forSatcatNoradId(1),
        CacheKeyBuilder.forSatcatNoradId(999999999),
        CacheKeyBuilder.forSatcatGroup('Active DEBris'),
        CacheKeyBuilder.forSatcatIntlDesignator('1998-067A'),
        CacheKeyBuilder.forSatcatAll(),
      ];
      for (final key in keys) {
        expect(() => CacheStore.validateKey(key), returnsNormally);
      }
    });

    test('forSatcatAll equals forSatcatGroup("active")', () {
      expect(
        CacheKeyBuilder.forSatcatAll(),
        equals(CacheKeyBuilder.forSatcatGroup('active')),
      );
    });

    test('forSatcatNoradId rejects non-positive ids', () {
      expect(
        () => CacheKeyBuilder.forSatcatNoradId(0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => CacheKeyBuilder.forSatcatNoradId(-1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
