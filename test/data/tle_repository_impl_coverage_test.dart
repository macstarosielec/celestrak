/// Targeted tests to close coverage gaps identified by lcov.
///
/// Exercises paths that are correct but not reachable via existing tests:
/// - Cache eviction races (bytes == null on read after age check).
/// - TLE sub-key independently evicted.
/// - TLE-format cache-hit paths for category, group, name, intldes.
/// - No matching NORAD ID in a TLE body.
/// - CacheMissException when fromCache is true and TLE sub-key is absent.
/// - SatelliteNotFoundException and NetworkException branches in tleBodyFor.
/// - parseTleInIsolate fromCache=true branch via useIsolate=true.
///
/// Fixtures loaded once in [setUpAll]:
/// [_stationsOmmFixture], [_stationsTleFixture], [_nameIssOmmFixture],
/// [_nameIssTleFixture], [_intdesOmmFixture], [_intdesTleFixture],
/// [_issTleFixture], and [_issOmmFixture].
library;

import 'dart:typed_data' show Uint8List;

import 'package:celestrak/celestrak.dart';
import 'package:celestrak/src/data/local/cache_store.dart';
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

late String _stationsOmmFixture;
late String _stationsTleFixture;
late String _nameIssOmmFixture;
late String _nameIssTleFixture;
late String _intdesOmmFixture;
late String _intdesTleFixture;
late String _issTleFixture;
late String _issOmmFixture;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testBase = 'https://celestrak.test/gp.php';

/// A [CacheStore] that delegates to a [MemoryCacheStore] but can be
/// configured to drop reads for a named key once (simulating a concurrent
/// eviction race between the age() check and the subsequent read()).
final class _EvictingCacheStore implements CacheStore {
  _EvictingCacheStore() : _inner = MemoryCacheStore();

  final MemoryCacheStore _inner;

  /// Keys whose next [read] call returns null regardless of stored content.
  final _evictOnRead = <String>{};

  void evictOnNextRead(String key) => _evictOnRead.add(key);

  @override
  Future<Uint8List?> read(String key) async {
    if (_evictOnRead.remove(key)) return null;
    return _inner.read(key);
  }

  @override
  Future<void> write(
    String key,
    Uint8List bytes,
    DateTime writtenAt,
  ) =>
      _inner.write(key, bytes, writtenAt);

  @override
  Future<Duration?> age(String key, DateTime now) => _inner.age(key, now);

  @override
  Future<void> clear({String? keyPrefix}) => _inner.clear(keyPrefix: keyPrefix);
}

/// A [CacheStore] that delegates to [MemoryCacheStore] and drops read calls
/// for a specific key after a given number of allowed reads.
final class _TleSubKeyEvictingStore implements CacheStore {
  _TleSubKeyEvictingStore() : _inner = MemoryCacheStore();

  final MemoryCacheStore _inner;
  final _blockedKeys = <String>{};

  void blockReadsFor(String key) => _blockedKeys.add(key);

  @override
  Future<Uint8List?> read(String key) async {
    if (_blockedKeys.contains(key)) return null;
    return _inner.read(key);
  }

  @override
  Future<void> write(
    String key,
    Uint8List bytes,
    DateTime writtenAt,
  ) =>
      _inner.write(key, bytes, writtenAt);

  @override
  Future<Duration?> age(String key, DateTime now) => _inner.age(key, now);

  @override
  Future<void> clear({String? keyPrefix}) => _inner.clear(keyPrefix: keyPrefix);
}

