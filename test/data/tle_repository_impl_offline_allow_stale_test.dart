/// CEL-54: Offline / allowStale tests (P6).
///
/// Acceptance criteria (US-4, NFR-8, FR-18, FR-19):
///   1. fetchCategory(allowStale:true) offline → cached list returned with
///      source==local and isStale() true (US-4).
///   2. allowStale:false + offline + no cache → NetworkException (FR-18).
///   3. forceCache:true + no cached entry → CacheMissException with zero
///      transport calls (FR-19).
///   4. forceCache:true + cached entry → returns from cache, zero transport
///      calls.
///   5. All five fetch methods exercised: fetchByNoradId, fetchCategory,
///      fetchCategoryByGroup, fetchByName, fetchByIntlDesignator.
///   6. Never crashes on network loss — always throws a typed
///      CelestrakException, never an unhandled SocketException or similar
///      (NFR-8).
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
// Constants
// ---------------------------------------------------------------------------

const _testBase = 'https://celestrak.test/gp.php';
const _defaultTtl = Duration(hours: 2);

// ISS epoch in the fixtures is 2026-06-01T13:00:00Z.
// The default staleThreshold is 3 days — advance the clock 4 days so that
// isStale() returns true when the record is served from cache.
const _staleDuration = Duration(days: 4);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [TleRepositoryImpl] backed by a caller-supplied [MemoryCacheStore]
/// and [FakeClock] with a [MockClient] handler.
///
/// [handler] serves all non-TLE requests; [tleHandler] intercepts FORMAT=TLE
/// requests (falls back to [handler] when omitted).
///
/// [transportCalls] is incremented by the mock on every HTTP request so tests
/// can assert zero transport calls for cache-only paths.
TleRepositoryImpl _repo(
  MockClientHandler handler, {
  required FakeClock clock,
  required MemoryCacheStore store,
  MockClientHandler? tleHandler,
  int maxAttempts = 1,
  List<int>? transportCalls,
}) {
  return TleRepositoryImpl(
    dataSource: CelestrakDataSource(
      transport: HttpTransport(
        client: MockClient((req) async {
          transportCalls?.add(1);
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

  // ═══════════════════════════════════════════════════════════════════════════
  // US-4: allowStale:true offline → cached + isStale() true
  // ═══════════════════════════════════════════════════════════════════════════

  group('US-4 — allowStale:true offline returns cached+stale flag', () {
    // ── fetchCategory ─────────────────────────────────────────────────────

    test(
        'fetchCategory allowStale:true offline → source==local and '
        'isStale() true', () async {
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

      // Prime the cache with a fresh response.
      await repo.fetchCategory(SatelliteCategory.stations);
      // Advance well past TTL and staleThreshold.
      clock.advance(_staleDuration);
      fail = true;

      final results = await repo.fetchCategory(
        SatelliteCategory.stations,
        allowStale: true,
      );

      expect(results, isNotEmpty, reason: 'stale cache must return records');
      for (final r in results) {
        expect(
          r.source,
          equals(TleSource.local),
          reason: 'stale fallback must stamp source=local',
        );
        expect(
          r.isStale(now: clock.now),
          isTrue,
          reason:
              'records returned via stale fallback must report isStale=true',
        );
      }
    });

    // ── fetchByNoradId ────────────────────────────────────────────────────

    test(
        'fetchByNoradId allowStale:true offline → source==local and '
        'isStale() true', () async {
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
      clock.advance(_staleDuration);
      fail = true;

      final tle = await repo.fetchByNoradId(25544, allowStale: true);

      expect(tle.source, equals(TleSource.local));
      expect(
        tle.isStale(now: clock.now),
        isTrue,
        reason: 'stale record must report isStale=true',
      );
    });

    // ── fetchCategoryByGroup ──────────────────────────────────────────────

    test(
        'fetchCategoryByGroup allowStale:true offline → source==local and '
        'isStale() true', () async {
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

      final results =
          await repo.fetchCategoryByGroup('stations', allowStale: true);

      expect(results, isNotEmpty);
      for (final r in results) {
        expect(r.source, equals(TleSource.local));
        expect(r.isStale(now: clock.now), isTrue);
      }
    });

    // ── fetchByName ───────────────────────────────────────────────────────

    test(
        'fetchByName allowStale:true offline → source==local and '
        'isStale() true', () async {
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
        expect(r.isStale(now: clock.now), isTrue);
      }
    });

    // ── fetchByIntlDesignator ─────────────────────────────────────────────

    test(
        'fetchByIntlDesignator allowStale:true offline → source==local and '
        'isStale() true', () async {
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

      final results =
          await repo.fetchByIntlDesignator('1998-067A', allowStale: true);

      expect(results, isNotEmpty);
      for (final r in results) {
        expect(r.source, equals(TleSource.local));
        expect(r.isStale(now: clock.now), isTrue);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FR-18: allowStale:false + offline + no cache → NetworkException
  // ═══════════════════════════════════════════════════════════════════════════

  group('FR-18 — allowStale:false + offline + no cache → NetworkException', () {
    test(
        'fetchCategory allowStale:false + no cache + offline → '
        'NetworkException', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchCategory(
          SatelliteCategory.stations,
          allowStale: false,
        ),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
        'fetchByNoradId allowStale:false + no cache + offline → '
        'NetworkException', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchByNoradId(25544, allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
        'fetchCategoryByGroup allowStale:false + no cache + offline → '
        'NetworkException', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchCategoryByGroup('stations', allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });

    test('fetchByName allowStale:false + no cache + offline → NetworkException',
        () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchByName('ISS', allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
        'fetchByIntlDesignator allowStale:false + no cache + offline → '
        'NetworkException', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchByIntlDesignator('1998-067A', allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });

    // expired cache + allowStale:false → NetworkException (not stale fallback)
    test(
        'fetchCategory expired cache + allowStale:false + offline → '
        'NetworkException', () async {
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
        repo.fetchCategory(
          SatelliteCategory.stations,
          allowStale: false,
        ),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FR-19: forceCache:true + no entry → CacheMissException + zero transport
  // ═══════════════════════════════════════════════════════════════════════════

  group('FR-19 — forceCache:true, no entry → CacheMissException, zero network',
      () {
    // ── fetchCategory ─────────────────────────────────────────────────────

    test(
        'fetchCategory forceCache:true + no entry → CacheMissException, '
        'zero transport calls', () async {
      final calls = <int>[];
      final repo = _repo(
        (_) async => http.Response(_stationsOmmFixture, 200),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
        transportCalls: calls,
      );

      await expectLater(
        repo.fetchCategory(SatelliteCategory.stations, forceCache: true),
        throwsA(isA<CacheMissException>()),
      );
      expect(calls, isEmpty, reason: 'forceCache must not issue any HTTP call');
    });

    test('fetchCategory forceCache:true CacheMissException.key is non-empty',
        () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmFixture, 200),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      try {
        await repo.fetchCategory(SatelliteCategory.stations, forceCache: true);
        fail('expected CacheMissException');
      } on CacheMissException catch (e) {
        expect(e.key, isNotEmpty, reason: 'key must identify the cache slot');
        expect(e.message, isNotEmpty);
      }
    });

    test(
        'fetchCategory forceCache:true + cached entry → returns list, '
        'zero additional transport calls after prime', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final calls = <int>[];
      final repo = _repo(
        (_) async => http.Response(_stationsOmmFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
        transportCalls: calls,
      );

      // Prime the cache with one network round-trip.
      await repo.fetchCategory(SatelliteCategory.stations);
      final callsAfterPrime = calls.length;

      // forceCache must hit cache only — no additional transport calls.
      final results = await repo.fetchCategory(
        SatelliteCategory.stations,
        forceCache: true,
      );

      expect(results, isNotEmpty);
      expect(
        calls.length,
        equals(callsAfterPrime),
        reason: 'forceCache must not issue any HTTP call after prime',
      );
    });

    // ── fetchByNoradId ────────────────────────────────────────────────────

    test(
        'fetchByNoradId forceCache:true + no entry → CacheMissException, '
        'zero transport calls', () async {
      final calls = <int>[];
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
        transportCalls: calls,
      );

      await expectLater(
        repo.fetchByNoradId(25544, forceCache: true),
        throwsA(isA<CacheMissException>()),
      );
      expect(calls, isEmpty);
    });

    test(
        'fetchByNoradId forceCache:true + cached entry → returns record, '
        'zero additional transport calls after prime', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final calls = <int>[];
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
        transportCalls: calls,
      );

      await repo.fetchByNoradId(25544);
      final callsAfterPrime = calls.length;

      final tle = await repo.fetchByNoradId(25544, forceCache: true);

      expect(tle.noradId, equals(25544));
      expect(tle.source, equals(TleSource.local));
      expect(calls.length, equals(callsAfterPrime));
    });

    // ── fetchCategoryByGroup ──────────────────────────────────────────────

    test(
        'fetchCategoryByGroup forceCache:true + no entry → CacheMissException, '
        'zero transport calls', () async {
      final calls = <int>[];
      final repo = _repo(
        (_) async => http.Response(_stationsOmmFixture, 200),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
        transportCalls: calls,
      );

      await expectLater(
        repo.fetchCategoryByGroup('stations', forceCache: true),
        throwsA(isA<CacheMissException>()),
      );
      expect(calls, isEmpty);
    });

    test(
        'fetchCategoryByGroup forceCache:true + cached entry → returns list, '
        'zero additional transport calls after prime', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final calls = <int>[];
      final repo = _repo(
        (_) async => http.Response(_stationsOmmFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
        transportCalls: calls,
      );

      await repo.fetchCategoryByGroup('stations');
      final callsAfterPrime = calls.length;

      final results =
          await repo.fetchCategoryByGroup('stations', forceCache: true);

      expect(results, isNotEmpty);
      for (final r in results) {
        expect(
          r.source,
          equals(TleSource.local),
          reason: 'forceCache must stamp source=local',
        );
      }
      expect(calls.length, equals(callsAfterPrime));
    });

    // ── fetchByName ───────────────────────────────────────────────────────

    test(
        'fetchByName forceCache:true + no entry → CacheMissException, '
        'zero transport calls', () async {
      final calls = <int>[];
      final repo = _repo(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
        transportCalls: calls,
      );

      await expectLater(
        repo.fetchByName('ISS', forceCache: true),
        throwsA(isA<CacheMissException>()),
      );
      expect(calls, isEmpty);
    });

    test(
        'fetchByName forceCache:true + cached entry → returns list, '
        'zero additional transport calls after prime', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final calls = <int>[];
      final repo = _repo(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
        clock: clock,
        store: store,
        transportCalls: calls,
      );

      await repo.fetchByName('ISS');
      final callsAfterPrime = calls.length;

      final results = await repo.fetchByName('ISS', forceCache: true);

      expect(results, isNotEmpty);
      for (final r in results) {
        expect(
          r.source,
          equals(TleSource.local),
          reason: 'forceCache must stamp source=local',
        );
      }
      expect(calls.length, equals(callsAfterPrime));
    });

    // ── fetchByIntlDesignator ─────────────────────────────────────────────

    test(
        'fetchByIntlDesignator forceCache:true + no entry → '
        'CacheMissException, zero transport calls', () async {
      final calls = <int>[];
      final repo = _repo(
        (_) async => http.Response(_intdesOmmFixture, 200),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
        transportCalls: calls,
      );

      await expectLater(
        repo.fetchByIntlDesignator('1998-067A', forceCache: true),
        throwsA(isA<CacheMissException>()),
      );
      expect(calls, isEmpty);
    });

    test(
        'fetchByIntlDesignator forceCache:true + cached entry → returns list, '
        'zero additional transport calls after prime', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final calls = <int>[];
      final repo = _repo(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        clock: clock,
        store: store,
        transportCalls: calls,
      );

      await repo.fetchByIntlDesignator('1998-067A');
      final callsAfterPrime = calls.length;

      final results =
          await repo.fetchByIntlDesignator('1998-067A', forceCache: true);

      expect(results, isNotEmpty);
      for (final r in results) {
        expect(
          r.source,
          equals(TleSource.local),
          reason: 'forceCache must stamp source=local',
        );
      }
      expect(calls.length, equals(callsAfterPrime));
    });

    // malformed intlDesignator + forceCache — ArgumentError fires before cache
    test(
        'fetchByIntlDesignator forceCache:true + malformed designator → '
        'ArgumentError (not CacheMissException), zero transport calls',
        () async {
      final calls = <int>[];
      final repo = _repo(
        (_) async => http.Response(_intdesOmmFixture, 200),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
        transportCalls: calls,
      );

      await expectLater(
        repo.fetchByIntlDesignator('bad-format', forceCache: true),
        throwsA(isA<ArgumentError>()),
      );
      expect(calls, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // NFR-8: never crashes on network loss — always typed CelestrakException
  // ═══════════════════════════════════════════════════════════════════════════

  group('NFR-8 — never crashes on network loss', () {
    test('fetchCategory 503 response throws NetworkException, not raw error',
        () async {
      final repo = _repo(
        (_) async => http.Response('upstream error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchCategory(SatelliteCategory.stations),
        throwsA(
          isA<NetworkException>().having(
            (e) => e,
            'is CelestrakException',
            isA<CelestrakException>(),
          ),
        ),
        reason: 'network errors must be wrapped in CelestrakException',
      );
    });

    test('fetchByNoradId 503 response throws NetworkException, not raw error',
        () async {
      final repo = _repo(
        (_) async => http.Response('upstream error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchByNoradId(25544),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
        'fetchCategory allowStale:true + no cache + 503 → NetworkException '
        '(no crash)', () async {
      final repo = _repo(
        (_) async => http.Response('upstream error', 503),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      await expectLater(
        repo.fetchCategory(SatelliteCategory.stations, allowStale: true),
        throwsA(isA<NetworkException>()),
        reason: 'allowStale with no cache entry must re-throw NetworkException'
            ' not crash',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CacheMissException field assertions
  // ═══════════════════════════════════════════════════════════════════════════

  group('CacheMissException — field assertions', () {
    test('CacheMissException has non-empty message', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmFixture, 200),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      try {
        await repo.fetchCategory(SatelliteCategory.stations, forceCache: true);
        fail('expected CacheMissException');
      } on CacheMissException catch (e) {
        expect(e.message, isNotEmpty);
        expect(e.toString(), contains('CacheMissException'));
      }
    });

    test('CacheMissException.key reflects the cache slot queried', () async {
      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      try {
        await repo.fetchByNoradId(25544, forceCache: true);
        fail('expected CacheMissException');
      } on CacheMissException catch (e) {
        // The key must be a non-empty string; exact value is implementation
        // detail — assert only structure.
        expect(e.key, isNotEmpty);
      }
    });

    test('CacheMissException is a CelestrakException subtype', () async {
      final repo = _repo(
        (_) async => http.Response(_stationsOmmFixture, 200),
        clock: FakeClock(DateTime.utc(2026, 6, 1, 14)),
        store: MemoryCacheStore(),
      );

      try {
        await repo.fetchCategory(SatelliteCategory.stations, forceCache: true);
        fail('expected CacheMissException');
      } on Object catch (e) {
        expect(
          e,
          isA<CelestrakException>(),
          reason: 'CacheMissException must extend CelestrakException',
        );
        expect(e, isA<CacheMissException>());
      }
    });
  });
}
