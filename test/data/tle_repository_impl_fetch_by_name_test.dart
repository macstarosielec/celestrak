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

late String _nameIssOmmFixture;
late String _nameIssTleFixture;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testBase = 'https://celestrak.test/gp.php';
const _defaultTtl = Duration(hours: 2);

/// Creates a [TleRepositoryImpl] wired to a [MockClient] and a fresh
/// [MemoryCacheStore] with an optional [FakeClock].
///
/// [nameHandler] handles `NAME=` requests.
/// [tleHandler] handles `FORMAT=TLE` requests (defaults to [nameHandler]).
TleRepositoryImpl _repo(
  MockClientHandler nameHandler, {
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
            return (tleHandler ?? nameHandler)(req);
          }
          return nameHandler(req);
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
    _nameIssOmmFixture = await loadFixture('test/fixtures/name_iss_omm.json');
    _nameIssTleFixture = await loadFixture('test/fixtures/name_iss.txt');
  });

  // ── Happy path ─────────────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchByName — happy path', () {
    test('returns non-empty list for a matching name', () async {
      final repo = _repo(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
      );

      final results = await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      expect(results, isNotEmpty);
    });

    test('result contains satellite with noradId=25544 for NAME=ISS', () async {
      final repo = _repo(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
      );

      final results = await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      final noradIds = results.map((r) => r.noradId).toList();

      expect(noradIds, contains(25544));
    });

    test('stamps source=celestrak on remote fetch', () async {
      final repo = _repo(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
      );

      final results = await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      for (final r in results) {
        expect(r.source, equals(TleSource.celestrak));
      }
    });

    test('passes name verbatim in NAME= query parameter', () async {
      String? capturedName;
      final repo = _repo(
        (req) async {
          capturedName = req.url.queryParameters['NAME'];
          return http.Response(_nameIssOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
      );

      await repo.fetchByName(
        'My Satellite',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      expect(capturedName, equals('My Satellite'));
    });
  });

  // ── No-match (FR-3, US-5) ──────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchByName — no match returns empty list', () {
    test('returns empty list when server returns "No GP data found"', () async {
      final repo = _repo(
        (_) async => http.Response('No GP data found', 200),
      );

      final results = await repo.fetchByName(
        'NONEXISTENT',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      expect(results, isEmpty);
    });

    test('no-match result is an empty list, not an exception', () async {
      final repo = _repo(
        (_) async => http.Response('No GP data found', 200),
      );

      await expectLater(
        repo.fetchByName(
          'NONEXISTENT',
          format: CelestrakFormat.omm,
          ttl: _defaultTtl,
        ),
        completes,
      );
    });
  });

  // ── Cache behaviour (FR-12) ────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchByName — caching (FR-12)', () {
    test('second call within TTL does not issue transport call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          calls++;
          return http.Response(_nameIssOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(minutes: 30));
      await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      expect(calls, equals(1));
    });

    test('cache hit stamps source=local', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(minutes: 30));
      final results = await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      for (final r in results) {
        expect(r.source, equals(TleSource.local));
      }
    });

    test('no-match result is cached — second call within TTL skips transport',
        () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          calls++;
          return http.Response('No GP data found', 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchByName(
        'GHOST',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(minutes: 30));
      await repo.fetchByName(
        'GHOST',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      expect(calls, equals(1));
    });

    test('cache miss after TTL expiry issues new transport call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          calls++;
          return http.Response(_nameIssOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(hours: 2, seconds: 1));
      await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      expect(calls, greaterThanOrEqualTo(2));
    });
  });

  // ── nameAge ───────────────────────────────────────────────────────────────

  group('TleRepositoryImpl.nameAge', () {
    test('returns null before any fetch', () async {
      final repo = _repo(
        (_) async => http.Response(_nameIssOmmFixture, 200),
      );

      final age = await repo.nameAge('ISS', format: CelestrakFormat.omm);

      expect(age, isNull);
    });

    test('returns Duration after fetch', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(minutes: 20));

      final age = await repo.nameAge('ISS', format: CelestrakFormat.omm);

      expect(age, equals(const Duration(minutes: 20)));
    });

    test('returns null after clearCache', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      await repo.clearCache();

      final age = await repo.nameAge('ISS', format: CelestrakFormat.omm);

      expect(age, isNull);
    });
  });

  // ── allowStale (FR-17) ────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchByName — allowStale (FR-17)', () {
    test('allowStale:true returns stale cache when network fails', () async {
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
        maxAttempts: 1,
      );

      await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(hours: 3));
      fail = true;

      final results = await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
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
          return http.Response(_nameIssOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_nameIssTleFixture, 200);
        },
        clock: clock,
        store: store,
        maxAttempts: 1,
      );

      await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(hours: 3));
      fail = true;

      await expectLater(
        repo.fetchByName(
          'ISS',
          format: CelestrakFormat.omm,
          ttl: _defaultTtl,
          allowStale: false,
        ),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
        'allowStale:true with no prior cache entry re-throws original '
        'NetworkException', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      // No prior fetch — cacheAge is null; stale fallback cannot apply.
      await expectLater(
        repo.fetchByName(
          'ISS',
          format: CelestrakFormat.omm,
          ttl: _defaultTtl,
          allowStale: true,
        ),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // ── Error paths ────────────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchByName — error paths', () {
    test('throws ArgumentError for empty name string', () async {
      final repo = _repo(
        (_) async => http.Response(_nameIssOmmFixture, 200),
      );

      await expectLater(
        repo.fetchByName('', format: CelestrakFormat.omm, ttl: _defaultTtl),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for whitespace-only name string', () async {
      final repo = _repo(
        (_) async => http.Response(_nameIssOmmFixture, 200),
      );

      await expectLater(
        repo.fetchByName(
          '   ',
          format: CelestrakFormat.omm,
          ttl: _defaultTtl,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('NetworkException propagates on transport error', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      await expectLater(
        repo.fetchByName('ISS', format: CelestrakFormat.omm, ttl: _defaultTtl),
        throwsA(isA<NetworkException>()),
      );
    });

    test('NetworkException.statusCode is set on HTTP error response', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      try {
        await repo.fetchByName(
          'ISS',
          format: CelestrakFormat.omm,
          ttl: _defaultTtl,
        );
        fail('expected NetworkException');
      } on NetworkException catch (e) {
        expect(e.statusCode, equals(503));
      }
    });
  });

  // ── TLE format ────────────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchByName — TLE format', () {
    test('returns list when format:tle', () async {
      final repo = _repo(
        (_) async => http.Response(_nameIssTleFixture, 200),
      );

      final results = await repo.fetchByName(
        'ISS',
        format: CelestrakFormat.tle,
        ttl: _defaultTtl,
      );

      expect(results, isNotEmpty);
    });

    test('returns empty list when no match in TLE format', () async {
      final repo = _repo(
        (_) async => http.Response('No GP data found', 200),
      );

      final results = await repo.fetchByName(
        'NONEXISTENT',
        format: CelestrakFormat.tle,
        ttl: _defaultTtl,
      );

      expect(results, isEmpty);
    });

    test(
        'no-match TLE response is cached — second call within TTL skips '
        'transport', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          calls++;
          return http.Response('No GP data found', 200);
        },
        clock: clock,
        store: store,
      );

      await repo.fetchByName(
        'GHOST',
        format: CelestrakFormat.tle,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(minutes: 30));
      await repo.fetchByName(
        'GHOST',
        format: CelestrakFormat.tle,
        ttl: _defaultTtl,
      );

      expect(calls, equals(1));
    });
  });
}
