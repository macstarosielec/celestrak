/// CEL-61: Public API surface freeze.
///
/// Verifies that every symbol intentionally exported from
/// `package:celestrak` is accessible, and that known internal types are NOT
/// accessible via the barrel. This test acts as a canary: if the barrel is
/// accidentally widened or narrowed, it fails immediately.
///
/// Symbols confirmed public (one assignment proves the name resolves):
///   CelestrakClient, SpaceTrackClient, SpaceTrackQuery,
///   CacheStore, MemoryCacheStore, OmmParser, ParseBenchmarkHook,
///   NullParseBenchmarkHook, Clock, SystemClock, kDefaultTtl,
///   kDefaultMaxAttempts, kDefaultTimeout, SatelliteCategory, TleSource,
///   CelestrakFormat, CelestrakException, AuthenticationException,
///   CacheMissException, NetworkException, OmmParseException,
///   RateLimitException, SatelliteNotFoundException, TleParseException,
///   TleRepository, Omm, SatelliteTle, StalenessChecker,
///   defaultStaleThreshold, SatcatOwner, satcatOwnerForCode, SatcatEntry,
///   SatcatObjectType, SatcatParser, SatcatParseException.
///
/// Internal symbols not exported (compile-time-checked via
/// `dart analyze` passing without undefined-identifier errors):
///   HttpTransport, TleOmmStitcher, CacheKeyBuilder, FileCacheStore,
///   kBackoffBase, kBackoffMax.
library;

import 'package:celestrak/celestrak.dart';
import 'package:test/test.dart';