/// Creates a [TleRepositoryImpl] with the given [store].
TleRepositoryImpl _repo(
  MockClientHandler ommHandler, {
  MockClientHandler? tleHandler,
  CacheStore? store,
  FakeClock? clock,
  int maxAttempts = 1,
  bool useIsolate = false,
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
    useIsolate: useIsolate,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    _stationsOmmFixture = await loadFixture(
      'test/fixtures/stations_group_omm.json',
    );
    _stationsTleFixture = await loadFixture(
      'test/fixtures/stations_group.txt',
    );
    _nameIssOmmFixture = await loadFixture('test/fixtures/name_iss_omm.json');
    _nameIssTleFixture = await loadFixture('test/fixtures/name_iss.txt');
    _intdesOmmFixture = await loadFixture(
      'test/fixtures/intdes_1998_067a_omm.json',
    );
    _intdesTleFixture = await loadFixture('test/fixtures/intdes_1998_067a.txt');
    _issTleFixture = await loadFixture('test/fixtures/iss_25544.tle');
    _issOmmFixture = await loadFixture('test/fixtures/iss_25544_omm.json');
  });

  // ── _parseTle: no matching NORAD ID ───────────────────────────────────────

  group('TleRepositoryImpl._parseTle — no matching NORAD ID in body', () {
    // Use valid TLE lines for a different satellite (Hubble, NORAD 20580) and
    // request NORAD ID 25544, which is absent from the body.  The checksum on
    // each line must be valid; the body is taken verbatim from the stations
    // fixture which passes the checksum validator.
    test('throws SatelliteNotFoundException when ID absent from TLE body',
        () async {
      final repo = _repo(
        (_) async => http.Response(_stationsTleFixture, 200),
      );

      // Request NORAD ID 99999 which is not in the stations fixture.
      await expectLater(
        repo.fetchByNoradId(99999, format: CelestrakFormat.tle),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });

    test('SatelliteNotFoundException.noradId matches the requested id',
        () async {
      final repo = _repo(
        (_) async => http.Response(_stationsTleFixture, 200),
      );

      try {
        await repo.fetchByNoradId(99999, format: CelestrakFormat.tle);
        fail('expected SatelliteNotFoundException');
      } on SatelliteNotFoundException catch (e) {
        expect(e.noradId, 99999);
      }
    });
  });

  // ── _readCategoryFromCache: TLE format cache hit ───────────────────────────

  group(
    'TleRepositoryImpl.fetchCategory — TLE format cache hit (source=local)',
    () {
      test('cache hit on TLE format stamps source=local', () async {
        final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
        final store = MemoryCacheStore();
        final repo = _repo(
          (_) async => http.Response(_stationsTleFixture, 200),
          clock: clock,
          store: store,
        );

        // Prime the TLE cache.
        await repo.fetchCategory(
          SatelliteCategory.stations,
          format: CelestrakFormat.tle,
        );

        // Advance within TTL — next call is a cache hit.
        clock.advance(const Duration(minutes: 30));
        final results = await repo.fetchCategory(
          SatelliteCategory.stations,
          format: CelestrakFormat.tle,
        );

        expect(results, isNotEmpty);
        for (final r in results) {
          expect(r.source, equals(TleSource.local));
        }
      });

      test('TLE cache hit does not issue transport call', () async {
        var calls = 0;
        final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
        final store = MemoryCacheStore();
        final repo = _repo(
          (_) async {
            calls++;
            return http.Response(_stationsTleFixture, 200);
          },
          clock: clock,
          store: store,
        );

        await repo.fetchCategory(
          SatelliteCategory.stations,
          format: CelestrakFormat.tle,
        );
        clock.advance(const Duration(minutes: 30));
        await repo.fetchCategory(
          SatelliteCategory.stations,
          format: CelestrakFormat.tle,
        );

        expect(calls, equals(1));
      });
    },
  );

  // ── _readGroupFromCache: TLE format cache hit ─────────────────────────────

  group(
    'TleRepositoryImpl.fetchCategoryByGroup — TLE format cache hit',
    () {
      test('cache hit on TLE format stamps source=local', () async {
        final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
        final store = MemoryCacheStore();
        final repo = _repo(
          (_) async => http.Response(_stationsTleFixture, 200),
          clock: clock,
          store: store,
        );

        await repo.fetchCategoryByGroup(
          'stations',
          format: CelestrakFormat.tle,
        );
        clock.advance(const Duration(minutes: 30));
        final results = await repo.fetchCategoryByGroup(
          'stations',
          format: CelestrakFormat.tle,
        );

        expect(results, isNotEmpty);
        for (final r in results) {
          expect(r.source, equals(TleSource.local));
        }
      });
    },
  );

  // ── _readNameFromCache: TLE format cache hit ──────────────────────────────

  group(
    'TleRepositoryImpl.fetchByName — TLE format cache hit',
    () {
      test('cache hit on TLE format stamps source=local', () async {
        final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
        final store = MemoryCacheStore();
        final repo = _repo(
          (_) async => http.Response(_nameIssTleFixture, 200),
          clock: clock,
          store: store,
        );

        await repo.fetchByName('ISS', format: CelestrakFormat.tle);
        clock.advance(const Duration(minutes: 30));
        final results = await repo.fetchByName(
          'ISS',
          format: CelestrakFormat.tle,
        );

        expect(results, isNotEmpty);
        for (final r in results) {
          expect(r.source, equals(TleSource.local));
        }
      });
    },
  );

  // ── _readIntlDesFromCache: TLE format cache hit ───────────────────────────

  group(
    'TleRepositoryImpl.fetchByIntlDesignator — TLE format cache hit',
    () {
      test('cache hit on TLE format stamps source=local', () async {
        final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
        final store = MemoryCacheStore();
        final repo = _repo(
          (_) async => http.Response(_intdesTleFixture, 200),
          clock: clock,
          store: store,
        );

        await repo.fetchByIntlDesignator(
          '1998-067A',
          format: CelestrakFormat.tle,
        );
        clock.advance(const Duration(minutes: 30));
        final results = await repo.fetchByIntlDesignator(
          '1998-067A',
          format: CelestrakFormat.tle,
        );

        expect(results, isNotEmpty);
        for (final r in results) {
          expect(r.source, equals(TleSource.local));
        }
      });
    },
  );

  // ── _readCategoryFromCache: TLE sub-key independently evicted ─────────────

  group(
    'TleRepositoryImpl.fetchCategory — TLE sub-key eviction (OMM format)',
    () {
      test(
        'throws CacheMissException when TLE sub-key is independently evicted',
        () async {
          final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
          final store = _TleSubKeyEvictingStore();
          final repo = _repo(
            (_) async => http.Response(_stationsOmmFixture, 200),
            tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
            clock: clock,
            store: store,
          );

          // Prime both OMM and TLE cache entries.
          await repo.fetchCategory(SatelliteCategory.stations);

          // Block reads on the TLE sub-key to simulate independent eviction.
          final tleKey = CacheKeyBuilder.forCategory(
            SatelliteCategory.stations,
            format: CelestrakFormat.tle,
          );
          store.blockReadsFor(tleKey);

          // Advance within TTL so the OMM hit is attempted.
          clock.advance(const Duration(minutes: 30));

          await expectLater(
            repo.fetchCategory(SatelliteCategory.stations),
            throwsA(isA<CacheMissException>()),
          );
        },
      );

      test(
        'CacheMissException.key references the evicted TLE sub-key',
        () async {
          final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
          final store = _TleSubKeyEvictingStore();
          final repo = _repo(
            (_) async => http.Response(_stationsOmmFixture, 200),
            tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchCategory(SatelliteCategory.stations);

          final tleKey = CacheKeyBuilder.forCategory(
            SatelliteCategory.stations,
            format: CelestrakFormat.tle,
          );
          store.blockReadsFor(tleKey);

          clock.advance(const Duration(minutes: 30));

          try {
            await repo.fetchCategory(SatelliteCategory.stations);
            fail('expected CacheMissException');
          } on CacheMissException catch (e) {
            expect(e.key, contains('stations'));
            expect(e.key, contains('tle'));
          }
        },
      );
    },
  );

  // ── _readGroupFromCache: TLE sub-key independently evicted ───────────────

  group(
    'TleRepositoryImpl.fetchCategoryByGroup — TLE sub-key eviction',
    () {
      test(
        'throws CacheMissException when TLE sub-key is independently evicted',
        () async {
          final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
          final store = _TleSubKeyEvictingStore();
          final repo = _repo(
            (_) async => http.Response(_stationsOmmFixture, 200),
            tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchCategoryByGroup('stations');

          final tleKey = CacheKeyBuilder.forGroup(
            'stations',
            format: CelestrakFormat.tle,
          );
          store.blockReadsFor(tleKey);
          clock.advance(const Duration(minutes: 30));

          await expectLater(
            repo.fetchCategoryByGroup('stations'),
            throwsA(isA<CacheMissException>()),
          );
        },
      );
    },
  );

  // ── _readNameFromCache: TLE sub-key independently evicted ────────────────

  group(
    'TleRepositoryImpl.fetchByName — TLE sub-key eviction (OMM format)',
    () {
      test(
        'throws CacheMissException when TLE sub-key is independently evicted',
        () async {
          final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
          final store = _TleSubKeyEvictingStore();
          final repo = _repo(
            (_) async => http.Response(_nameIssOmmFixture, 200),
            tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByName('ISS');

          final tleKey = CacheKeyBuilder.forName(
            'ISS',
            format: CelestrakFormat.tle,
          );
          store.blockReadsFor(tleKey);
          clock.advance(const Duration(minutes: 30));

          await expectLater(
            repo.fetchByName('ISS'),
            throwsA(isA<CacheMissException>()),
          );
        },
      );
    },
  );

  // ── _readIntlDesFromCache: TLE sub-key independently evicted ─────────────

  group(
    'TleRepositoryImpl.fetchByIntlDesignator — TLE sub-key eviction',
    () {
      test(
        'throws CacheMissException when TLE sub-key is independently evicted',
        () async {
          final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
          final store = _TleSubKeyEvictingStore();
          final repo = _repo(
            (_) async => http.Response(_intdesOmmFixture, 200),
            tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByIntlDesignator('1998-067A');

          final tleKey = CacheKeyBuilder.forIntlDesignator(
            '1998-067A',
            format: CelestrakFormat.tle,
          );
          store.blockReadsFor(tleKey);
          clock.advance(const Duration(minutes: 30));

          await expectLater(
            repo.fetchByIntlDesignator('1998-067A'),
            throwsA(isA<CacheMissException>()),
          );
        },
      );
    },
  );

  // ── Cache eviction races (primary key evicted between age() and read()) ───

  group(
    'TleRepositoryImpl — primary cache key evicted between age() and read()',
    () {
      test('fetchCategory: throws NetworkException on primary key eviction',
          () async {
        final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
        final store = _EvictingCacheStore();
        final repo = _repo(
          (_) async => http.Response(_stationsOmmFixture, 200),
          tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
          clock: clock,
          store: store,
        );

        // Prime the cache.
        await repo.fetchCategory(SatelliteCategory.stations);

        // Arrange eviction of the primary OMM key on the next read.
        final ommKey = CacheKeyBuilder.forCategory(
          SatelliteCategory.stations,
          format: CelestrakFormat.omm,
        );
        store.evictOnNextRead(ommKey);

        // Advance within TTL so the cache path is taken.
        clock.advance(const Duration(minutes: 30));

        await expectLater(
          repo.fetchCategory(SatelliteCategory.stations),
          throwsA(isA<NetworkException>()),
        );
      });

      test('fetchCategoryByGroup: throws NetworkException on primary eviction',
          () async {
        final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
        final store = _EvictingCacheStore();
        final repo = _repo(
          (_) async => http.Response(_stationsOmmFixture, 200),
          tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
          clock: clock,
          store: store,
        );

        await repo.fetchCategoryByGroup('stations');

        final ommKey = CacheKeyBuilder.forGroup(
          'stations',
          format: CelestrakFormat.omm,
        );
        store.evictOnNextRead(ommKey);
        clock.advance(const Duration(minutes: 30));

        await expectLater(
          repo.fetchCategoryByGroup('stations'),
          throwsA(isA<NetworkException>()),
        );
      });

      test('fetchByName: throws NetworkException on primary key eviction',
          () async {
        final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
        final store = _EvictingCacheStore();
        final repo = _repo(
          (_) async => http.Response(_nameIssOmmFixture, 200),
          tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
          clock: clock,
          store: store,
        );

        await repo.fetchByName('ISS');

        final ommKey = CacheKeyBuilder.forName(
          'ISS',
          format: CelestrakFormat.omm,
        );
        store.evictOnNextRead(ommKey);
        clock.advance(const Duration(minutes: 30));

        await expectLater(
          repo.fetchByName('ISS'),
          throwsA(isA<NetworkException>()),
        );
      });

      test('fetchByIntlDesignator: throws NetworkException on primary eviction',
          () async {
        final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
        final store = _EvictingCacheStore();
        final repo = _repo(
          (_) async => http.Response(_intdesOmmFixture, 200),
          tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
          clock: clock,
          store: store,
        );

        await repo.fetchByIntlDesignator('1998-067A');

        final ommKey = CacheKeyBuilder.forIntlDesignator(
          '1998-067A',
          format: CelestrakFormat.omm,
        );
        store.evictOnNextRead(ommKey);
        clock.advance(const Duration(minutes: 30));

        await expectLater(
          repo.fetchByIntlDesignator('1998-067A'),
          throwsA(isA<NetworkException>()),
        );
      });

      test('fetchByNoradId: throws NetworkException on primary key eviction',
          () async {
        final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
        final store = _EvictingCacheStore();
        final repo = _repo(
          (_) async => http.Response(_stationsTleFixture, 200),
          clock: clock,
          store: store,
        );

        // Prime TLE cache.
        await repo.fetchByNoradId(25544, format: CelestrakFormat.tle);

        final tleKey = CacheKeyBuilder.forNoradId(
          25544,
          format: CelestrakFormat.tle,
        );
        store.evictOnNextRead(tleKey);
        clock.advance(const Duration(minutes: 30));

        await expectLater(
          repo.fetchByNoradId(25544, format: CelestrakFormat.tle),
          throwsA(isA<NetworkException>()),
        );
      });
    },
  );

  // ── _tleBodyFor — CacheMissException when fromCache=true ─────────────────

  group('TleRepositoryImpl._tleBodyFor — fromCache=true with evicted TLE key',
      () {
    test('throws CacheMissException via forceCache when TLE sub-key absent',
        () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = _TleSubKeyEvictingStore();

      final repo = _repo(
        (_) async => http.Response(_issOmmFixture, 200),
        tleHandler: (_) async => http.Response(_issTleFixture, 200),
        clock: clock,
        store: store,
      );

      // Prime both OMM and TLE keys.
      await repo.fetchByNoradId(25544);

      // Block only the TLE sub-key on next read.
      final tleKey = CacheKeyBuilder.forNoradId(
        25544,
        format: CelestrakFormat.tle,
      );
      store.blockReadsFor(tleKey);

      // Request via forceCache=true — OMM key present but TLE key absent.
      await expectLater(
        repo.fetchByNoradId(25544, forceCache: true),
        throwsA(isA<CacheMissException>()),
      );
    });
  });

  // ── _tleBodyFor — NetworkException fallback to empty lines ───────────────

  group('TleRepositoryImpl._tleBodyFor — NetworkException → empty lines', () {
    test(
      'OMM fetch succeeds but TLE fetch fails with NetworkException — '
      'returns result with empty lines',
      () async {
        final repo = _repo(
          (_) async => http.Response(_issOmmFixture, 200),
          tleHandler: (_) async => http.Response('server error', 503),
          maxAttempts: 1,
        );

        // Should not throw — NetworkException from TLE fetch is swallowed;
        // the stitcher falls back to empty strings for line1/line2.
        final tle = await repo.fetchByNoradId(25544);

        expect(tle.noradId, 25544);
        expect(tle.line1, isEmpty);
        expect(tle.line2, isEmpty);
      },
    );
  });

  // ── _fetchAndCacheCategory: TLE fetch CelestrakException fallback ─────────

  group(
    'TleRepositoryImpl.fetchCategory — supplementary TLE fetch fails',
    () {
      test(
        'CelestrakException on supplementary TLE fetch returns results '
        'with empty TLE lines (does not throw)',
        () async {
          // OMM fetch succeeds; supplementary TLE fetch fails.
          // Repository falls back to empty tleBody and returns records with
          // blank line1/line2 (stitcher _stitchWithEmptyLines path).
          final repo = _repo(
            (_) async => http.Response(_stationsOmmFixture, 200),
            tleHandler: (_) async => http.Response('server error', 503),
            maxAttempts: 1,
          );

          final results = await repo.fetchCategory(SatelliteCategory.stations);

          expect(results, isNotEmpty);
          for (final r in results) {
            expect(r.noradId, isPositive);
          }
          // Verify the stitch produced empty lines rather than throwing or
          // filling in garbage values.
          expect(results.first.line1, isEmpty);
          expect(results.first.line2, isEmpty);
        },
      );
    },
  );

  // ── _fetchAndCacheGroup: TLE fetch CelestrakException fallback ───────────

  group(
    'TleRepositoryImpl.fetchCategoryByGroup — supplementary TLE fetch fails',
    () {
      test(
        'CelestrakException on supplementary TLE fetch does not throw',
        () async {
          final repo = _repo(
            (_) async => http.Response(_stationsOmmFixture, 200),
            tleHandler: (_) async => http.Response('server error', 503),
            maxAttempts: 1,
          );

          final results = await repo.fetchCategoryByGroup('stations');

          expect(results, isNotEmpty);
        },
      );
    },
  );

  // ── _fetchAndCacheName: TLE fetch CelestrakException fallback ────────────

  group(
    'TleRepositoryImpl.fetchByName — supplementary TLE fetch fails',
    () {
      test(
        'CelestrakException on supplementary TLE fetch does not throw',
        () async {
          final repo = _repo(
            (_) async => http.Response(_nameIssOmmFixture, 200),
            tleHandler: (_) async => http.Response('server error', 503),
            maxAttempts: 1,
          );

          final results = await repo.fetchByName('ISS');

          expect(results, isNotEmpty);
        },
      );
    },
  );

  // ── _fetchAndCacheIntlDes: TLE fetch CelestrakException fallback ──────────

  group(
    'TleRepositoryImpl.fetchByIntlDesignator — supplementary TLE fetch fails',
    () {
      test(
        'CelestrakException on supplementary TLE fetch does not throw',
        () async {
          final repo = _repo(
            (_) async => http.Response(_intdesOmmFixture, 200),
            tleHandler: (_) async => http.Response('server error', 503),
            maxAttempts: 1,
          );

          final results = await repo.fetchByIntlDesignator('1998-067A');

          expect(results, isNotEmpty);
        },
      );
    },
  );

  // ── _parseTleInIsolate: fromCache=true branch (useIsolate + TLE cache hit) ─

  group(
    'TleRepositoryImpl._parseTleInIsolate — fromCache=true (useIsolate path)',
    () {
      test(
        'useIsolate=true TLE format cache hit returns source=local records',
        () async {
          final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_stationsTleFixture, 200),
            clock: clock,
            store: store,
            useIsolate: true,
          );

          // Prime the TLE cache.
          await repo.fetchCategory(
            SatelliteCategory.stations,
            format: CelestrakFormat.tle,
          );

          // Cache hit path — exercises _parseTleInIsolate with fromCache=true.
          clock.advance(const Duration(minutes: 30));
          final results = await repo.fetchCategory(
            SatelliteCategory.stations,
            format: CelestrakFormat.tle,
          );

          expect(results, isNotEmpty);
          for (final r in results) {
            expect(r.source, equals(TleSource.local));
          }
        },
      );
    },
  );
}
