/// CEL-52 / CEL-54: allowStale fallback — stale-while-revalidate semantics (FR-17).
///
/// Verifies:
/// - network fail + allowStale:true → stale cache returned + isStale() true
/// - allowStale:false + no fresh cache + no network → NetworkException
/// - allowStale:true + no cache entry at all → NetworkException (re-throw)
/// - SatelliteNotFoundException is never masked by the allowStale fallback
/// - consistent behaviour across fetchByNoradId, fetchCategory,
///   fetchCategoryByGroup, fetchByName, fetchByIntlDesignator.
library;

import 'package:celestrak/celestrak.dart';
import 'package:celestrak/src/data/remote/celestrak_data_source.dart';
import 'package:celestrak/src/data/tle_repository_impl.dart';
import 'package:celestrak/src/network/http_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';
import '../support/fixture_loader.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

late String _issOmmFixture;
late String _issTleFixture;
late String _stationsOmmFixture;
late String _stationsTleFixture;
late String _nameIssOmmFixture;
late String _nameIssTleFixture;
late String _intdesOmmFixture;
late String _intdesTleFixture;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testBase = 'https://celestrak.test/gp.php';
const _defaultTtl = Duration(hours: 2);

// ISS epoch in the fixture: 2026-06-01T13:00:00Z.
// Default staleThreshold is 3 days — advance clock by 4 days so the
// returned record's isStale() is true when using the default threshold.
const _staleDuration = Duration(days: 4);

