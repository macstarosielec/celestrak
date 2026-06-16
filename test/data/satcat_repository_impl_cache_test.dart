/// CEL-141: SATCAT repository cache layer.
///
/// Verifies the dataset-discriminated SATCAT cache: zero-network cache hits,
/// the 7-day TTL boundary and 30-day staleness under a [FakeClock], the
/// forceCache and allowStale semantics (including that
/// [SatelliteNotFoundException] and [SatcatParseException] are never masked),
/// and that clearCache scopes to the SATCAT namespace.
library;

import 'dart:convert' show utf8;
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:celestrak/celestrak.dart';
import 'package:celestrak/src/data/local/cache_key_builder.dart';
import 'package:celestrak/src/data/remote/satcat_data_source.dart';
import 'package:celestrak/src/data/satcat_repository_impl.dart';
import 'package:celestrak/src/network/http_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

late String _issSatcatObject;
late String _groupStations;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testBase = 'https://celestrak.test/satcat/records.php';

/// A response handler that counts the HTTP calls it serves.
class _CountingHandler {
  _CountingHandler(this._respond);

  final http.Response Function(http.Request request) _respond;
  int calls = 0;

  Future<http.Response> call(http.Request request) async {
    calls++;
    return _respond(request);
  }
}

/// Creates a [SatcatRepositoryImpl] wired to a [MockClient] data source over
/// [handler], a [FakeClock], and a [MemoryCacheStore].
SatcatRepositoryImpl _repo(
  _CountingHandler handler, {
  required FakeClock clock,
  required MemoryCacheStore store,
  int maxAttempts = 1,
}) =>
    SatcatRepositoryImpl(
      dataSource: SatcatDataSource(
        transport: HttpTransport(
          client: MockClient(handler.call),
          maxAttempts: maxAttempts,
          timeout: const Duration(seconds: 5),
        ),
        baseUrl: _testBase,
      ),
      cacheStore: store,
      clock: clock,
    );

