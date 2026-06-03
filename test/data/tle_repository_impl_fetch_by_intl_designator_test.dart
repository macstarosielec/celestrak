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

late String _intdesOmmFixture;
late String _intdesTleFixture;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testBase = 'https://celestrak.test/gp.php';
const _defaultTtl = Duration(hours: 2);

/// Creates a [TleRepositoryImpl] wired to a [MockClient] and a fresh
/// [MemoryCacheStore] with an optional [FakeClock].
///
/// [intdesHandler] handles `INTDES=` requests.
/// [tleHandler] handles `FORMAT=TLE` requests (defaults to [intdesHandler]).
TleRepositoryImpl _repo(
  MockClientHandler intdesHandler, {
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
            return (tleHandler ?? intdesHandler)(req);
          }
          return intdesHandler(req);
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
    _intdesOmmFixture =
        await loadFixture('test/fixtures/intdes_1998_067a_omm.json');
    _intdesTleFixture = await loadFixture('test/fixtures/intdes_1998_067a.txt');
  });

  // ── Happy path ─────────────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchByIntlDesignator — happy path', () {
    test('returns non-empty list for a valid designator', () async {
      final repo = _repo(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
      );

      final results = await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      expect(results, isNotEmpty);
    });

    test('result contains ISS with noradId=25544 for INTDES=1998-067A',
        () async {
      final repo = _repo(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
      );

      final results = await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      final noradIds = results.map((r) => r.noradId).toList();

      expect(noradIds, contains(25544));
    });

    test('stamps source=celestrak on remote fetch', () async {
      final repo = _repo(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
      );

      final results = await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      for (final r in results) {
        expect(r.source, equals(TleSource.celestrak));
      }
    });

    test('passes designator verbatim in INTDES= query parameter', () async {
      String? capturedIntdes;
      final repo = _repo(
        (req) async {
          capturedIntdes = req.url.queryParameters['INTDES'];
          return http.Response(_intdesOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
      );

      await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      expect(capturedIntdes, equals('1998-067A'));
    });

    test('accepts designator without hyphen (1998067A)', () async {
      final repo = _repo(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
      );

      final results = await repo.fetchByIntlDesignator(
        '1998067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      expect(results, isNotEmpty);
    });
  });

  // ── No-match ───────────────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchByIntlDesignator — no match', () {
    test('returns empty list when server returns "No GP data found"', () async {
      final repo = _repo(
        (_) async => http.Response('No GP data found', 200),
      );

      final results = await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      expect(results, isEmpty);
    });

    test('no-match completes without throwing', () async {
      final repo = _repo(
        (_) async => http.Response('No GP data found', 200),
      );

      await expectLater(
        repo.fetchByIntlDesignator(
          '1998-067A',
          format: CelestrakFormat.omm,
          ttl: _defaultTtl,
        ),
        completes,
      );
    });
  });

  // ── Malformed designator → ArgumentError (FR-4) ───────────────────────────

  group(
      'TleRepositoryImpl.fetchByIntlDesignator — '
      'malformed designator (FR-4)', () {
    final malformed = [
      '',
      '   ',
      'ABCD-067A',
      '98-067A',
      '1998-A',
      '1998-0671',
      '1998-067ABCD',
      'not-a-designator',
    ];

    for (final bad in malformed) {
      test('throws ArgumentError for "$bad"', () async {
        final repo = _repo(
          (_) async => http.Response(_intdesOmmFixture, 200),
        );

        await expectLater(
          repo.fetchByIntlDesignator(
            bad,
            format: CelestrakFormat.omm,
            ttl: _defaultTtl,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    }

    test('ArgumentError.name is "intlDesignator"', () async {
      final repo = _repo(
        (_) async => http.Response(_intdesOmmFixture, 200),
      );

      await expectLater(
        repo.fetchByIntlDesignator(
          'bad',
          format: CelestrakFormat.omm,
          ttl: _defaultTtl,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            equals('intlDesignator'),
          ),
        ),
      );
    });

    test('throws ArgumentError for malformed input even with warm cache',
        () async {
      // Regression test for the deferred-validation bug: previously validation
      // was delegated to the data source, so a warm cache hit would bypass it
      // entirely and return cached data for a malformed designator.
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        clock: clock,
        store: store,
      );

      // Warm the cache with a valid designator.
      await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      // A structurally different malformed value must still throw even though
      // some cache entries now exist.
      await expectLater(
        repo.fetchByIntlDesignator(
          'bad',
          format: CelestrakFormat.omm,
          ttl: _defaultTtl,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── Cache behaviour (FR-12) ────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchByIntlDesignator — caching (FR-12)', () {
    test('second call within TTL does not issue transport call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async {
          calls++;
          return http.Response(_intdesOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(minutes: 30));
      await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      expect(calls, equals(1));
    });

    test('cache hit stamps source=local', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(minutes: 30));
      final results = await repo.fetchByIntlDesignator(
        '1998-067A',
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

      await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(minutes: 30));
      await repo.fetchByIntlDesignator(
        '1998-067A',
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
          return http.Response(_intdesOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(hours: 2, seconds: 1));
      await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );

      expect(calls, greaterThanOrEqualTo(2));
    });
  });

  // ── intlDesignatorAge ─────────────────────────────────────────────────────

  group('TleRepositoryImpl.intlDesignatorAge', () {
    test('returns null before any fetch', () async {
      final repo = _repo(
        (_) async => http.Response(_intdesOmmFixture, 200),
      );

      final age = await repo.intlDesignatorAge(
        '1998-067A',
        format: CelestrakFormat.omm,
      );

      expect(age, isNull);
    });

    test('returns Duration after fetch', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(minutes: 20));

      final age = await repo.intlDesignatorAge(
        '1998-067A',
        format: CelestrakFormat.omm,
      );

      expect(age, equals(const Duration(minutes: 20)));
    });

    test('returns null after clearCache', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final repo = _repo(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        clock: clock,
        store: store,
      );

      await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      await repo.clearCache();

      final age = await repo.intlDesignatorAge(
        '1998-067A',
        format: CelestrakFormat.omm,
      );

      expect(age, isNull);
    });
  });

  // ── allowStale (FR-17) ────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchByIntlDesignator — allowStale (FR-17)', () {
    test('allowStale:true returns stale cache when network fails', () async {
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
        maxAttempts: 1,
      );

      await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(hours: 3));
      fail = true;

      final results = await repo.fetchByIntlDesignator(
        '1998-067A',
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
          return http.Response(_intdesOmmFixture, 200);
        },
        tleHandler: (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_intdesTleFixture, 200);
        },
        clock: clock,
        store: store,
        maxAttempts: 1,
      );

      await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.omm,
        ttl: _defaultTtl,
      );
      clock.advance(const Duration(hours: 3));
      fail = true;

      await expectLater(
        repo.fetchByIntlDesignator(
          '1998-067A',
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

      await expectLater(
        repo.fetchByIntlDesignator(
          '1998-067A',
          format: CelestrakFormat.omm,
          ttl: _defaultTtl,
          allowStale: true,
        ),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // ── Error paths ────────────────────────────────────────────────────────────

  group('TleRepositoryImpl.fetchByIntlDesignator — error paths', () {
    test('NetworkException propagates on transport error', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      await expectLater(
        repo.fetchByIntlDesignator(
          '1998-067A',
          format: CelestrakFormat.omm,
          ttl: _defaultTtl,
        ),
        throwsA(isA<NetworkException>()),
      );
    });

    test('NetworkException.statusCode is set on HTTP error response', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      try {
        await repo.fetchByIntlDesignator(
          '1998-067A',
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

  group('TleRepositoryImpl.fetchByIntlDesignator — TLE format', () {
    test('returns list when format:tle', () async {
      final repo = _repo(
        (_) async => http.Response(_intdesTleFixture, 200),
      );

      final results = await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.tle,
        ttl: _defaultTtl,
      );

      expect(results, isNotEmpty);
    });

    test('returns empty list when no match in TLE format', () async {
      final repo = _repo(
        (_) async => http.Response('No GP data found', 200),
      );

      final results = await repo.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.tle,
        ttl: _defaultTtl,
      );

      expect(results, isEmpty);
    });
  });
}
