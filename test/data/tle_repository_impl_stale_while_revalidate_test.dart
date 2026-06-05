/// CEL-51: Stale-while-revalidate semantics (FR-17).
///
/// Acceptance criteria verified here:
///   1. Refresh-on-success: TTL-expired + network OK → refresh cache and
///      return fresh record (source == celestrak).
///   2. Stale-on-failure: TTL-expired + network fail + allowStale → return
///      stale entry flagged as stale (source == local, isStale() == true).
///
/// All five fetch methods are exercised: fetchByNoradId, fetchCategory,
/// fetchCategoryByGroup, fetchByName, and fetchByIntlDesignator.
library;

import 'package:celestrak/celestrak.dart';
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

late String _issOmmFixture;
late String _issTleFixture;
late String _stationsOmmFixture;
late String _stationsTleFixture;
late String _nameIssOmmFixture;
late String _nameIssTleFixture;
late String _intdesOmmFixture;
late String _intdesTleFixture;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testBase = 'https://celestrak.test/gp.php';

/// Clock starts at a fixed UTC instant so tests are fully deterministic.
final _t0 = DateTime.utc(2026, 6, 1, 14);

/// Duration that advances the clock past TTL but NOT past the 3-day
/// stale threshold, so [SatelliteTle.isStale] returns true only after
/// advancing by [_staleOffset].
const _ttlOffset = Duration(hours: 3); // beyond _defaultTtl

/// Duration that advances the clock past both TTL and the 3-day
/// staleThreshold so [SatelliteTle.isStale] returns true.
const _staleOffset = Duration(days: 4);

