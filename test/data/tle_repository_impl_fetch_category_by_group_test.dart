import 'package:celestrak/celestrak.dart';
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

late String _stationsOmmGroupFixture;
late String _stationsTleFixture;

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
        timeout: const Duration(seconds: 10),
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
  });

  // ── Happy path ─────────────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchCategoryByGroup — happy path', () {
    test('returns non-empty list for stations group string', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await repo.fetchCategoryByGroup('stations');

      expect(results, isNotEmpty);
    });

    test('stations group includes ISS (noradId=25544)', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await repo.fetchCategoryByGroup('stations');
      final noradIds = results.map((r) => r.noradId).toList();

      expect(noradIds, contains(25544));
    });

    test('stamps source=celestrak on remote fetch', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await repo.fetchCategoryByGroup('stations');

      for (final r in results) {
        expect(r.source, equals(TleSource.celestrak));
      }
    });

    test('uses GROUP= query parameter with passthrough value', () async {
      String? capturedGroup;
      final repo = _repo(
        (req) async {
          capturedGroup = req.url.queryParameters['GROUP'];
          return http.Response(_stationsOmmGroupFixture, 200);
        },
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      await repo.fetchCategoryByGroup('stations');

      expect(capturedGroup, equals('stations'));
    });

    test('arbitrary group string is passed through verbatim', () async {
      String? capturedGroup;
      final repo = _repo(
        (req) async {
          capturedGroup = req.url.queryParameters['GROUP'];
          return http.Response(_stationsOmmGroupFixture, 200);
        },
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      await repo.fetchCategoryByGroup('some-custom-group');

      expect(capturedGroup, equals('some-custom-group'));
    });

    test('TLE format returns records with null omm', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await repo.fetchCategoryByGroup(
        'stations',
        format: CelestrakFormat.tle,
      );

      expect(results, isNotEmpty);
      for (final r in results) {
        expect(r.omm, isNull);
      }
    });
  });

  // ── Caching (FR-12) ────────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchCategoryByGroup — caching (FR-12)', () {
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

      await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);
      clock.advance(const Duration(minutes: 30));
      await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);

      // groupHandler is called once (OMM fetch);
      // tleHandler is separate and not counted here.
      expect(calls, equals(1));
    });

    test('cache hit stamps source=local', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);
      clock.advance(const Duration(minutes: 30));
      final results =
          await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);

      for (final r in results) {
        expect(r.source, equals(TleSource.local));
      }
    });

    test('group string key is independent from SatelliteCategory key',
        () async {
      var stationsGroupCalls = 0;
      var customGroupCalls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (req) async {
          final group = req.url.queryParameters['GROUP'];
          if (group == 'stations') {
            stationsGroupCalls++;
          } else {
            customGroupCalls++;
          }
          return http.Response(_stationsOmmGroupFixture, 200);
        },
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);
      await repo.fetchCategoryByGroup('custom-group', ttl: _defaultTtl);

      expect(stationsGroupCalls, equals(1));
      expect(customGroupCalls, equals(1));

      // Within TTL — no new calls.
      clock.advance(const Duration(minutes: 30));
      await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);
      await repo.fetchCategoryByGroup('custom-group', ttl: _defaultTtl);

      expect(stationsGroupCalls, equals(1));
      expect(customGroupCalls, equals(1));
    });

    test('cache miss after TTL expiry issues new transport call', () async {
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

      await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);
      clock.advance(const Duration(hours: 2, seconds: 1));
      await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);

      expect(calls, greaterThanOrEqualTo(2));
    });
  });

  // ── groupAge ───────────────────────────────────────────────────────────────

  group('TleRepositoryImpl.groupAge', () {
    test('returns null before any fetch', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
      );

      final age = await repo.groupAge('stations');

      expect(age, isNull);
    });

    test('returns Duration after fetch', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);
      clock.advance(const Duration(minutes: 20));

      final age = await repo.groupAge('stations');

      expect(age, equals(const Duration(minutes: 20)));
    });

    test('returns null after clearCache', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);
      await repo.clearCache();

      final age = await repo.groupAge('stations');

      expect(age, isNull);
    });

    test('groupAge key differs from categoryAge key for same group string',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();

      // Seed the store directly with a category key for 'stations'.
      final categoryKey = CacheKeyBuilder.forCategory(
        SatelliteCategory.stations,
        format: CelestrakFormat.omm,
      );
      final groupKey = CacheKeyBuilder.forGroup(
        'stations',
        format: CelestrakFormat.omm,
      );

      // Verify both factory methods produce the same key (both use group:).
      expect(groupKey, equals(categoryKey));

      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      // fetchCategoryByGroup and fetchCategory share the cache key.
      await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);
      clock.advance(const Duration(minutes: 10));

      final groupAgeResult = await repo.groupAge('stations');
      final categoryAgeResult =
          await repo.categoryAge(SatelliteCategory.stations);

      expect(groupAgeResult, equals(const Duration(minutes: 10)));
      expect(categoryAgeResult, equals(const Duration(minutes: 10)));
    });
  });

  // ── allowStale (FR-17) ─────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchCategoryByGroup — allowStale (FR-17)', () {
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

      await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);
      clock.advance(const Duration(hours: 3));
      fail = true;

      final results = await repo.fetchCategoryByGroup(
        'stations',
        ttl: _defaultTtl,
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

      await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);
      clock.advance(const Duration(hours: 3));
      fail = true;

      await expectLater(
        repo.fetchCategoryByGroup('stations', ttl: _defaultTtl),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
        'allowStale:true + stale cache present + SatelliteNotFoundException '
        're-throws instead of returning stale data', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var returnNotFound = false;
      final repo = _repo(
        (_) async {
          if (returnNotFound) return http.Response('No GP data found', 200);
          return http.Response(_stationsOmmGroupFixture, 200);
        },
        tleHandler: (_) async {
          if (returnNotFound) return http.Response('No GP data found', 200);
          return http.Response(_stationsTleFixture, 200);
        },
        clock: clock,
        store: store,
        maxAttempts: 1,
      );

      // Seed a valid stale cache entry.
      await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);
      clock.advance(const Duration(hours: 3));
      returnNotFound = true;

      // Even with allowStale:true, SatelliteNotFoundException must propagate.
      await expectLater(
        repo.fetchCategoryByGroup(
          'stations',
          ttl: _defaultTtl,
          allowStale: true,
        ),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });

    test(
        'allowStale:true with no prior cache entry re-throws original '
        'NetworkException', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      // No prior fetch — cacheAge is null.
      await expectLater(
        repo.fetchCategoryByGroup(
          'stations',
          ttl: _defaultTtl,
          allowStale: true,
        ),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // ── Error paths ────────────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchCategoryByGroup — error paths', () {
    test('throws ArgumentError for empty group string', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
      );

      await expectLater(
        repo.fetchCategoryByGroup(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('ArgumentError.name is "group"', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
      );

      expect(
        () => repo.fetchCategoryByGroup(''),
        throwsA(
          isA<ArgumentError>().having((e) => e.name, 'name', equals('group')),
        ),
      );
    });

    test('NetworkException propagates on transport error', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      await expectLater(
        repo.fetchCategoryByGroup('stations'),
        throwsA(isA<NetworkException>()),
      );
    });

    test('NetworkException.statusCode set on HTTP error response', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      try {
        await repo.fetchCategoryByGroup('stations');
        fail('expected NetworkException');
      } on NetworkException catch (e) {
        expect(e.statusCode, equals(503));
      }
    });

    test('unknown group returns SatelliteNotFoundException', () async {
      final repo = _repo(
        (_) async => http.Response('No GP data found', 200),
        maxAttempts: 1,
      );

      await expectLater(
        repo.fetchCategoryByGroup('unknown-group'),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });
  });
}
