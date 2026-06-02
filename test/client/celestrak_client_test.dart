import 'dart:io' show File;

import 'package:celestrak/celestrak.dart';
import 'package:celestrak/src/data/local/memory_cache_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';
import '../support/temp_cache.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

late String _issOmmFixture;
late String _issTleFixture;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [CelestrakClient] via [CelestrakClient.withStore] backed by a
/// [MemoryCacheStore] and [MockClient].
///
/// [ommHandler] handles `FORMAT=JSON` requests.
/// [tleHandler] handles `FORMAT=TLE` requests (defaults to [ommHandler]).
CelestrakClient _client(
  MockClientHandler ommHandler, {
  MockClientHandler? tleHandler,
  FakeClock? clock,
  MemoryCacheStore? store,
  int maxRetries = 1,
  Duration defaultTtl = const Duration(hours: 2),
  CelestrakFormat defaultFormat = CelestrakFormat.omm,
  Duration staleThreshold = const Duration(days: 3),
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

  // Redirect to test base URL via a custom data source.  We compose the
  // internal graph manually here to keep the test isolated from real network.
  return CelestrakClient.withStore(
    httpClient: mockClient,
    cacheStore: effectiveStore,
    defaultTtl: defaultTtl,
    defaultFormat: defaultFormat,
    staleThreshold: staleThreshold,
    clock: effectiveClock,
    maxRetries: maxRetries,
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

  // ── withStore constructor ─────────────────────────────────────────────────

  group('CelestrakClient.withStore — happy path', () {
    test('fetchByNoradId returns SatelliteTle with correct noradId', () async {
      final client = _client(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
      );

      final tle = await client.fetchByNoradId(25544);

      expect(tle.noradId, equals(25544));
    });

    test('fetchByNoradId stamps source=celestrak on remote fetch', () async {
      final client = _client(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
      );

      final tle = await client.fetchByNoradId(25544);

      expect(tle.source, equals(TleSource.celestrak));
    });

    test('fetchByNoradId returns satellite name', () async {
      final client = _client(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
      );

      final tle = await client.fetchByNoradId(25544);

      expect(tle.name, equals('ISS (ZARYA)'));
    });

    test('fetchByNoradId populates TLE lines', () async {
      final client = _client(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
      );

      final tle = await client.fetchByNoradId(25544);

      expect(tle.line1, isNotEmpty);
      expect(tle.line2, isNotEmpty);
    });
  });

  // ── default properties ────────────────────────────────────────────────────

  group('CelestrakClient — default properties', () {
    test('defaultTtl is 2 hours by default', () {
      final client = _client((_) async => http.Response('', 200));

      expect(client.defaultTtl, equals(const Duration(hours: 2)));
    });

    test('defaultFormat is omm by default', () {
      final client = _client((_) async => http.Response('', 200));

      expect(client.defaultFormat, equals(CelestrakFormat.omm));
    });

    test('staleThreshold is 3 days by default', () {
      final client = _client((_) async => http.Response('', 200));

      expect(client.staleThreshold, equals(const Duration(days: 3)));
    });

    test('custom defaultTtl is preserved', () {
      final client = _client(
        (_) async => http.Response('', 200),
        defaultTtl: const Duration(minutes: 30),
      );

      expect(client.defaultTtl, equals(const Duration(minutes: 30)));
    });

    test('custom staleThreshold is preserved', () {
      final client = _client(
        (_) async => http.Response('', 200),
        staleThreshold: const Duration(hours: 12),
      );

      expect(client.staleThreshold, equals(const Duration(hours: 12)));
    });
  });

  // ── cache behaviour (FR-12) ───────────────────────────────────────────────

  group('CelestrakClient — cache (FR-12)', () {
    test('second call within TTL does not issue transport call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async {
          calls++;
          return http.Response(_issOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByNoradId(25544);
      clock.advance(const Duration(minutes: 30));
      await client.fetchByNoradId(25544);

      expect(calls, equals(1));
    });

    test('second call within TTL stamps source=local', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByNoradId(25544);
      clock.advance(const Duration(minutes: 30));
      final tle = await client.fetchByNoradId(25544);

      expect(tle.source, equals(TleSource.local));
    });
  });

  // ── cacheAge ──────────────────────────────────────────────────────────────

  group('CelestrakClient — cacheAge', () {
    test('cacheAge returns null before any fetch', () async {
      final client = _client((_) async => http.Response('', 200));

      final age = await client.cacheAge(25544);

      expect(age, isNull);
    });

    test('cacheAge returns Duration after fetch', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByNoradId(25544);
      clock.advance(const Duration(minutes: 10));

      final age = await client.cacheAge(25544);

      expect(age, equals(const Duration(minutes: 10)));
    });

    test('cacheAge returns null after clearCache', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByNoradId(25544);
      await client.clearCache();

      final age = await client.cacheAge(25544);

      expect(age, isNull);
    });
  });

  // ── clearCache ────────────────────────────────────────────────────────────

  group('CelestrakClient — clearCache', () {
    test('clearCache forces remote fetch on next call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async {
          calls++;
          return http.Response(_issOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByNoradId(25544);
      await client.clearCache();
      await client.fetchByNoradId(25544);

      expect(calls, equals(2));
    });
  });

  // ── isStale ───────────────────────────────────────────────────────────────

  group('CelestrakClient — isStale', () {
    test('isStale returns false for recently fetched ISS TLE', () async {
      // ISS epoch is 2026-06-01T13:00; fake clock is 14:00 same day — 1 hour
      // old, well within the 3-day default threshold.
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      final tle = await client.fetchByNoradId(25544);

      expect(client.isStale(tle), isFalse);
    });

    test('isStale returns true when epoch is older than staleThreshold',
        () async {
      // The clock is 4 days after the ISS epoch, exceeding the 3-day default.
      final clock = FakeClock(DateTime.utc(2026, 6, 5, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
        staleThreshold: const Duration(days: 3),
      );

      final tle = await client.fetchByNoradId(25544);

      expect(client.isStale(tle), isTrue);
    });

    test('isStale respects custom staleThreshold', () async {
      // Clock is 2 hours ahead; with a 1-hour threshold the data is stale.
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 15));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
        staleThreshold: const Duration(hours: 1),
      );

      final tle = await client.fetchByNoradId(25544);

      expect(client.isStale(tle), isTrue);
    });
  });

  // ── error paths ───────────────────────────────────────────────────────────

  group('CelestrakClient — error paths', () {
    test('SatelliteNotFoundException propagates when object not found',
        () async {
      final client =
          _client((_) async => http.Response('No GP data found', 200));

      await expectLater(
        client.fetchByNoradId(99999),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });

    test('SatelliteNotFoundException.noradId matches the requested id',
        () async {
      final client =
          _client((_) async => http.Response('No GP data found', 200));

      try {
        await client.fetchByNoradId(99999);
        fail('expected SatelliteNotFoundException');
      } on SatelliteNotFoundException catch (e) {
        expect(e.noradId, equals(99999));
      }
    });

    test('NetworkException propagates on transport error', () async {
      final client = _client(
        (_) async => http.Response('server error', 503),
        maxRetries: 1,
      );

      await expectLater(
        client.fetchByNoradId(25544),
        throwsA(isA<NetworkException>()),
      );
    });

    test('NetworkException.statusCode is set on HTTP error response', () async {
      final client = _client(
        (_) async => http.Response('server error', 503),
        maxRetries: 1,
      );

      try {
        await client.fetchByNoradId(25544);
        fail('expected NetworkException');
      } on NetworkException catch (e) {
        expect(e.statusCode, equals(503));
      }
    });

    test('ArgumentError on noradId < 1', () async {
      final client = _client((_) async => http.Response(_issOmmFixture, 200));

      await expectLater(
        client.fetchByNoradId(0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── allowStale (FR-17) ────────────────────────────────────────────────────

  group('CelestrakClient — allowStale (FR-17)', () {
    test('allowStale:true returns stale cache when network fails', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final client = _client(
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
        maxRetries: 1,
      );

      await client.fetchByNoradId(25544);
      clock.advance(const Duration(hours: 3));
      fail = true;

      final tle = await client.fetchByNoradId(25544, allowStale: true);

      expect(tle.source, equals(TleSource.local));
      expect(tle.noradId, equals(25544));
    });

    test('allowStale:false re-throws NetworkException when cache stale',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final client = _client(
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
        maxRetries: 1,
      );

      await client.fetchByNoradId(25544);
      clock.advance(const Duration(hours: 3));
      fail = true;

      await expectLater(
        client.fetchByNoradId(25544, allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // ── dispose (US-12) ───────────────────────────────────────────────────────

  group('CelestrakClient — dispose (US-12)', () {
    test('dispose with ownsClient=false does not close the external client',
        () async {
      var closeCalled = false;

      // Extend MockClient to track close() calls.
      final mockClient = _TrackingMockClient(
        (_) async => http.Response(_issOmmFixture, 200),
        onClose: () => closeCalled = true,
      );

      final store = MemoryCacheStore();
      CelestrakClient.withStore(
        httpClient: mockClient,
        cacheStore: store,
      ).dispose();

      expect(closeCalled, isFalse);
    });

    test('cacheDir constructor creates an owned client (dispose is safe)',
        () async {
      final tmp = await TempCache.create();
      try {
        final client = CelestrakClient(cacheDir: tmp.directory.path);

        // Calling dispose must not throw.
        expect(client.dispose, returnsNormally);
      } finally {
        await tmp.tearDown();
      }
    });
  });

  // ── defaultFormat respected ───────────────────────────────────────────────

  group('CelestrakClient — defaultFormat', () {
    test('fetchByNoradId uses defaultFormat when format not specified',
        () async {
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_issTleFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        store: store,
        defaultFormat: CelestrakFormat.tle,
      );

      final tle = await client.fetchByNoradId(25544);

      // TLE format: omm field is null, no stitch needed.
      expect(tle.omm, isNull);
      expect(tle.noradId, equals(25544));
    });

    test('format param overrides defaultFormat', () async {
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        store: store,
        defaultFormat: CelestrakFormat.tle,
      );

      // Explicitly request omm despite tle being the default.
      final tle = await client.fetchByNoradId(
        25544,
        format: CelestrakFormat.omm,
      );

      expect(tle.omm, isNotNull);
    });
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// A [MockClient] subclass that intercepts [close] to track whether it was
/// called, without actually closing the connection.
final class _TrackingMockClient extends http.BaseClient {
  _TrackingMockClient(this._handler, {required void Function() onClose})
      : _onClose = onClose;

  final MockClientHandler _handler;
  final void Function() _onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = await _handler(request as http.Request);
    return http.StreamedResponse(
      Stream.value(r.bodyBytes),
      r.statusCode,
      headers: r.headers,
    );
  }

  @override
  void close() => _onClose();
}
