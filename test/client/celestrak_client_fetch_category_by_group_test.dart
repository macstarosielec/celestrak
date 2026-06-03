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

late String _stationsOmmGroupFixture;
late String _stationsTleFixture;

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
    _stationsOmmGroupFixture =
        await loadFixture('test/fixtures/stations_group_omm.json');
    _stationsTleFixture = await loadFixture('test/fixtures/stations_group.txt');
  });

  // ── Happy path ─────────────────────────────────────────────────────────────

  group('CelestrakClient.fetchCategoryByGroup — happy path', () {
    test('returns non-empty list for stations group string', () async {
      final client = _client(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await client.fetchCategoryByGroup('stations');

      expect(results, isNotEmpty);
    });

    test('stations group includes ISS (noradId=25544)', () async {
      final client = _client(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await client.fetchCategoryByGroup('stations');
      final noradIds = results.map((r) => r.noradId).toList();

      expect(noradIds, contains(25544));
    });

    test('stamps source=celestrak on remote fetch', () async {
      final client = _client(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      final results = await client.fetchCategoryByGroup('stations');

      for (final r in results) {
        expect(r.source, equals(TleSource.celestrak));
      }
    });

    test('passes group string verbatim in GROUP= parameter', () async {
      String? capturedGroup;
      final client = _client(
        (req) async {
          capturedGroup = req.url.queryParameters['GROUP'];
          return http.Response(_stationsOmmGroupFixture, 200);
        },
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      await client.fetchCategoryByGroup('some-custom-group');

      expect(capturedGroup, equals('some-custom-group'));
    });
  });

  // ── Per-group cache key (FR-12) ────────────────────────────────────────────

  group('CelestrakClient.fetchCategoryByGroup — per-group cache (FR-12)', () {
    test('second call within TTL does not issue transport call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async {
          calls++;
          return http.Response(_stationsOmmGroupFixture, 200);
        },
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchCategoryByGroup('stations');
      clock.advance(const Duration(minutes: 30));
      await client.fetchCategoryByGroup('stations');

      expect(calls, equals(1));
    });

    test('cache hit stamps source=local', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchCategoryByGroup('stations');
      clock.advance(const Duration(minutes: 30));
      final results = await client.fetchCategoryByGroup('stations');

      for (final r in results) {
        expect(r.source, equals(TleSource.local));
      }
    });

    test('different group strings are cached independently', () async {
      var stationsCalls = 0;
      var customCalls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (req) async {
          final group = req.url.queryParameters['GROUP'];
          if (group == 'stations') {
            stationsCalls++;
          } else {
            customCalls++;
          }
          return http.Response(_stationsOmmGroupFixture, 200);
        },
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchCategoryByGroup('stations');
      await client.fetchCategoryByGroup('custom-group');

      expect(stationsCalls, equals(1));
      expect(customCalls, equals(1));

      // Within TTL — neither issues a new call.
      clock.advance(const Duration(minutes: 30));
      await client.fetchCategoryByGroup('stations');
      await client.fetchCategoryByGroup('custom-group');

      expect(stationsCalls, equals(1));
      expect(customCalls, equals(1));
    });

    test('cache miss after TTL expiry issues new transport call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async {
          calls++;
          return http.Response(_stationsOmmGroupFixture, 200);
        },
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
        defaultTtl: const Duration(hours: 2),
      );

      await client.fetchCategoryByGroup('stations');
      clock.advance(const Duration(hours: 2, seconds: 1));
      await client.fetchCategoryByGroup('stations');

      expect(calls, greaterThanOrEqualTo(2));
    });
  });

  // ── groupAge ──────────────────────────────────────────────────────────────

  group('CelestrakClient.groupAge', () {
    test('returns null before any fetch', () async {
      final client = _client(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
      );

      final age = await client.groupAge('stations');

      expect(age, isNull);
    });

    test('returns Duration after fetch', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchCategoryByGroup('stations');
      clock.advance(const Duration(minutes: 20));

      final age = await client.groupAge('stations');

      expect(age, equals(const Duration(minutes: 20)));
    });

    test('returns null after clearCache', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchCategoryByGroup('stations');
      await client.clearCache();

      final age = await client.groupAge('stations');

      expect(age, isNull);
    });
  });

  // ── allowStale (FR-17) ────────────────────────────────────────────────────

  group('CelestrakClient.fetchCategoryByGroup — allowStale (FR-17)', () {
    test('allowStale:true returns stale cache when network fails', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final client = _client(
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
        maxRetries: 1,
      );

      await client.fetchCategoryByGroup('stations');
      clock.advance(const Duration(hours: 3));
      fail = true;

      final results = await client.fetchCategoryByGroup(
        'stations',
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
      final client = _client(
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
        maxRetries: 1,
      );

      await client.fetchCategoryByGroup('stations');
      clock.advance(const Duration(hours: 3));
      fail = true;

      await expectLater(
        client.fetchCategoryByGroup('stations', allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // ── Error paths ────────────────────────────────────────────────────────────

  group('CelestrakClient.fetchCategoryByGroup — error paths', () {
    test('throws ArgumentError for empty group string', () async {
      final client = _client(
        (_) async => http.Response(_stationsOmmGroupFixture, 200),
      );

      await expectLater(
        client.fetchCategoryByGroup(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('NetworkException propagates on transport error', () async {
      final client = _client(
        (_) async => http.Response('server error', 503),
        maxRetries: 1,
      );

      await expectLater(
        client.fetchCategoryByGroup('stations'),
        throwsA(isA<NetworkException>()),
      );
    });

    test('NetworkException.statusCode is set on HTTP error response', () async {
      final client = _client(
        (_) async => http.Response('server error', 503),
        maxRetries: 1,
      );

      try {
        await client.fetchCategoryByGroup('stations');
        fail('expected NetworkException');
      } on NetworkException catch (e) {
        expect(e.statusCode, equals(503));
      }
    });

    test('unknown group raises SatelliteNotFoundException', () async {
      final client = _client(
        (_) async => http.Response('No GP data found', 200),
        maxRetries: 1,
      );

      await expectLater(
        client.fetchCategoryByGroup('unknown-group'),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });
  });

  // ── TLE format ────────────────────────────────────────────────────────────

  group('CelestrakClient.fetchCategoryByGroup — TLE format', () {
    test('returns list when format:tle', () async {
      final client = _client(
        (_) async => http.Response(_stationsTleFixture, 200),
        defaultFormat: CelestrakFormat.tle,
      );

      final results = await client.fetchCategoryByGroup('stations');

      expect(results, isNotEmpty);
    });

    test('format override respected per call', () async {
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_stationsTleFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        store: store,
        defaultFormat: CelestrakFormat.omm,
      );

      final results = await client.fetchCategoryByGroup(
        'stations',
        format: CelestrakFormat.tle,
      );

      for (final r in results) {
        expect(r.omm, isNull);
      }
    });
  });
}
