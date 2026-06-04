import 'package:celestrak/celestrak.dart';
import 'package:celestrak/src/data/local/memory_cache_store.dart';
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
late String _starlinkMultiOmmFixture;
late String _starlinkMultiTleFixture;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [CelestrakClient] via [CelestrakClient.withStore] backed by a
/// [MemoryCacheStore] and [MockClient].
///
/// [ommHandler] handles `FORMAT=JSON` (OMM) and any other non-TLE requests.
/// [tleHandler] handles `FORMAT=TLE` requests (defaults to [ommHandler]).
CelestrakClient _client(
  MockClientHandler ommHandler, {
  MockClientHandler? tleHandler,
  FakeClock? clock,
  MemoryCacheStore? store,
  int maxRetries = 1,
  Duration defaultTtl = const Duration(hours: 2),
  CelestrakFormat defaultFormat = CelestrakFormat.omm,
}) {
  final effectiveClock = clock ?? FakeClock(DateTime.utc(2026, 6, 1, 14));
  final effectiveStore = store ?? MemoryCacheStore();

  final mockClient = MockClient((req) async {
    final format = req.url.queryParameters['FORMAT'];
    if (format == 'TLE') {
      return (tleHandler ?? ommHandler)(req);
    }
    return ommHandler(req);
  });

  return CelestrakClient.withStore(
    httpClient: mockClient,
    cacheStore: effectiveStore,
    defaultTtl: defaultTtl,
    defaultFormat: defaultFormat,
    clock: effectiveClock,
    maxRetries: maxRetries,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    _nameIssOmmFixture = await loadFixture('test/fixtures/name_iss_omm.json');
    _nameIssTleFixture = await loadFixture('test/fixtures/name_iss.txt');
    _starlinkMultiOmmFixture =
        await loadFixture('test/fixtures/starlink_multi_omm.json');
    _starlinkMultiTleFixture =
        await loadFixture('test/fixtures/starlink_multi.txt');
  });

  // ── Happy path ─────────────────────────────────────────────────────────────

  group('CelestrakClient.fetchByName — happy path', () {
    test('returns non-empty list for a matching name', () async {
      final client = _client(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
      );

      final results = await client.fetchByName('ISS');

      expect(results, isNotEmpty);
    });

    test('result contains ISS (noradId=25544)', () async {
      final client = _client(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
      );

      final results = await client.fetchByName('ISS');
      final noradIds = results.map((r) => r.noradId).toList();

      expect(noradIds, contains(25544));
    });

    test('stamps source=celestrak on remote fetch', () async {
      final client = _client(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
      );

      final results = await client.fetchByName('ISS');

      for (final r in results) {
        expect(r.source, equals(TleSource.celestrak));
      }
    });

    test('passes name verbatim in NAME= query parameter', () async {
      String? capturedName;
      final client = _client(
        (req) async {
          capturedName = req.url.queryParameters['NAME'];
          return http.Response(_nameIssOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
      );

      await client.fetchByName('My Satellite');

      expect(capturedName, equals('My Satellite'));
    });
  });

  // ── No-match → empty list (FR-3, US-5) ────────────────────────────────────

  group('CelestrakClient.fetchByName — no match (FR-3, US-5)', () {
    test('returns empty list when no satellite matches', () async {
      final client = _client(
        (_) async => http.Response('No GP data found', 200),
      );

      final results = await client.fetchByName('NONEXISTENT');

      expect(results, isEmpty);
    });

    test('no match does not throw — returns [] instead', () async {
      final client = _client(
        (_) async => http.Response('No GP data found', 200),
      );

      await expectLater(
        client.fetchByName('GHOST'),
        completes,
      );
    });
  });

  // ── Cache behaviour (FR-12) ────────────────────────────────────────────────

  group('CelestrakClient.fetchByName — caching (FR-12)', () {
    test('second call within TTL does not issue transport call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async {
          calls++;
          return http.Response(_nameIssOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByName('ISS');
      clock.advance(const Duration(minutes: 30));
      await client.fetchByName('ISS');

      expect(calls, equals(1));
    });

    test('cache hit stamps source=local', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByName('ISS');
      clock.advance(const Duration(minutes: 30));
      final results = await client.fetchByName('ISS');

      for (final r in results) {
        expect(r.source, equals(TleSource.local));
      }
    });

    test('no-match result is cached — second call within TTL skips transport',
        () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async {
          calls++;
          return http.Response('No GP data found', 200);
        },
        clock: clock,
        store: store,
      );

      await client.fetchByName('GHOST');
      clock.advance(const Duration(minutes: 30));
      await client.fetchByName('GHOST');

      expect(calls, equals(1));
    });

    test('different name strings are cached independently', () async {
      var issCalls = 0;
      var hubbleCalls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (req) async {
          final name = req.url.queryParameters['NAME'];
          if (name == 'ISS') {
            issCalls++;
          } else {
            hubbleCalls++;
          }
          return http.Response(_nameIssOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByName('ISS');
      await client.fetchByName('HUBBLE');

      expect(issCalls, equals(1));
      expect(hubbleCalls, equals(1));

      // Within TTL — neither issues a new call.
      clock.advance(const Duration(minutes: 30));
      await client.fetchByName('ISS');
      await client.fetchByName('HUBBLE');

      expect(issCalls, equals(1));
      expect(hubbleCalls, equals(1));
    });

    test('cache miss after TTL expiry issues new transport call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async {
          calls++;
          return http.Response(_nameIssOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
        clock: clock,
        store: store,
        defaultTtl: const Duration(hours: 2),
      );

      await client.fetchByName('ISS');
      clock.advance(const Duration(hours: 2, seconds: 1));
      await client.fetchByName('ISS');

      expect(calls, greaterThanOrEqualTo(2));
    });
  });

  // ── nameAge ───────────────────────────────────────────────────────────────

  group('CelestrakClient.nameAge', () {
    test('returns null before any fetch', () async {
      final client = _client(
        (_) async => http.Response(_nameIssOmmFixture, 200),
      );

      final age = await client.nameAge('ISS');

      expect(age, isNull);
    });

    test('returns Duration after fetch', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByName('ISS');
      clock.advance(const Duration(minutes: 20));

      final age = await client.nameAge('ISS');

      expect(age, equals(const Duration(minutes: 20)));
    });

    test('returns null after clearCache', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_nameIssOmmFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByName('ISS');
      await client.clearCache();

      final age = await client.nameAge('ISS');

      expect(age, isNull);
    });
  });

  // ── allowStale (FR-17) ────────────────────────────────────────────────────

  group('CelestrakClient.fetchByName — allowStale (FR-17)', () {
    test('allowStale:true returns stale cache when network fails', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final client = _client(
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
        maxRetries: 1,
      );

      await client.fetchByName('ISS');
      clock.advance(const Duration(hours: 3));
      fail = true;

      final results = await client.fetchByName('ISS', allowStale: true);

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
      final client = _client(
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
        maxRetries: 1,
      );

      await client.fetchByName('ISS');
      clock.advance(const Duration(hours: 3));
      fail = true;

      await expectLater(
        client.fetchByName('ISS', allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
        'allowStale:true with no prior cache entry re-throws original '
        'NetworkException', () async {
      final client = _client(
        (_) async => http.Response('server error', 503),
        maxRetries: 1,
      );

      // No prior fetch — cacheAge is null; stale fallback cannot apply.
      await expectLater(
        client.fetchByName('ISS', allowStale: true),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // ── Error paths ────────────────────────────────────────────────────────────

  group('CelestrakClient.fetchByName — error paths', () {
    test('throws ArgumentError for empty name string', () async {
      final client = _client(
        (_) async => http.Response(_nameIssOmmFixture, 200),
      );

      await expectLater(
        client.fetchByName(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for whitespace-only name string', () async {
      final client = _client(
        (_) async => http.Response(_nameIssOmmFixture, 200),
      );

      await expectLater(
        client.fetchByName('   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('NetworkException propagates on transport error', () async {
      final client = _client(
        (_) async => http.Response('server error', 503),
        maxRetries: 1,
      );

      await expectLater(
        client.fetchByName('ISS'),
        throwsA(isA<NetworkException>()),
      );
    });

    test('NetworkException.statusCode is set on HTTP error response', () async {
      final client = _client(
        (_) async => http.Response('server error', 503),
        maxRetries: 1,
      );

      try {
        await client.fetchByName('ISS');
        fail('expected NetworkException');
      } on NetworkException catch (e) {
        expect(e.statusCode, equals(503));
      }
    });
  });

  // ── TLE format ────────────────────────────────────────────────────────────

  group('CelestrakClient.fetchByName — TLE format', () {
    test('returns list when format:tle', () async {
      final client = _client(
        (_) async => http.Response(_nameIssTleFixture, 200),
        defaultFormat: CelestrakFormat.tle,
      );

      final results = await client.fetchByName('ISS');

      expect(results, isNotEmpty);
    });

    test('format override respected per call', () async {
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_nameIssTleFixture, 200),
        tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
        store: store,
        defaultFormat: CelestrakFormat.omm,
      );

      final results = await client.fetchByName(
        'ISS',
        format: CelestrakFormat.tle,
      );

      for (final r in results) {
        expect(r.omm, isNull);
      }
    });
  });

  // ── Multi-result fetchByName (P4 / RK-4) ─────────────────────────────────

  group('CelestrakClient.fetchByName — multi-result (P4 RK-4)', () {
    test('fetchByName returns multiple records when server returns >1 match',
        () async {
      final client = _client(
        (_) async => http.Response(_starlinkMultiOmmFixture, 200),
        tleHandler: (_) async => http.Response(_starlinkMultiTleFixture, 200),
      );

      final results = await client.fetchByName('STARLINK');

      expect(results.length, greaterThan(1));
    });

    test('all records in multi-result carry expected noradIds', () async {
      final client = _client(
        (_) async => http.Response(_starlinkMultiOmmFixture, 200),
        tleHandler: (_) async => http.Response(_starlinkMultiTleFixture, 200),
      );

      final results = await client.fetchByName('STARLINK');
      final noradIds = results.map((r) => r.noradId).toList();

      expect(noradIds, unorderedEquals([44713, 44714, 44715]));
    });

    test('multi-result cached — second call within TTL skips transport',
        () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async {
          calls++;
          return http.Response(_starlinkMultiOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_starlinkMultiTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByName('STARLINK');
      clock.advance(const Duration(minutes: 30));
      final cached = await client.fetchByName('STARLINK');

      expect(calls, equals(1));
      expect(cached.length, greaterThan(1));
    });

    test('multi-result cache hit stamps source=local', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_starlinkMultiOmmFixture, 200),
        tleHandler: (_) async => http.Response(_starlinkMultiTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByName('STARLINK');
      clock.advance(const Duration(minutes: 30));
      final cached = await client.fetchByName('STARLINK');

      for (final r in cached) {
        expect(r.source, equals(TleSource.local));
      }
    });

    test('multi-result TLE format returns records with null omm', () async {
      final client = _client(
        (_) async => http.Response(_starlinkMultiTleFixture, 200),
        defaultFormat: CelestrakFormat.tle,
      );

      final results = await client.fetchByName('STARLINK');

      expect(results.length, greaterThan(1));
      for (final r in results) {
        expect(r.omm, isNull);
      }
    });
  });
}