/// Creates a [TleRepositoryImpl] with a [MockClient] and a caller-supplied
/// [MemoryCacheStore] and [FakeClock].
///
/// [handler] receives all non-TLE requests; [tleHandler] intercepts
/// `FORMAT=TLE` requests (defaults to [handler]).
///
/// [clock] and [store] are required so that tests always operate on
/// known, test-controlled instances — omitting them would silently create
/// independent defaults and mask missing-cache-entry logic.
TleRepositoryImpl _repo(
  MockClientHandler handler, {
  required FakeClock clock,
  required MemoryCacheStore store,
  MockClientHandler? tleHandler,
  int maxAttempts = 1,
}) {
  return TleRepositoryImpl(
    dataSource: CelestrakDataSource(
      transport: HttpTransport(
        client: MockClient((req) async {
          final format = req.url.queryParameters['FORMAT'];
          if (format == 'TLE') {
            return (tleHandler ?? handler)(req);
          }
          return handler(req);
        }),
        maxAttempts: maxAttempts,
        timeout: const Duration(seconds: 10),
      ),
      baseUrl: _testBase,
    ),
    cacheStore: store,
    clock: clock,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    _issOmmFixture = await loadFixture('test/fixtures/iss_25544_omm.json');
    _issTleFixture = await loadFixture('test/fixtures/iss_25544.tle');
    _stationsOmmFixture =
        await loadFixture('test/fixtures/stations_group_omm.json');
    _stationsTleFixture = await loadFixture('test/fixtures/stations_group.txt');
    _nameIssOmmFixture = await loadFixture('test/fixtures/name_iss_omm.json');
    _nameIssTleFixture = await loadFixture('test/fixtures/name_iss.txt');
    _intdesOmmFixture =
        await loadFixture('test/fixtures/intdes_1998_067a_omm.json');
    _intdesTleFixture = await loadFixture('test/fixtures/intdes_1998_067a.txt');
  });

  // ── fetchByNoradId

  group('allowStale (FR-18) — fetchByNoradId', () {
    test('network fail + allowStale:true → source==local and isStale() is true',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final repo = _repo(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_issOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_issTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544);
      // Advance beyond TTL and beyond 3-day staleThreshold so isStale is true.
      clock.advance(_staleDuration);
      fail = true;

      final tle = await repo.fetchByNoradId(25544, allowStale: true);

      expect(tle.source, equals(TleSource.local));
      expect(
        tle.isStale(now: clock.now),
        isTrue,
        reason: 'stale cache returned via allowStale must report isStale=true',
      );
    });

    test('allowStale:false + no fresh cache + network fail → NetworkException',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final repo = _repo(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_issOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_issTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544);
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      fail = true;

      await expectLater(
        repo.fetchByNoradId(25544, allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });

    test('allowStale:true + no cache entry at all → NetworkException re-thrown',
        () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchByNoradId(25544, allowStale: true),
        throwsA(isA<NetworkException>()),
      );
    });

    test('allowStale:true does not suppress SatelliteNotFoundException',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var notFound = false;
      final repo = _repo(
        (_) async {
          if (notFound) return http.Response('No GP data found', 200);
          return http.Response(_issOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (notFound) return http.Response('No GP data found', 200);
          return http.Response(_issTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544);
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      notFound = true;

      await expectLater(
        repo.fetchByNoradId(25544, allowStale: true),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });
  });

  // ── fetchCategory

  group('allowStale (FR-18) — fetchCategory', () {
    test('network fail + allowStale:true → source==local and isStale() is true',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final repo = _repo(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_stationsOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_stationsTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchCategory(SatelliteCategory.stations);
      clock.advance(_staleDuration);
      fail = true;

      final results = await repo.fetchCategory(
        SatelliteCategory.stations,
        allowStale: true,
      );

      expect(results, isNotEmpty);
      for (final r in results) {
        expect(r.source, equals(TleSource.local));
        expect(
          r.isStale(now: clock.now),
          isTrue,
          reason:
              'stale cache returned via allowStale must report isStale=true',
        );
      }
    });

    test('allowStale:false + no fresh cache + network fail → NetworkException',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final repo = _repo(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_stationsOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_stationsTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchCategory(SatelliteCategory.stations);
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      fail = true;

      await expectLater(
        repo.fetchCategory(SatelliteCategory.stations, allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });

    test('allowStale:true + no cache entry at all → NetworkException re-thrown',
        () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchCategory(SatelliteCategory.stations, allowStale: true),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // ── fetchCategoryByGroup

  group('allowStale (FR-18) — fetchCategoryByGroup', () {
    test('network fail + allowStale:true → source==local and isStale() is true',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final repo = _repo(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_stationsOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_stationsTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchCategoryByGroup('stations');
      clock.advance(_staleDuration);
      fail = true;

      final results = await repo.fetchCategoryByGroup(
        'stations',
        allowStale: true,
      );

      expect(results, isNotEmpty);
      for (final r in results) {
        expect(r.source, equals(TleSource.local));
        expect(
          r.isStale(now: clock.now),
          isTrue,
          reason:
              'stale cache returned via allowStale must report isStale=true',
        );
      }
    });

    test('allowStale:false + no fresh cache + network fail → NetworkException',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final repo = _repo(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_stationsOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_stationsTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchCategoryByGroup('stations');
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      fail = true;

      await expectLater(
        repo.fetchCategoryByGroup('stations', allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });

    test('allowStale:true + no cache entry at all → NetworkException re-thrown',
        () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchCategoryByGroup('stations', allowStale: true),
        throwsA(isA<NetworkException>()),
      );
    });

    test('allowStale:true does not suppress SatelliteNotFoundException',
        () async {
      // Note: unlike fetchByName/fetchByIntlDesignator (which return an empty
      // string for the not-found sentinel), CelestrakDataSource.fetchByGroup
      // throws SatelliteNotFoundException directly when the sentinel body is
      // received. This test therefore exercises a real, reachable code path —
      // the SatelliteNotFoundException guard in fetchCategoryByGroup is not
      // merely defensive.
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var notFound = false;
      final repo = _repo(
        (_) async {
          if (notFound) return http.Response('No GP data found', 200);
          return http.Response(_stationsOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (notFound) return http.Response('No GP data found', 200);
          return http.Response(_stationsTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchCategoryByGroup('stations');
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      notFound = true;

      await expectLater(
        repo.fetchCategoryByGroup('stations', allowStale: true),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });
  });

  // ── fetchByName

  group('allowStale (FR-18) — fetchByName', () {
    test('network fail + allowStale:true → source==local and isStale() is true',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final repo = _repo(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_nameIssOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_nameIssTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchByName('ISS');
      clock.advance(_staleDuration);
      fail = true;

      final results = await repo.fetchByName('ISS', allowStale: true);

      expect(results, isNotEmpty);
      for (final r in results) {
        expect(r.source, equals(TleSource.local));
        expect(
          r.isStale(now: clock.now),
          isTrue,
          reason:
              'stale cache returned via allowStale must report isStale=true',
        );
      }
    });

    test('allowStale:false + no fresh cache + network fail → NetworkException',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final repo = _repo(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_nameIssOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_nameIssTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchByName('ISS');
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      fail = true;

      await expectLater(
        repo.fetchByName('ISS', allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });

    test('allowStale:true + no cache entry at all → NetworkException re-thrown',
        () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchByName('ISS', allowStale: true),
        throwsA(isA<NetworkException>()),
      );
    });
    // Note: fetchByName data source converts the CelesTrak not-found sentinel
    // to an empty string (not SatelliteNotFoundException), so that exception
    // cannot be triggered via this path in tests. The guard in the repository
    // is defensive for future parse paths.
  });

  // ── fetchByIntlDesignator

  group('allowStale (FR-18) — fetchByIntlDesignator', () {
    test('network fail + allowStale:true → source==local and isStale() is true',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final repo = _repo(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_intdesOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_intdesTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchByIntlDesignator('1998-067A');
      clock.advance(_staleDuration);
      fail = true;

      final results = await repo.fetchByIntlDesignator(
        '1998-067A',
        allowStale: true,
      );

      expect(results, isNotEmpty);
      for (final r in results) {
        expect(r.source, equals(TleSource.local));
        expect(
          r.isStale(now: clock.now),
          isTrue,
          reason:
              'stale cache returned via allowStale must report isStale=true',
        );
      }
    });

    test('allowStale:false + no fresh cache + network fail → NetworkException',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final repo = _repo(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_intdesOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_intdesTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchByIntlDesignator('1998-067A');
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      fail = true;

      await expectLater(
        repo.fetchByIntlDesignator('1998-067A', allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });

    test('allowStale:true + no cache entry at all → NetworkException re-thrown',
        () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchByIntlDesignator('1998-067A', allowStale: true),
        throwsA(isA<NetworkException>()),
      );
    });

    test('allowStale:true + malformed designator → ArgumentError (not masked)',
        () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchByIntlDesignator('bad-format', allowStale: true),
        throwsA(isA<ArgumentError>()),
      );
    });
    // Note: fetchByIntlDesignator data source converts the CelesTrak not-found
    // sentinel to an empty string (not SatelliteNotFoundException), so that
    // exception cannot be triggered via this path in tests. The guard in the
    // repository is defensive for future parse paths.
  });

  // ── fetchByNoradId (TLE format)

  group('allowStale (FR-18) — fetchByNoradId (format: CelestrakFormat.tle)',
      () {
    test(
        'network fail + allowStale:true + TLE format → source==local and '
        'isStale() is true', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final repo = _repo(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_issTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544, format: CelestrakFormat.tle);
      // Advance beyond TTL and beyond 3-day staleThreshold so isStale is true.
      clock.advance(_staleDuration);
      fail = true;

      final tle = await repo.fetchByNoradId(
        25544,
        format: CelestrakFormat.tle,
        allowStale: true,
      );

      expect(tle.source, equals(TleSource.local));
      expect(
        tle.isStale(now: clock.now),
        isTrue,
        reason: 'stale TLE-format cache returned via allowStale must report '
            'isStale=true',
      );
    });

    test(
        'allowStale:true + TLE format + SatelliteNotFoundException not '
        'suppressed', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var notFound = false;
      final repo = _repo(
        (_) async {
          if (notFound) return http.Response('No GP data found', 200);
          return http.Response(_issTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544, format: CelestrakFormat.tle);
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      notFound = true;

      await expectLater(
        repo.fetchByNoradId(
          25544,
          format: CelestrakFormat.tle,
          allowStale: true,
        ),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });
  });

  // ── fetchCategory: SatelliteNotFoundException not suppressed

  group('allowStale (FR-18) — fetchCategory SatelliteNotFoundException', () {
    test(
        'allowStale:true does not suppress SatelliteNotFoundException for '
        'fetchCategory', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var notFound = false;
      final repo = _repo(
        (_) async {
          if (notFound) return http.Response('No GP data found', 200);
          return http.Response(_stationsOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (notFound) return http.Response('No GP data found', 200);
          return http.Response(_stationsTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      // Prime the cache with a valid response.
      await repo.fetchCategory(SatelliteCategory.stations);
      // Advance past TTL so the next call attempts a network fetch.
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      notFound = true;

      // Even with allowStale:true and a stale cache entry present, the
      // SatelliteNotFoundException must propagate — unknown groups are not
      // masked by the stale fallback.
      await expectLater(
        repo.fetchCategory(SatelliteCategory.stations, allowStale: true),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });
  });
}