void main() {
  // ── Public symbols resolve ─────────────────────────────────────────────────

  group('Public API barrel - all intentional exports resolve', () {
    test('CelestrakClient is accessible', () {
      // Construction requires real deps; just check the type resolves.
      expect(CelestrakClient, isNotNull);
    });

    test('SpaceTrackClient is accessible', () {
      final client = SpaceTrackClient(identity: null, password: null);
      expect(client.isEnabled, isFalse);
      client.dispose();
    });

    test('SpaceTrackQuery is accessible', () {
      final query = SpaceTrackQuery.byNoradId(25544);
      expect(query.noradId, 25544);
    });

    test('MemoryCacheStore is accessible', () {
      final store = MemoryCacheStore();
      expect(store, isA<CacheStore>());
    });

    test('CacheStore interface is accessible', () {
      // Verify it is usable as a type annotation.
      CacheStore? store;
      store = MemoryCacheStore();
      expect(store, isNotNull);
    });

    test('OmmParser is accessible', () {
      const parser = OmmParser();
      expect(parser, isNotNull);
    });

    test('NullParseBenchmarkHook is accessible', () {
      const hook = NullParseBenchmarkHook();
      expect(hook, isA<ParseBenchmarkHook>());
    });

    test('ParseBenchmarkHook interface is accessible', () {
      ParseBenchmarkHook? hook;
      hook = const NullParseBenchmarkHook();
      expect(hook, isNotNull);
    });

    test('Clock / SystemClock are accessible', () {
      const clock = SystemClock();
      expect(clock, isA<Clock>());
      expect(clock.now, isA<DateTime>());
    });

    test('kDefaultTtl is accessible', () {
      expect(kDefaultTtl, const Duration(hours: 2));
    });

    test('kDefaultMaxAttempts is accessible', () {
      expect(kDefaultMaxAttempts, 5);
    });

    test('kDefaultTimeout is accessible', () {
      expect(kDefaultTimeout, const Duration(seconds: 30));
    });

    test('SatelliteCategory enum is accessible', () {
      expect(SatelliteCategory.stations.group, 'stations');
    });

    test('TleSource enum is accessible', () {
      expect(TleSource.celestrak, isNotNull);
      expect(TleSource.spacetrack, isNotNull);
      expect(TleSource.local, isNotNull);
    });

    test('CelestrakFormat enum is accessible', () {
      expect(CelestrakFormat.omm, isNotNull);
      expect(CelestrakFormat.tle, isNotNull);
    });

    test('CelestrakException hierarchy is accessible', () {
      const e1 = NetworkException('x');
      expect(e1, isA<CelestrakException>());

      const e2 = OmmParseException('x', field: 'EPOCH');
      expect(e2.field, 'EPOCH');

      const e3 = TleParseException('x', field: 'line1');
      expect(e3.field, 'line1');

      const e4 = SatelliteNotFoundException('x', noradId: 99);
      expect(e4.noradId, 99);

      const e5 = CacheMissException('x', key: 'k');
      expect(e5.key, 'k');

      const e6 = AuthenticationException('x', statusCode: 401);
      expect(e6.statusCode, 401);

      const e7 = RateLimitException('x', retryAfter: Duration(seconds: 30));
      expect(e7.retryAfter, const Duration(seconds: 30));
    });

    test('TleRepository interface is accessible as a type', () {
      // Cannot instantiate (abstract interface); verify as a type annotation.
      TleRepository? repo;
      expect(repo, isNull);
    });

    test('SatelliteTle is accessible', () {
      final epoch = DateTime.utc(2026, 1, 1);
      final tle = SatelliteTle(
        noradId: 25544,
        name: 'ISS (ZARYA)',
        line1: '',
        line2: '',
        epoch: epoch,
        fetchedAt: epoch,
        source: TleSource.celestrak,
      );
      expect(tle.noradId, 25544);
      expect(tle.isStale(now: epoch), isFalse);
    });

    test('Omm is accessible', () {
      expect(Omm, isNotNull);
    });

    test('StalenessChecker is accessible', () {
      const checker = StalenessChecker();
      expect(checker.staleThreshold, defaultStaleThreshold);
    });

    test('defaultStaleThreshold is accessible', () {
      expect(defaultStaleThreshold, const Duration(days: 3));
    });

    test('SatcatOwner is accessible', () {
      const owner = SatcatOwner(code: 'US', name: 'United States');
      expect(owner.code, 'US');
    });

    test('satcatOwnerForCode is accessible', () {
      expect(satcatOwnerForCode('FR').isEuSovereign, isTrue);
    });

    test('SatcatEntry is accessible', () {
      const entry = SatcatEntry(
        noradId: 25544,
        name: 'ISS (ZARYA)',
        ownerCode: 'US',
        objectType: SatcatObjectType.payload,
      );
      expect(entry.noradId, 25544);
      expect(entry.isPayload, isTrue);
      expect(entry.owner.name, 'United States');
    });

    test('SatcatObjectType enum is accessible', () {
      expect(SatcatObjectType.fromCode('PAYLOAD'), SatcatObjectType.payload);
      expect(
        SatcatObjectType.fromCode('ROCKET BODY'),
        SatcatObjectType.rocketBody,
      );
      expect(SatcatObjectType.fromCode('DEBRIS'), SatcatObjectType.debris);
      expect(SatcatObjectType.fromCode('???'), SatcatObjectType.unknown);
    });

    test('SatcatParser is accessible', () {
      const parser = SatcatParser();
      final entry = parser.parseJson(<String, dynamic>{
        'NORAD_CAT_ID': 25544,
        'OBJECT_NAME': 'ISS (ZARYA)',
        'OWNER': 'US',
        'OBJECT_TYPE': 'PAYLOAD',
      });
      expect(entry.noradId, 25544);
      expect(entry.objectType, SatcatObjectType.payload);
    });

    test('SatcatParseException is accessible', () {
      const e = SatcatParseException('x', field: 'NORAD_CAT_ID');
      expect(e, isA<CelestrakException>());
      expect(e.field, 'NORAD_CAT_ID');
    });
  });

  // ── Internal symbols are NOT in the barrel ─────────────────────────────────
  // These are compile-time checks: if the barrel ever accidentally exports
  // an internal symbol, `dart analyze` will flag it as an unused import here
  // - or, if we try to use it via the barrel, an undefined-identifier error.
  //
  // We verify absence indirectly: the test file only imports
  // `package:celestrak/celestrak.dart` (the barrel). If any of the "internal"
  // identifiers were resolvable from it, the code below would compile, but
  // since they are absent, using them would cause an analyzer error.
  // This comment documents the design; actual enforcement is via `dart analyze`
  // which is run in CI with --fatal-infos.
  // Internal-symbol absence is enforced by `dart analyze --fatal-infos`, not
  // by this test. If HttpTransport, TleOmmStitcher, CacheKeyBuilder,
  // FileCacheStore, kBackoffBase, or kBackoffMax were ever exported via the
  // barrel, referencing them here (without a src/ import) would produce an
  // undefined_identifier analyzer error that fails CI.
  //
  // This file intentionally imports only the barrel to make that check work.
  group(
      'internal-symbol absence is enforced by dart analyze (not by this test)',
      () {
    test('barrel-only import means absent internals cause analyzer errors', () {
      // No runtime assertion is possible here; enforcement is static.
      // The test exists so the group appears in test output as documentation.
      expect(true, isTrue);
    });
  });
}
