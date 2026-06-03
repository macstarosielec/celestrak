import 'dart:convert' show utf8;

import 'package:celestrak/celestrak.dart';
import 'package:celestrak/src/data/local/memory_cache_store.dart';
import 'package:celestrak/src/data/remote/celestrak_data_source.dart';
import 'package:celestrak/src/data/tle_repository_impl.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';
import '../support/fixture_loader.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

late String _stationsOmmFixture;
late String _stationsTleFixture;
late String _stationsOmmGroupFixture;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testBase = 'https://celestrak.test/gp.php';
const _defaultTtl = Duration(hours: 2);

/// Creates a [TleRepositoryImpl] wired to a [MockClient] and a fresh
/// [MemoryCacheStore] with an optional [FakeClock].
///
/// [groupHandler] handles `GROUP=` requests.
/// [tleHandler] handles `FORMAT=TLE` requests (defaults to [groupHandler]).
TleRepositoryImpl _repo(
  MockClientHandler groupHandler, {
  MockClientHandler? tleHandler,
  FakeClock? clock,
  MemoryCacheStore? store,
  int maxAttempts = 1,
}) {
  final effectiveClock = clock ?? FakeClock(DateTime.utc(2026, 6, 1, 14));
  final effectiveStore = store ?? MemoryCacheStore();

  return TleRepositoryImpl(
    dataSource: CelestrakDataSource(
      transport: HttpTransport(
        client: MockClient((req) async {
          final format = req.url.queryParameters['FORMAT'];
          if (format == 'TLE') {
            return (tleHandler ?? groupHandler)(req);
          }
          return groupHandler(req);
        }),
        maxAttempts: maxAttempts,
        timeout: const Duration(seconds: 5),
      ),
      baseUrl: _testBase,
    ),
    cacheStore: effectiveStore,
    clock: effectiveClock,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    _stationsOmmGroupFixture =
        await loadFixture('test/fixtures/stations_group_omm.json');
    _stationsTleFixture = await loadFixture('test/fixtures/stations_group.txt');
    _stationsOmmFixture = await loadFixture('test/fixtures/iss_25544_omm.json');
  });

  // ── Happy path (OMM) ───────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchCategory — happy path (OMM)', () {
    test('returns non-empty list for stations category', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await repo.fetchCategory(SatelliteCategory.stations);

      expect(results, isNotEmpty);
    });

    test('stations result includes ISS (noradId=25544)', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await repo.fetchCategory(SatelliteCategory.stations);
      final noradIds = results.map((r) => r.noradId).toList();

      expect(noradIds, contains(25544));
    });

    test('stamps source=celestrak on remote fetch', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await repo.fetchCategory(SatelliteCategory.stations);

      for (final r in results) {
        expect(r.source, equals(TleSource.celestrak));
      }
    });

    test('stations fixture returns exactly three records', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await repo.fetchCategory(SatelliteCategory.stations);

      expect(results.length, equals(3));
    });
  });

  // ── Happy path (TLE) ──────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchCategory — happy path (TLE format)', () {
    test('returns non-empty list for stations category', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await repo.fetchCategory(
        SatelliteCategory.stations,
        format: CelestrakFormat.tle,
      );

      expect(results, isNotEmpty);
    });

    test('stamps source=celestrak on remote TLE fetch', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await repo.fetchCategory(
        SatelliteCategory.stations,
        format: CelestrakFormat.tle,
      );

      for (final r in results) {
        expect(r.source, equals(TleSource.celestrak));
      }
    });

    test('stations TLE fixture returns three records', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await repo.fetchCategory(
        SatelliteCategory.stations,
        format: CelestrakFormat.tle,
      );

      expect(results.length, equals(3));
    });

    test('TLE records have omm field null', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await repo.fetchCategory(
        SatelliteCategory.stations,
        format: CelestrakFormat.tle,
      );

      for (final r in results) {
        expect(r.omm, isNull);
      }
    });
  });

  // ── Per-category cache key (FR-2 / FR-12) ─────────────────────────────────

  group('TleRepositoryImpl.fetchCategory — per-category cache key', () {
    test('second call within TTL does not issue transport call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          calls++;
          return http.Response(_stationsOmmGroupFixture, 200);
        },
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchCategory(SatelliteCategory.stations);
      clock.advance(const Duration(minutes: 30));
      await repo.fetchCategory(SatelliteCategory.stations);

      expect(calls, equals(1));
    });

    test('cache hit stamps source=local on all records', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchCategory(SatelliteCategory.stations);
      clock.advance(const Duration(minutes: 30));
      final results = await repo.fetchCategory(SatelliteCategory.stations);

      for (final r in results) {
        expect(r.source, equals(TleSource.local));
      }
    });

    test('different categories use separate cache entries', () async {
      var stationsCalls = 0;
      var starlinkCalls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();

      final repo = TleRepositoryImpl(
        dataSource: CelestrakDataSource(
          transport: HttpTransport(
            client: MockClient((req) async {
              final group = req.url.queryParameters['GROUP'];
              final format = req.url.queryParameters['FORMAT'];
              // Supplementary TLE fetches always return TLE fixture.
              if (format == 'TLE') {
                return http.Response(_stationsTleFixture, 200);
              }
              if (group == 'stations') {
                stationsCalls++;
                return http.Response(_stationsOmmGroupFixture, 200);
              }
              if (group == 'starlink') {
                starlinkCalls++;
                return http.Response(_stationsOmmGroupFixture, 200);
              }
              return http.Response(_stationsTleFixture, 200);
            }),
            maxAttempts: 1,
            timeout: const Duration(seconds: 5),
          ),
          baseUrl: _testBase,
        ),
        cacheStore: store,
        clock: clock,
      );

      await repo.fetchCategory(SatelliteCategory.stations);
      await repo.fetchCategory(SatelliteCategory.starlink);

      // Both categories triggered their own OMM network call.
      expect(stationsCalls, equals(1));
      expect(starlinkCalls, equals(1));

      // Within TTL — no new calls for either category.
      clock.advance(const Duration(minutes: 30));
      await repo.fetchCategory(SatelliteCategory.stations);
      await repo.fetchCategory(SatelliteCategory.starlink);

      expect(stationsCalls, equals(1));
      expect(starlinkCalls, equals(1));
    });

    test('cache miss after TTL issues a new transport call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          calls++;
          return http.Response(_stationsOmmGroupFixture, 200);
        },
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchCategory(SatelliteCategory.stations);
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      await repo.fetchCategory(SatelliteCategory.stations);

      expect(calls, greaterThanOrEqualTo(2));
    });

    test('category cache key differs from noradId cache key', () async {
      var noradCalls = 0;
      var groupCalls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();

      final repo = TleRepositoryImpl(
        dataSource: CelestrakDataSource(
          transport: HttpTransport(
            client: MockClient((req) async {
              final hasGroup = req.url.queryParameters.containsKey('GROUP');
              final format = req.url.queryParameters['FORMAT'];
              if (hasGroup) {
                // Supplementary TLE group fetch returns TLE fixture.
                if (format == 'TLE') {
                  return http.Response(_stationsTleFixture, 200);
                }
                groupCalls++;
                return http.Response(_stationsOmmGroupFixture, 200);
              }
              noradCalls++;
              if (format == 'TLE') {
                return http.Response(_stationsTleFixture, 200);
              }
              return http.Response(_stationsOmmFixture, 200);
            }),
            maxAttempts: 1,
            timeout: const Duration(seconds: 5),
          ),
          baseUrl: _testBase,
        ),
        cacheStore: store,
        clock: clock,
      );

      // Fetch by NORAD ID (primes a norad-keyed cache entry).
      await repo.fetchByNoradId(25544);
      // Fetch by category (uses a different group-keyed cache entry).
      await repo.fetchCategory(SatelliteCategory.stations);

      // Both paths must have issued network calls independently.
      expect(noradCalls, greaterThanOrEqualTo(1));
      expect(groupCalls, greaterThanOrEqualTo(1));
    });
  });

  // ── categoryAge ───────────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchCategory — categoryAge', () {
    test('categoryAge returns null before any fetch', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
      );

      final age = await repo.categoryAge(SatelliteCategory.stations);

      expect(age, isNull);
    });

    test('categoryAge returns Duration after fetch', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchCategory(SatelliteCategory.stations);
      clock.advance(const Duration(minutes: 15));

      final age = await repo.categoryAge(SatelliteCategory.stations);

      expect(age, equals(const Duration(minutes: 15)));
    });

    test('categoryAge returns null after clearCache', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchCategory(SatelliteCategory.stations);
      await repo.clearCache();

      final age = await repo.categoryAge(SatelliteCategory.stations);

      expect(age, isNull);
    });

    test('categoryAge is per-category independent', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();

      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchCategory(SatelliteCategory.stations);
      // starlink was never fetched — its age must be null.
      final age = await repo.categoryAge(SatelliteCategory.starlink);

      expect(age, isNull);
    });
  });

  // ── allowStale (FR-17) ────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchCategory — allowStale (FR-17)', () {
    test('allowStale:true returns stale cache when network fails', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final repo = _repo(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_stationsOmmGroupFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_stationsTleFixture, 200);
        },
        clock: clock,
        store: store,
        maxAttempts: 1,
      );

      await repo.fetchCategory(SatelliteCategory.stations);
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      fail = true;

      final results = await repo.fetchCategory(
        SatelliteCategory.stations,
        allowStale: true,
      );

      expect(results, isNotEmpty);
      for (final r in results) {
        expect(r.source, equals(TleSource.local));
      }
    });

    test('allowStale:false re-throws NetworkException when network fails',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final repo = _repo(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_stationsOmmGroupFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_stationsTleFixture, 200);
        },
        clock: clock,
        store: store,
        maxAttempts: 1,
      );

      await repo.fetchCategory(SatelliteCategory.stations);
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      fail = true;

      await expectLater(
        repo.fetchCategory(SatelliteCategory.stations, allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });

    test('allowStale:true re-throws when no cache entry exists', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      await expectLater(
        repo.fetchCategory(
          SatelliteCategory.stations,
          allowStale: true,
        ),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // ── cache payload isolation ────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchCategory — cache payload', () {
    test('cache stores payload as UTF-8 bytes', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchCategory(SatelliteCategory.stations);

      final key = CacheKeyBuilder.forCategory(
        SatelliteCategory.stations,
        format: CelestrakFormat.omm,
      );
      final bytes = await store.read(key);
      expect(bytes, isNotNull);
      final decoded = utf8.decode(bytes!);
      expect(decoded, equals(_stationsOmmGroupFixture));
    });

    test('TTL boundary: entry at exact TTL triggers refetch', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          calls++;
          return http.Response(_stationsOmmGroupFixture, 200);
        },
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchCategory(
        SatelliteCategory.stations,
        ttl: const Duration(hours: 1),
      );
      clock.advance(const Duration(hours: 1));
      await repo.fetchCategory(
        SatelliteCategory.stations,
        ttl: const Duration(hours: 1),
      );

      expect(calls, greaterThanOrEqualTo(2));
    });
  });
}