void main() {
  setUpAll(() async {
    _issSatcatObject =
        await File('test/fixtures/satcat/iss_25544_satcat.json').readAsString();
    _groupStations = await File(
      'test/fixtures/satcat/satcat_group_stations.json',
    ).readAsString();
  });

  FakeClock newClock() => FakeClock(DateTime.utc(2026, 6, 1, 14));

  // Cache hit = zero network
  group('SatcatRepositoryImpl - cache hit incurs zero network', () {
    test('fetchByNoradId: second call within TTL makes no HTTP call', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_issSatcatObject, 200));
      final repo = _repo(handler, clock: clock, store: store);

      final first = await repo.fetchByNoradId(25544);
      expect(handler.calls, equals(1));

      clock.advance(const Duration(hours: 1));
      final second = await repo.fetchByNoradId(25544);

      expect(handler.calls, equals(1));
      expect(second, equals(first));
    });

    test('fetchByGroup: cached list served with no HTTP call', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_groupStations, 200));
      final repo = _repo(handler, clock: clock, store: store);

      final first = await repo.fetchByGroup('stations');
      expect(handler.calls, equals(1));
      expect(first, hasLength(3));

      clock.advance(const Duration(days: 1));
      final second = await repo.fetchByGroup('stations');

      expect(handler.calls, equals(1));
      expect(second, equals(first));
    });

    test('fetchAll: empty catalogue is cached and served fresh', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler = _CountingHandler((_) => http.Response('[]', 200));
      final repo = _repo(handler, clock: clock, store: store);

      expect(await repo.fetchAll(), isEmpty);
      expect(handler.calls, equals(1));

      clock.advance(const Duration(days: 2));
      expect(await repo.fetchAll(), isEmpty);
      // Empty list is a valid cached result: zero additional network.
      expect(handler.calls, equals(1));
    });

    test('fetchAll and fetchByGroup("active") share one cache entry', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_groupStations, 200));
      final repo = _repo(handler, clock: clock, store: store);

      await repo.fetchAll();
      expect(handler.calls, equals(1));

      // The active-group key is identical, so this is a cache hit.
      final viaGroup = await repo.fetchByGroup('active');
      expect(handler.calls, equals(1));
      expect(viaGroup, hasLength(3));
    });
  });

  // 7-day TTL boundary
  group('SatcatRepositoryImpl - 7-day TTL boundary', () {
    test('just under 7 days is served from cache (no network)', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_issSatcatObject, 200));
      final repo = _repo(handler, clock: clock, store: store);

      await repo.fetchByNoradId(25544);
      expect(handler.calls, equals(1));

      clock.advance(const Duration(days: 7) - const Duration(seconds: 1));
      await repo.fetchByNoradId(25544);
      expect(handler.calls, equals(1));
    });

    test('just over 7 days triggers a remote refetch', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_issSatcatObject, 200));
      final repo = _repo(handler, clock: clock, store: store);

      await repo.fetchByNoradId(25544);
      expect(handler.calls, equals(1));

      clock.advance(const Duration(days: 7) + const Duration(seconds: 1));
      await repo.fetchByNoradId(25544);
      expect(handler.calls, equals(2));
    });
  });

  // 30-day staleness
  group('SatcatRepositoryImpl - 30-day staleness via *Age', () {
    test('noradIdAge crosses kSatcatStaleThreshold deterministically',
        () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_issSatcatObject, 200));
      final repo = _repo(handler, clock: clock, store: store);

      expect(await repo.noradIdAge(25544), isNull);

      await repo.fetchByNoradId(25544);
      expect(await repo.noradIdAge(25544), equals(Duration.zero));

      clock.advance(kSatcatStaleThreshold - const Duration(seconds: 1));
      final ageBefore = await repo.noradIdAge(25544);
      expect(ageBefore! < kSatcatStaleThreshold, isTrue);

      clock.advance(const Duration(seconds: 2));
      final ageAfter = await repo.noradIdAge(25544);
      expect(ageAfter! > kSatcatStaleThreshold, isTrue);
    });

    test('allAge mirrors groupAge("active")', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_groupStations, 200));
      final repo = _repo(handler, clock: clock, store: store);

      await repo.fetchAll();
      clock.advance(const Duration(days: 5));

      expect(await repo.allAge(), equals(const Duration(days: 5)));
      expect(await repo.groupAge('active'), equals(const Duration(days: 5)));
    });
  });

  // forceCache
  group('SatcatRepositoryImpl - forceCache', () {
    test('no entry throws CacheMissException with zero network', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_issSatcatObject, 200));
      final repo = _repo(handler, clock: clock, store: store);

      await expectLater(
        repo.fetchByNoradId(25544, forceCache: true),
        throwsA(isA<CacheMissException>()),
      );
      expect(handler.calls, equals(0));
    });

    test('TTL-expired entry is served from cache with zero network', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_issSatcatObject, 200));
      final repo = _repo(handler, clock: clock, store: store);

      await repo.fetchByNoradId(25544);
      expect(handler.calls, equals(1));

      // Age well past the 7-day TTL.
      clock.advance(const Duration(days: 14));
      final entry = await repo.fetchByNoradId(25544, forceCache: true);

      expect(handler.calls, equals(1));
      expect(entry.noradId, equals(25544));
    });

    test('bulk forceCache with no entry throws CacheMissException', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_groupStations, 200));
      final repo = _repo(handler, clock: clock, store: store);

      await expectLater(
        repo.fetchByGroup('stations', forceCache: true),
        throwsA(isA<CacheMissException>()),
      );
      expect(handler.calls, equals(0));
    });
  });

  // allowStale
  group('SatcatRepositoryImpl - allowStale', () {
    test('network failure after populate returns the stale entry', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      var fail = false;
      final handler = _CountingHandler(
        (_) => fail
            ? http.Response('server error', 503)
            : http.Response(_issSatcatObject, 200),
      );
      final repo = _repo(handler, clock: clock, store: store);

      final fresh = await repo.fetchByNoradId(25544);

      // Expire the TTL and make the network fail.
      clock.advance(const Duration(days: 8));
      fail = true;

      final stale = await repo.fetchByNoradId(25544, allowStale: true);
      expect(stale, equals(fresh));
    });

    test('without allowStale a network failure rethrows NetworkException',
        () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      var fail = false;
      final handler = _CountingHandler(
        (_) => fail
            ? http.Response('server error', 503)
            : http.Response(_issSatcatObject, 200),
      );
      final repo = _repo(handler, clock: clock, store: store);

      await repo.fetchByNoradId(25544);
      clock.advance(const Duration(days: 8));
      fail = true;

      await expectLater(
        repo.fetchByNoradId(25544),
        throwsA(isA<NetworkException>()),
      );
    });

    test('bulk: network failure after populate returns the stale list',
        () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      var fail = false;
      final handler = _CountingHandler(
        (_) => fail
            ? http.Response('server error', 503)
            : http.Response(_groupStations, 200),
      );
      final repo = _repo(handler, clock: clock, store: store);

      final fresh = await repo.fetchByGroup('stations');
      clock.advance(const Duration(days: 8));
      fail = true;

      final stale = await repo.fetchByGroup('stations', allowStale: true);
      expect(stale, equals(fresh));
    });

    test('bulk: allowStale with no cached entry rethrows the failure',
        () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response('server error', 503));
      final repo = _repo(handler, clock: clock, store: store);

      // No prior populate: the cache is empty, so allowStale has nothing to
      // fall back to and must not swallow the network failure.
      await expectLater(
        repo.fetchByGroup('stations', allowStale: true),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // fetchByIntlDesignator cache path
  group('SatcatRepositoryImpl - fetchByIntlDesignator cache', () {
    test('second call within TTL makes no HTTP call', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_groupStations, 200));
      final repo = _repo(handler, clock: clock, store: store);

      final first = await repo.fetchByIntlDesignator('1998-067');
      expect(handler.calls, equals(1));
      expect(first, hasLength(3));

      clock.advance(const Duration(days: 1));
      final second = await repo.fetchByIntlDesignator('1998-067');

      expect(handler.calls, equals(1));
      expect(second, equals(first));
    });

    test('forceCache with no entry throws CacheMissException', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_groupStations, 200));
      final repo = _repo(handler, clock: clock, store: store);

      await expectLater(
        repo.fetchByIntlDesignator('1998-067', forceCache: true),
        throwsA(isA<CacheMissException>()),
      );
      expect(handler.calls, equals(0));
    });

    test('intlDesignatorAge reports the cached entry age', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_groupStations, 200));
      final repo = _repo(handler, clock: clock, store: store);

      expect(await repo.intlDesignatorAge('1998-067'), isNull);

      await repo.fetchByIntlDesignator('1998-067');
      clock.advance(const Duration(days: 3));

      expect(
        await repo.intlDesignatorAge('1998-067'),
        equals(const Duration(days: 3)),
      );
    });
  });

  // Corrupt bulk cache payloads surface as SatcatParseException
  group('SatcatRepositoryImpl - corrupt bulk cache payload', () {
    test('non-JSON cached bytes throw SatcatParseException on read', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_groupStations, 200));
      final repo = _repo(handler, clock: clock, store: store);

      final key = CacheKeyBuilder.forSatcatGroup('stations');
      await store.write(
        key,
        Uint8List.fromList(utf8.encode('not json')),
        clock.now,
      );

      await expectLater(
        repo.fetchByGroup('stations', forceCache: true),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('JSON object (not array) cached bytes throw SatcatParseException',
        () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_groupStations, 200));
      final repo = _repo(handler, clock: clock, store: store);

      final key = CacheKeyBuilder.forSatcatGroup('stations');
      await store.write(
        key,
        Uint8List.fromList(utf8.encode('{"NORAD_CAT_ID": 1}')),
        clock.now,
      );

      await expectLater(
        repo.fetchByGroup('stations', forceCache: true),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('a row that fails to parse throws rather than truncating the list',
        () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_groupStations, 200));
      final repo = _repo(handler, clock: clock, store: store);

      final key = CacheKeyBuilder.forSatcatGroup('stations');
      // A row missing the required NORAD_CAT_ID would be silently skipped by
      // the lenient bulk parser; the strict cache read must reject it instead.
      await store.write(
        key,
        Uint8List.fromList(utf8.encode('[{"OBJECT_NAME": "NO ID"}]')),
        clock.now,
      );

      await expectLater(
        repo.fetchByGroup('stations', forceCache: true),
        throwsA(isA<SatcatParseException>()),
      );
    });
  });

  // allowStale never masks not-found / parse errors
  group('SatcatRepositoryImpl - allowStale never masks data errors', () {
    test('SatelliteNotFoundException still thrown with allowStale + cache',
        () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      var miss = false;
      final handler = _CountingHandler(
        (_) => miss
            ? http.Response('No SATCAT records found', 200)
            : http.Response(_issSatcatObject, 200),
      );
      final repo = _repo(handler, clock: clock, store: store);

      // Populate a cache entry first.
      await repo.fetchByNoradId(25544);
      clock.advance(const Duration(days: 8));
      miss = true;

      await expectLater(
        repo.fetchByNoradId(25544, allowStale: true),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });

    test('SatcatParseException still thrown with allowStale + cache', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      var corrupt = false;
      final handler = _CountingHandler(
        (_) => corrupt
            ? http.Response('{ not json', 200)
            : http.Response(_issSatcatObject, 200),
      );
      final repo = _repo(handler, clock: clock, store: store);

      await repo.fetchByNoradId(25544);
      clock.advance(const Duration(days: 8));
      corrupt = true;

      await expectLater(
        repo.fetchByNoradId(25544, allowStale: true),
        throwsA(isA<SatcatParseException>()),
      );
    });
  });

  // clearCache scoping
  group('SatcatRepositoryImpl - clearCache', () {
    test('clearCache removes SATCAT entries (forceCache then misses)',
        () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_issSatcatObject, 200));
      final repo = _repo(handler, clock: clock, store: store);

      await repo.fetchByNoradId(25544);
      expect(await repo.noradIdAge(25544), isNotNull);

      await repo.clearCache();

      expect(await repo.noradIdAge(25544), isNull);
      await expectLater(
        repo.fetchByNoradId(25544, forceCache: true),
        throwsA(isA<CacheMissException>()),
      );
    });

    test('default clearCache leaves GP entries intact', () async {
      final clock = newClock();
      final store = MemoryCacheStore();
      final handler =
          _CountingHandler((_) => http.Response(_issSatcatObject, 200));
      final repo = _repo(handler, clock: clock, store: store);

      // Seed a GP-shaped key directly in the shared store.
      final gpKey =
          CacheKeyBuilder.forNoradId(25544, format: CelestrakFormat.omm);
      await store.write(
        gpKey,
        // Arbitrary bytes; clearCache must not touch this key.
        Uint8List.fromList(utf8.encode('gp-payload')),
        clock.now,
      );

      await repo.fetchByNoradId(25544);
      await repo.clearCache();

      // SATCAT key gone, GP key untouched.
      expect(await repo.noradIdAge(25544), isNull);
      expect(await store.read(gpKey), isNotNull);
    });
  });
}