/// Creates a [TleRepositoryImpl] backed by a [MockClient] and a fresh
/// [MemoryCacheStore] with a controllable [FakeClock].
///
/// [ommHandler] handles `FORMAT=JSON` requests; [tleHandler] handles
/// `FORMAT=TLE` requests (defaults to [ommHandler]).
TleRepositoryImpl _repo(
  MockClientHandler ommHandler, {
  required FakeClock clock,
  required MemoryCacheStore store,
  MockClientHandler? tleHandler,
  int maxAttempts = 1,
}) =>
    TleRepositoryImpl(
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
          timeout: const Duration(seconds: 10),
        ),
        baseUrl: _testBase,
      ),
      cacheStore: store,
      clock: clock,
    );

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

  // ── fetchByNoradId ─────────────────────────────────────────────────────────

  group(
    'stale-while-revalidate (FR-17) — fetchByNoradId: refresh-on-success',
    () {
      test(
        'TTL-expired + network OK → source==celestrak (fresh record returned)',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_issOmmFixture, 200),
            tleHandler: (_) async => http.Response(_issTleFixture, 200),
            clock: clock,
            store: store,
          );

          // Prime the cache.
          await repo.fetchByNoradId(25544);

          // Expire the cache; network is still healthy.
          clock.advance(_ttlOffset);

          final refreshed = await repo.fetchByNoradId(25544);

          expect(
            refreshed.source,
            equals(TleSource.celestrak),
            reason: 'TTL-expired + network OK must return a fresh record '
                'with source=celestrak',
          );
        },
      );

      test(
        'TTL-expired + network OK → cache is updated (third call is a hit)',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          var calls = 0;
          final repo = _repo(
            (_) async {
              calls++;
              return http.Response(_issOmmFixture, 200);
            },
            tleHandler: (_) async => http.Response(_issTleFixture, 200),
            clock: clock,
            store: store,
          );

          // Call 1: prime the cache.
          await repo.fetchByNoradId(25544);
          // Expire the TTL.
          clock.advance(_ttlOffset);
          // Call 2: TTL-expired + network OK → should fetch and refresh cache.
          await repo.fetchByNoradId(25544);
          // Call 3: within the new TTL → must be a cache hit.
          clock.advance(const Duration(minutes: 5));
          await repo.fetchByNoradId(25544);

          // Calls 1 and 2 go to the network; call 3 is served from the
          // refreshed cache.
          expect(
            calls,
            equals(2),
            reason: 'cache must be refreshed after revalidation so the '
                'subsequent call is a hit',
          );
        },
      );

      test(
        'TTL-expired + network OK → fetchedAt updated to revalidation time',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_issOmmFixture, 200),
            tleHandler: (_) async => http.Response(_issTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByNoradId(25544);
          clock.advance(_ttlOffset);

          final refreshed = await repo.fetchByNoradId(25544);

          expect(
            refreshed.fetchedAt,
            equals(_t0.add(_ttlOffset)),
            reason: 'fetchedAt must reflect the revalidation timestamp, not '
                'the original prime timestamp',
          );
        },
      );
    },
  );

  group(
    'stale-while-revalidate (FR-17) — fetchByNoradId: stale-on-failure',
    () {
      test(
        'TTL-expired + network fail + allowStale:true → source==local',
        () async {
          final clock = FakeClock(_t0);
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
          clock.advance(_staleOffset);
          fail = true;

          final stale = await repo.fetchByNoradId(25544, allowStale: true);

          expect(
            stale.source,
            equals(TleSource.local),
            reason: 'network fail + allowStale must return stale entry with '
                'source=local',
          );
        },
      );

      test(
        'TTL-expired + network fail + allowStale:true → isStale() is true',
        () async {
          final clock = FakeClock(_t0);
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
          clock.advance(_staleOffset);
          fail = true;

          final stale = await repo.fetchByNoradId(25544, allowStale: true);

          expect(
            stale.isStale(now: clock.now),
            isTrue,
            reason: 'stale-flagged record must report isStale=true relative '
                'to the revalidation time',
          );
        },
      );
    },
  );

  // ── fetchCategory ──────────────────────────────────────────────────────────

  group(
    'stale-while-revalidate (FR-17) — fetchCategory: refresh-on-success',
    () {
      test(
        'TTL-expired + network OK → all records have source==celestrak',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_stationsOmmFixture, 200),
            tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchCategory(SatelliteCategory.stations);
          clock.advance(_ttlOffset);

          final refreshed =
              await repo.fetchCategory(SatelliteCategory.stations);

          expect(refreshed, isNotEmpty);
          for (final r in refreshed) {
            expect(
              r.source,
              equals(TleSource.celestrak),
              reason:
                  'fresh fetch after TTL expiry must stamp source=celestrak',
            );
          }
        },
      );

      test(
        'TTL-expired + network OK → cache updated (third call is a hit)',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          var ommCalls = 0;
          final repo = _repo(
            (_) async {
              ommCalls++;
              return http.Response(_stationsOmmFixture, 200);
            },
            tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchCategory(SatelliteCategory.stations);
          clock.advance(_ttlOffset);
          await repo.fetchCategory(SatelliteCategory.stations);
          clock.advance(const Duration(minutes: 5));
          await repo.fetchCategory(SatelliteCategory.stations);

          expect(
            ommCalls,
            equals(2),
            reason: 'only two network fetches expected: prime + revalidate',
          );
        },
      );
    },
  );

  group(
    'stale-while-revalidate (FR-17) — fetchCategory: stale-on-failure',
    () {
      test(
        'TTL-expired + network fail + allowStale:true → isStale() is true',
        () async {
          final clock = FakeClock(_t0);
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
          clock.advance(_staleOffset);
          fail = true;

          final results = await repo.fetchCategory(
            SatelliteCategory.stations,
            allowStale: true,
          );

          expect(results, isNotEmpty);
          for (final r in results) {
            expect(r.source, equals(TleSource.local));
            expect(
              r.isStale(now: clock.now),
              isTrue,
              reason: 'stale-flagged records must report isStale=true',
            );
          }
        },
      );
    },
  );

  // ── fetchCategoryByGroup ───────────────────────────────────────────────────

  group(
    'stale-while-revalidate (FR-17) — fetchCategoryByGroup: refresh-on-success',
    () {
      test(
        'TTL-expired + network OK → all records have source==celestrak',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_stationsOmmFixture, 200),
            tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchCategoryByGroup('stations');
          clock.advance(_ttlOffset);

          final refreshed = await repo.fetchCategoryByGroup('stations');

          expect(refreshed, isNotEmpty);
          for (final r in refreshed) {
            expect(r.source, equals(TleSource.celestrak));
          }
        },
      );
    },
  );

  group(
    'stale-while-revalidate (FR-17) — fetchCategoryByGroup: stale-on-failure',
    () {
      test(
        'TTL-expired + network fail + allowStale:true → isStale() is true',
        () async {
          final clock = FakeClock(_t0);
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
          clock.advance(_staleOffset);
          fail = true;

          final results = await repo.fetchCategoryByGroup(
            'stations',
            allowStale: true,
          );

          expect(results, isNotEmpty);
          for (final r in results) {
            expect(r.source, equals(TleSource.local));
            expect(r.isStale(now: clock.now), isTrue);
          }
        },
      );
    },
  );

  // ── fetchByName ────────────────────────────────────────────────────────────

  group(
    'stale-while-revalidate (FR-17) — fetchByName: refresh-on-success',
    () {
      test(
        'TTL-expired + network OK → all records have source==celestrak',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_nameIssOmmFixture, 200),
            tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByName('ISS');
          clock.advance(_ttlOffset);

          final refreshed = await repo.fetchByName('ISS');

          expect(refreshed, isNotEmpty);
          for (final r in refreshed) {
            expect(r.source, equals(TleSource.celestrak));
          }
        },
      );
    },
  );

  group(
    'stale-while-revalidate (FR-17) — fetchByName: stale-on-failure',
    () {
      test(
        'TTL-expired + network fail + allowStale:true → isStale() is true',
        () async {
          final clock = FakeClock(_t0);
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
          clock.advance(_staleOffset);
          fail = true;

          final results = await repo.fetchByName('ISS', allowStale: true);

          expect(results, isNotEmpty);
          for (final r in results) {
            expect(r.source, equals(TleSource.local));
            expect(r.isStale(now: clock.now), isTrue);
          }
        },
      );
    },
  );

  // ── fetchByIntlDesignator ──────────────────────────────────────────────────

  group(
    'stale-while-revalidate (FR-17) — fetchByIntlDesignator: '
    'refresh-on-success',
    () {
      test(
        'TTL-expired + network OK → all records have source==celestrak',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_intdesOmmFixture, 200),
            tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByIntlDesignator('1998-067A');
          clock.advance(_ttlOffset);

          final refreshed = await repo.fetchByIntlDesignator('1998-067A');

          expect(refreshed, isNotEmpty);
          for (final r in refreshed) {
            expect(r.source, equals(TleSource.celestrak));
          }
        },
      );
    },
  );

  group(
    'stale-while-revalidate (FR-17) — fetchByIntlDesignator: stale-on-failure',
    () {
      test(
        'TTL-expired + network fail + allowStale:true → isStale() is true',
        () async {
          final clock = FakeClock(_t0);
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
          clock.advance(_staleOffset);
          fail = true;

          final results = await repo.fetchByIntlDesignator(
            '1998-067A',
            allowStale: true,
          );

          expect(results, isNotEmpty);
          for (final r in results) {
            expect(r.source, equals(TleSource.local));
            expect(r.isStale(now: clock.now), isTrue);
          }
        },
      );
    },
  );

  // ── fetchByNoradId (TLE format) ────────────────────────────────────────────

  group(
    'stale-while-revalidate (FR-17) — fetchByNoradId TLE format: '
    'refresh-on-success',
    () {
      test(
        'TTL-expired + network OK + TLE format → source==celestrak',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_issTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByNoradId(25544, format: CelestrakFormat.tle);
          clock.advance(_ttlOffset);

          final refreshed = await repo.fetchByNoradId(
            25544,
            format: CelestrakFormat.tle,
          );

          expect(refreshed.source, equals(TleSource.celestrak));
        },
      );
    },
  );

  group(
    'stale-while-revalidate (FR-17) — fetchByNoradId TLE format: '
    'stale-on-failure',
    () {
      test(
        'TTL-expired + network fail + allowStale:true + TLE format → '
        'source==local and isStale() is true',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          var fail = false;
          final repo = _repo(
            (_) async {
              if (fail) return http.Response('server error', 503);
              return http.Response(_issTleFixture, 200);
            },
            clock: clock,
            store: store,
          );

          await repo.fetchByNoradId(25544, format: CelestrakFormat.tle);
          clock.advance(_staleOffset);
          fail = true;

          final stale = await repo.fetchByNoradId(
            25544,
            format: CelestrakFormat.tle,
            allowStale: true,
          );

          expect(stale.source, equals(TleSource.local));
          expect(stale.isStale(now: clock.now), isTrue);
        },
      );
    },
  );
}
