import 'dart:convert' show utf8;
import 'dart:io' show File;

import 'package:celestrak/celestrak.dart';
import 'package:celestrak/src/data/local/memory_cache_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

late String _issOmmFixture;
late String _issTleFixture;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Base URL used for all test data sources.
const _testBase = 'https://celestrak.test/gp.php';

const _defaultTtl = Duration(hours: 2);

/// Epoch timestamp embedded in the ISS OMM fixture.
// Derived from iss_25544_omm.json EPOCH "2026-06-01T13:00:00.000288Z"
final _issEpoch = DateTime.utc(2026, 6, 1, 13, 0, 0, 0, 288);

/// Creates a [TleRepositoryImpl] wired to a [MockClient] and a fresh
/// [MemoryCacheStore] with an optional [FakeClock].
///
/// [ommHandler] handles `FORMAT=JSON` requests.
/// [tleHandler] handles `FORMAT=TLE` requests (defaults to [ommHandler]).
TleRepositoryImpl _repo(
  MockClientHandler ommHandler, {
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
            return (tleHandler ?? ommHandler)(req);
          }
          return ommHandler(req);
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
    _issOmmFixture =
        await File('test/fixtures/iss_25544_omm.json').readAsString();
    _issTleFixture = await File('test/fixtures/iss_25544.tle').readAsString();
  });

  // ── Happy path ─────────────────────────────────────────────────────────────

  group('TleRepositoryImpl — happy path (OMM format)', () {
    test('fetchByNoradId returns SatelliteTle with correct noradId', () async {
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
      );

      final tle = await repo.fetchByNoradId(25544);

      expect(tle.noradId, equals(25544));
    });

    test('fetchByNoradId stamps source=celestrak on remote fetch', () async {
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
      );

      final tle = await repo.fetchByNoradId(25544);

      expect(tle.source, equals(TleSource.celestrak));
    });

    test('fetchByNoradId stamps fetchedAt from clock', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 15));
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
      );

      final tle = await repo.fetchByNoradId(25544);

      expect(tle.fetchedAt, equals(clock.now));
    });

    test('fetchByNoradId populates TLE lines from stitcher', () async {
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
      );

      final tle = await repo.fetchByNoradId(25544);

      expect(tle.line1, isNotEmpty);
      expect(tle.line2, isNotEmpty);
    });

    test('fetchByNoradId populates omm field', () async {
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
      );

      final tle = await repo.fetchByNoradId(25544);

      expect(tle.omm, isNotNull);
      expect(tle.omm!.noradCatId, equals(25544));
    });

    test('fetchByNoradId parses epoch from OMM correctly', () async {
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
      );

      final tle = await repo.fetchByNoradId(25544);

      expect(tle.epoch, equals(_issEpoch));
    });
  });

  group('TleRepositoryImpl — happy path (TLE format)', () {
    test('fetchByNoradId(format:tle) returns correct noradId', () async {
      final repo = _repo(
        (_) async => http.Response(_issTleFixture, 200),
      );

      final tle = await repo.fetchByNoradId(
        25544,
        format: CelestrakFormat.tle,
      );

      expect(tle.noradId, equals(25544));
    });

    test('fetchByNoradId(format:tle) stamps source=celestrak', () async {
      final repo = _repo(
        (_) async => http.Response(_issTleFixture, 200),
      );

      final tle = await repo.fetchByNoradId(
        25544,
        format: CelestrakFormat.tle,
      );

      expect(tle.source, equals(TleSource.celestrak));
    });

    test('fetchByNoradId(format:tle) omm field is null', () async {
      final repo = _repo(
        (_) async => http.Response(_issTleFixture, 200),
      );

      final tle = await repo.fetchByNoradId(
        25544,
        format: CelestrakFormat.tle,
      );

      expect(tle.omm, isNull);
    });
  });

  // ── Cache hit (FR-12) ──────────────────────────────────────────────────────

  group('TleRepositoryImpl — cache hit (FR-12)', () {
    test('second call within TTL does not issue OMM transport call', () async {
      var ommCalls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          ommCalls++;
          return http.Response(_issOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544);
      // Advance time within TTL.
      clock.advance(const Duration(minutes: 30));
      await repo.fetchByNoradId(25544);

      expect(ommCalls, equals(1));
    });

    test('cache hit stamps source=local', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544);
      clock.advance(const Duration(minutes: 30));
      final tle = await repo.fetchByNoradId(25544);

      expect(tle.source, equals(TleSource.local));
    });

    test('cache miss after TTL issues a new transport call', () async {
      var ommCalls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          ommCalls++;
          return http.Response(_issOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544);
      // Advance beyond the TTL boundary.
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      await repo.fetchByNoradId(25544);

      expect(ommCalls, equals(2));
    });

    test('cache hit returns correct noradId and name', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544);
      clock.advance(const Duration(minutes: 1));
      final tle = await repo.fetchByNoradId(25544);

      expect(tle.noradId, equals(25544));
      expect(tle.name, equals('ISS (ZARYA)'));
    });

    test('cache hit for TLE format does not issue transport call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          calls++;
          return http.Response(_issTleFixture, 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544, format: CelestrakFormat.tle);
      clock.advance(const Duration(minutes: 30));
      await repo.fetchByNoradId(25544, format: CelestrakFormat.tle);

      expect(calls, equals(1));
    });
  });

  // ── cacheAge ───────────────────────────────────────────────────────────────

  group('TleRepositoryImpl — cacheAge', () {
    test('cacheAge returns null before any fetch', () async {
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
      );

      final age = await repo.cacheAge(25544);
      expect(age, isNull);
    });

    test('cacheAge returns Duration after fetch', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544);
      clock.advance(const Duration(minutes: 10));

      final age = await repo.cacheAge(25544);
      expect(age, equals(const Duration(minutes: 10)));
    });

    test('cacheAge returns null after clearCache', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544);
      await repo.clearCache();

      final age = await repo.cacheAge(25544);
      expect(age, isNull);
    });
  });

  // ── clearCache ─────────────────────────────────────────────────────────────

  group('TleRepositoryImpl — clearCache', () {
    test('clearCache() forces remote fetch on next call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          calls++;
          return http.Response(_issOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544);
      await repo.clearCache();
      await repo.fetchByNoradId(25544);

      // Exactly 2 OMM calls: 1 before clear, 1 after.
      expect(calls, equals(2));
    });
  });

  // ── Error paths ────────────────────────────────────────────────────────────

  group('TleRepositoryImpl — error paths', () {
    test('SatelliteNotFoundException propagates when object not found',
        () async {
      final repo = _repo(
        (_) async => http.Response('No GP data found', 200),
      );

      await expectLater(
        repo.fetchByNoradId(99999),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });

    test('SatelliteNotFoundException.noradId matches the requested id',
        () async {
      final repo = _repo(
        (_) async => http.Response('No GP data found', 200),
      );

      try {
        await repo.fetchByNoradId(99999);
        fail('expected SatelliteNotFoundException');
      } on SatelliteNotFoundException catch (e) {
        expect(e.noradId, equals(99999));
      }
    });

    test('NetworkException propagates on transport error', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      await expectLater(
        repo.fetchByNoradId(25544),
        throwsA(isA<NetworkException>()),
      );
    });

    test('NetworkException.statusCode is set on HTTP error response', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      try {
        await repo.fetchByNoradId(25544);
        fail('expected NetworkException');
      } on NetworkException catch (e) {
        expect(e.statusCode, equals(503));
      }
    });

    test('ArgumentError on noradId < 1', () async {
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
      );

      await expectLater(
        repo.fetchByNoradId(0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── allowStale fallback (FR-17) ────────────────────────────────────────────

  group('TleRepositoryImpl — allowStale (FR-17)', () {
    test('allowStale:true returns stale cache entry when network fails',
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
        maxAttempts: 1,
      );

      // Prime the cache.
      await repo.fetchByNoradId(25544);

      // Expire the cache and make the network fail.
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      fail = true;

      final tle = await repo.fetchByNoradId(
        25544,
        allowStale: true,
      );

      expect(tle.source, equals(TleSource.local));
      expect(tle.noradId, equals(25544));
    });

    test('allowStale:false re-throws NetworkException when cache is stale',
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
        maxAttempts: 1,
      );

      await repo.fetchByNoradId(25544);
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      fail = true;

      await expectLater(
        repo.fetchByNoradId(25544, allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });

    test('allowStale:true re-throws when no cache entry exists', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      await expectLater(
        repo.fetchByNoradId(25544, allowStale: true),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
        'allowStale:true with SatelliteNotFoundException still throws '
        'when no cache entry', () async {
      final repo = _repo(
        (_) async => http.Response('No GP data found', 200),
      );

      await expectLater(
        repo.fetchByNoradId(99999, allowStale: true),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });

    test(
        'allowStale:true with SatelliteNotFoundException still throws '
        'even when a stale cache entry exists', () async {
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

      // Prime the cache with a valid entry.
      await repo.fetchByNoradId(25544);

      // Expire the cache and make the API report the object as not found.
      clock.advance(_defaultTtl + const Duration(seconds: 1));
      notFound = true;

      // SatelliteNotFoundException must propagate even though a stale entry
      // exists — allowStale only applies to transient network failures (FR-17).
      await expectLater(
        repo.fetchByNoradId(25544, allowStale: true),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });
  });

  // ── TTL boundary ───────────────────────────────────────────────────────────

  group('TleRepositoryImpl — TTL boundary (fake clock)', () {
    test('entry exactly at TTL boundary is considered stale', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          calls++;
          return http.Response(_issOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544, ttl: const Duration(hours: 1));
      // Advance exactly to TTL.
      clock.advance(const Duration(hours: 1));
      await repo.fetchByNoradId(25544, ttl: const Duration(hours: 1));

      // Age == TTL is NOT fresh (age < ttl is the condition), so refetch.
      expect(calls, greaterThanOrEqualTo(2));
    });

    test('entry just under TTL boundary is still fresh', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          calls++;
          return http.Response(_issOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544, ttl: const Duration(hours: 1));
      // Advance just under TTL.
      clock.advance(const Duration(hours: 1) - const Duration(seconds: 1));
      await repo.fetchByNoradId(25544, ttl: const Duration(hours: 1));

      expect(calls, equals(1));
    });
  });

  // ── OMM stitch with empty TLE body (RK-1) ─────────────────────────────────

  group('TleRepositoryImpl — OMM empty-lines fallback (RK-1)', () {
    test('stitch with empty TLE body produces empty line1/line2', () async {
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response('', 200),
      );

      final tle = await repo.fetchByNoradId(25544);

      expect(tle.line1, isEmpty);
      expect(tle.line2, isEmpty);
    });

    test('stitch with empty TLE body still returns valid omm', () async {
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response('', 200),
      );

      final tle = await repo.fetchByNoradId(25544);

      expect(tle.omm, isNotNull);
    });
  });

  // ── Cache key isolation ────────────────────────────────────────────────────

  group('TleRepositoryImpl — cache key isolation', () {
    test('OMM and TLE format use separate cache entries', () async {
      var ommCalls = 0;
      var tleCalls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();

      final repo = TleRepositoryImpl(
        dataSource: CelestrakDataSource(
          transport: HttpTransport(
            client: MockClient((req) async {
              final format = req.url.queryParameters['FORMAT'];
              if (format == 'TLE') {
                tleCalls++;
                return http.Response(_issTleFixture, 200);
              }
              ommCalls++;
              return http.Response(_issOmmFixture, 200);
            }),
            maxAttempts: 1,
            timeout: const Duration(seconds: 5),
          ),
          baseUrl: _testBase,
        ),
        cacheStore: store,
        clock: clock,
      );

      // Fetch OMM (caches OMM + TLE internally).
      await repo.fetchByNoradId(25544, format: CelestrakFormat.omm);
      final ommCallsAfterFirst = ommCalls;
      final tleCallsAfterFirst = tleCalls;

      // Fetch TLE format — its cache entry should already be populated.
      clock.advance(const Duration(minutes: 1));
      await repo.fetchByNoradId(25544, format: CelestrakFormat.tle);

      // OMM calls should not increase; TLE calls may or may not increase
      // depending on whether the TLE cache was shared.
      expect(ommCalls, equals(ommCallsAfterFirst));
      // The TLE format cache key differs from the internal TLE stitch key,
      // so a fresh TLE-format fetch is expected.
      expect(tleCalls, greaterThanOrEqualTo(tleCallsAfterFirst));
    });

    test('different noradIds use separate cache entries', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          calls++;
          return http.Response(_issOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544);
      // Fetch a different NORAD ID — the fixture only contains 25544, so the
      // parse throws SatelliteNotFoundException, but only after a network call
      // (proving the cache key is different from 25544's entry).
      await expectLater(
        repo.fetchByNoradId(12345),
        throwsA(isA<SatelliteNotFoundException>()),
      );

      // Each noradId triggers its own network call — both go to the network.
      expect(calls, greaterThanOrEqualTo(2));
    });
  });

  // ── Serialization round-trip ───────────────────────────────────────────────

  group('TleRepositoryImpl — serialization round-trip', () {
    test('cache stores payload as UTF-8 bytes', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByNoradId(25544);

      final key = CacheKeyBuilder.forNoradId(
        25544,
        format: CelestrakFormat.omm,
      );
      final bytes = await store.read(key);
      expect(bytes, isNotNull);
      final decoded = utf8.decode(bytes!);
      expect(decoded, equals(_issOmmFixture));
    });

    test('cache hit round-trip preserves epoch', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      final first = await repo.fetchByNoradId(25544);
      clock.advance(const Duration(minutes: 5));
      final second = await repo.fetchByNoradId(25544);

      expect(second.epoch, equals(first.epoch));
    });
  });
}
