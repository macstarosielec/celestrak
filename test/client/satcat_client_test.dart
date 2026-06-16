import 'dart:io' show File;

import 'package:celestrak/celestrak.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';
import '../support/temp_cache.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

late String _issSatcatFixture;
late String _stationsFixture;

// A NORAD id that does NOT appear in the stations fixture, for lookup-null.
const int _absentNoradId = 99999;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [SatcatClient] via [SatcatClient.withStore] backed by a
/// [MemoryCacheStore] and [MockClient].
///
/// [handler] handles every request; use [_TransportSpy] when a per-call count
/// is needed.
SatcatClient _client(
  MockClientHandler handler, {
  FakeClock? clock,
  MemoryCacheStore? store,
  int maxAttempts = 1,
  Duration defaultTtl = kSatcatDefaultTtl,
  Duration staleThreshold = kSatcatStaleThreshold,
  Duration timeout = kDefaultTimeout,
}) {
  final effectiveClock = clock ?? FakeClock(DateTime.utc(2026, 6, 1, 14));
  final effectiveStore = store ?? MemoryCacheStore();

  return SatcatClient.withStore(
    httpClient: MockClient(handler),
    cacheStore: effectiveStore,
    defaultTtl: defaultTtl,
    staleThreshold: staleThreshold,
    clock: effectiveClock,
    maxAttempts: maxAttempts,
    timeout: timeout,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    _issSatcatFixture = await File(
      'test/fixtures/satcat/iss_25544_satcat.json',
    ).readAsString();
    _stationsFixture = await File(
      'test/fixtures/satcat/satcat_group_stations.json',
    ).readAsString();
  });

  // -- constructors ----------------------------------------------------------

  group('SatcatClient - constructors', () {
    test('withStore constructs successfully', () {
      final client = _client((_) async => http.Response('[]', 200));
      expect(client, isNotNull);
    });

    test('default cacheDir constructor constructs and disposes without error',
        () async {
      final tmp = await TempCache.create();
      try {
        final client = SatcatClient(cacheDir: tmp.directory.path);
        expect(client.dispose, returnsNormally);
      } finally {
        await tmp.tearDown();
      }
    });

    test('maxAttempts: 0 throws ArgumentError', () {
      final rawClient = http.Client();
      addTearDown(rawClient.close);
      expect(
        () => SatcatClient.withStore(
          httpClient: rawClient,
          cacheStore: MemoryCacheStore(),
          maxAttempts: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // -- default properties ----------------------------------------------------

  group('SatcatClient - default properties', () {
    test('defaultTtl is 7 days by default', () {
      final rawClient = http.Client();
      addTearDown(rawClient.close);
      final client = SatcatClient.withStore(
        httpClient: rawClient,
        cacheStore: MemoryCacheStore(),
      );
      expect(client.defaultTtl, equals(kSatcatDefaultTtl));
    });

    test('staleThreshold is 30 days by default', () {
      final rawClient = http.Client();
      addTearDown(rawClient.close);
      final client = SatcatClient.withStore(
        httpClient: rawClient,
        cacheStore: MemoryCacheStore(),
      );
      expect(client.staleThreshold, equals(kSatcatStaleThreshold));
    });

    test('timeout / maxAttempts defaults are preserved', () {
      final rawClient = http.Client();
      addTearDown(rawClient.close);
      final client = SatcatClient.withStore(
        httpClient: rawClient,
        cacheStore: MemoryCacheStore(),
      );
      expect(client.timeout, equals(kDefaultTimeout));
      expect(client.maxAttempts, equals(kDefaultMaxAttempts));
    });

    test('custom configuration is preserved', () {
      final client = _client(
        (_) async => http.Response('[]', 200),
        defaultTtl: const Duration(days: 1),
        staleThreshold: const Duration(days: 2),
        timeout: const Duration(seconds: 5),
        maxAttempts: 3,
      );
      expect(client.defaultTtl, equals(const Duration(days: 1)));
      expect(client.staleThreshold, equals(const Duration(days: 2)));
      expect(client.timeout, equals(const Duration(seconds: 5)));
      expect(client.maxAttempts, equals(3));
    });
  });

  // -- fetchByNoradId (cache behaviour) --------------------------------------

  group('SatcatClient - fetchByNoradId', () {
    test('returns the ISS entry on first fetch', () async {
      final client = _client(
        (_) async => http.Response(_issSatcatFixture, 200),
      );

      final entry = await client.fetchByNoradId(25544);

      expect(entry.noradId, equals(25544));
      expect(entry.ownerCode, equals('ISS'));
      expect(entry.owner.code, equals('ISS'));
    });

    test('second call within TTL issues zero additional network calls',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final spy = _TransportSpy(
        (_) async => http.Response(_issSatcatFixture, 200),
      );
      final client = _client(spy.call, clock: clock, store: store);

      await client.fetchByNoradId(25544);
      clock.advance(const Duration(hours: 1));
      final second = await client.fetchByNoradId(25544);

      expect(spy.calls, equals(1));
      expect(second.noradId, equals(25544));
    });
  });

  // -- allowStale ------------------------------------------------------------

  group('SatcatClient - allowStale', () {
    test('allowStale:true returns the stale entry when network fails',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final client = _client(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_issSatcatFixture, 200);
        },
        clock: clock,
        store: store,
        defaultTtl: const Duration(hours: 1),
      );

      await client.fetchByNoradId(25544);
      clock.advance(const Duration(hours: 3));
      fail = true;

      final entry = await client.fetchByNoradId(25544, allowStale: true);

      expect(entry.noradId, equals(25544));
    });

    test('allowStale:false re-throws NetworkException when cache is stale',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final client = _client(
        (_) async {
          if (fail) return http.Response('server error', 503);
          return http.Response(_issSatcatFixture, 200);
        },
        clock: clock,
        store: store,
        defaultTtl: const Duration(hours: 1),
      );

      await client.fetchByNoradId(25544);
      clock.advance(const Duration(hours: 3));
      fail = true;

      await expectLater(
        client.fetchByNoradId(25544),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // -- forceCache ------------------------------------------------------------

  group('SatcatClient - forceCache', () {
    test('forceCache on empty cache throws CacheMissException, zero network',
        () async {
      final spy = _TransportSpy(
        (_) async => http.Response(_issSatcatFixture, 200),
      );
      final client = _client(spy.call);

      await expectLater(
        client.fetchByNoradId(25544, forceCache: true),
        throwsA(isA<CacheMissException>()),
      );
      expect(spy.calls, equals(0));
    });
  });

  // -- fetchCategory / fetchCategoryByGroup ----------------------------------

  group('SatcatClient - group queries', () {
    test('fetchCategoryByGroup resolves the stations fixture', () async {
      final client = _client(
        (_) async => http.Response(_stationsFixture, 200),
      );

      final entries = await client.fetchCategoryByGroup('stations');

      expect(entries.map((e) => e.noradId), contains(25544));
      expect(entries.length, equals(3));
    });

    test('fetchCategory delegates to the category group string', () async {
      String? observedGroup;
      final client = _client(
        (req) async {
          observedGroup = req.url.queryParameters['GROUP'];
          return http.Response(_stationsFixture, 200);
        },
      );

      final entries = await client.fetchCategory(SatelliteCategory.stations);

      expect(observedGroup, equals(SatelliteCategory.stations.group));
      expect(observedGroup, equals('stations'));
      expect(entries.length, equals(3));
    });
  });

  // -- lookup ----------------------------------------------------------------

  group('SatcatClient - lookup', () {
    test('returns the ISS entry and null for an absent id', () async {
      final client = _client(
        (_) async => http.Response(_stationsFixture, 200),
      );

      await client.fetchAll();

      final iss = await client.lookup(25544);
      final absent = await client.lookup(_absentNoradId);

      expect(iss, isNotNull);
      expect(iss!.noradId, equals(25544));
      expect(iss.ownerCode, equals('ISS'));
      expect(absent, isNull);
    });

    test('second lookup within TTL issues zero additional network calls',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final spy = _TransportSpy(
        (_) async => http.Response(_stationsFixture, 200),
      );
      final client = _client(spy.call, clock: clock, store: store);

      final first = await client.lookup(25544);
      clock.advance(const Duration(hours: 1));
      final second = await client.lookup(48274);

      expect(first?.noradId, equals(25544));
      expect(second?.noradId, equals(48274));
      // First lookup builds the catalogue (one network call); second is served
      // entirely from the in-memory index.
      expect(spy.calls, equals(1));
    });

    test('lookup after clearCache refetches the catalogue', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final spy = _TransportSpy(
        (_) async => http.Response(_stationsFixture, 200),
      );
      final client = _client(spy.call, clock: clock, store: store);

      await client.lookup(25544);
      await client.clearCache();
      await client.lookup(25544);

      expect(spy.calls, equals(2));
    });

    test('lookup after TTL expiry refetches the catalogue', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final spy = _TransportSpy(
        (_) async => http.Response(_stationsFixture, 200),
      );
      final client = _client(
        spy.call,
        clock: clock,
        store: store,
        defaultTtl: const Duration(hours: 1),
      );

      await client.lookup(25544);
      clock.advance(const Duration(hours: 2));
      await client.lookup(25544);

      expect(spy.calls, equals(2));
    });

    test('lookup over an empty catalogue returns null', () async {
      final client = _client((_) async => http.Response('[]', 200));

      expect(await client.lookup(25544), isNull);
      expect(await client.lookup(_absentNoradId), isNull);
    });

    test('concurrent first lookups are coalesced into one network call',
        () async {
      final spy = _TransportSpy(
        (_) async => http.Response(_stationsFixture, 200),
      );
      final client = _client(spy.call);

      // Fire two lookups before the first completes: they must share a single
      // catalogue fetch rather than each refetching.
      final results = await Future.wait([
        client.lookup(25544),
        client.lookup(48274),
      ]);

      expect(results[0]?.noradId, equals(25544));
      expect(results[1]?.noradId, equals(48274));
      expect(spy.calls, equals(1));
    });

    test('lookup with allowStale returns a stale entry when the refetch fails',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final client = _client(
        (_) async => fail
            ? http.Response('server error', 503)
            : http.Response(_stationsFixture, 200),
        clock: clock,
        store: store,
        defaultTtl: const Duration(hours: 1),
      );

      // Populate the catalogue, expire it, then make the network fail.
      await client.lookup(25544);
      clock.advance(const Duration(hours: 2));
      fail = true;

      final stale = await client.lookup(25544, allowStale: true);
      expect(stale, isNotNull);
      expect(stale!.noradId, equals(25544));
    });

    test('lookup without allowStale rethrows when the refetch fails', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final client = _client(
        (_) async => fail
            ? http.Response('server error', 503)
            : http.Response(_stationsFixture, 200),
        clock: clock,
        store: store,
        defaultTtl: const Duration(hours: 1),
      );

      await client.lookup(25544);
      clock.advance(const Duration(hours: 2));
      fail = true;

      await expectLater(
        client.lookup(25544),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // -- age methods -----------------------------------------------------------

  group('SatcatClient - age methods', () {
    test('noradIdAge returns null before fetch and a Duration after', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_issSatcatFixture, 200),
        clock: clock,
        store: store,
      );

      expect(await client.noradIdAge(25544), isNull);

      await client.fetchByNoradId(25544);
      clock.advance(const Duration(minutes: 10));

      expect(
        await client.noradIdAge(25544),
        equals(const Duration(minutes: 10)),
      );
    });

    test('groupAge / categoryAge / allAge report fetched ages', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_stationsFixture, 200),
        clock: clock,
        store: store,
      );

      expect(await client.groupAge('stations'), isNull);
      expect(await client.categoryAge(SatelliteCategory.stations), isNull);
      expect(await client.allAge(), isNull);

      await client.fetchCategory(SatelliteCategory.stations);
      await client.fetchAll();
      clock.advance(const Duration(minutes: 5));

      expect(
        await client.categoryAge(SatelliteCategory.stations),
        equals(const Duration(minutes: 5)),
      );
      expect(
        await client.groupAge('stations'),
        equals(const Duration(minutes: 5)),
      );
      expect(await client.allAge(), equals(const Duration(minutes: 5)));
    });

    test('intlDesignatorAge returns null before fetch and Duration after',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_stationsFixture, 200),
        clock: clock,
        store: store,
      );

      expect(await client.intlDesignatorAge('1998-067'), isNull);

      await client.fetchByIntlDesignator('1998-067');
      clock.advance(const Duration(hours: 1));

      expect(
        await client.intlDesignatorAge('1998-067'),
        equals(const Duration(hours: 1)),
      );
    });

    test('age exceeds staleThreshold after advancing the clock', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_issSatcatFixture, 200),
        clock: clock,
        store: store,
        staleThreshold: const Duration(days: 30),
      );

      await client.fetchByNoradId(25544);
      clock.advance(const Duration(days: 31));

      final age = await client.noradIdAge(25544);
      expect(age, isNotNull);
      expect(age! > client.staleThreshold, isTrue);
    });
  });

  // -- dispose ---------------------------------------------------------------

  group('SatcatClient - dispose', () {
    test('dispose with ownsClient=false does not close the external client',
        () async {
      var closeCalled = false;
      final mockClient = _TrackingMockClient(
        (_) async => http.Response(_issSatcatFixture, 200),
        onClose: () => closeCalled = true,
      );

      SatcatClient.withStore(
        httpClient: mockClient,
        cacheStore: MemoryCacheStore(),
      ).dispose();

      expect(closeCalled, isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Wraps a [MockClientHandler] and counts each call, for asserting the exact
/// number of network requests issued.
final class _TransportSpy {
  _TransportSpy(this._handler);

  final MockClientHandler _handler;

  /// Number of times [call] has been invoked.
  int calls = 0;

  /// Increments [calls] and delegates to the wrapped handler.
  Future<http.Response> call(http.Request request) {
    calls++;
    return _handler(request);
  }
}

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
