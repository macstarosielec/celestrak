/// CEL-52: Stale marking and local source on cache hits (FR-16).
///
/// Acceptance criteria:
///   1. Every cache hit stamps `source == TleSource.local` — never
///      `TleSource.celestrak` — regardless of whether the orbital data is
///      fresh or stale relative to `staleThreshold`.
///   2. `SatelliteTle.isStale()` returns the correct value when supplied with
///      the current fake-clock time and a custom `staleThreshold`, proving
///      staleness is computable from the returned record.
///   3. A cache-hit record that is older than `staleThreshold` is NEVER
///      returned as if it were fresh (`source` remains `local`, `isStale`
///      remains `true`) — directly mitigating RK-7 silent-stale.
///   4. All five fetch methods are exercised: fetchByNoradId,
///      fetchCategory, fetchCategoryByGroup, fetchByName, and
///      fetchByIntlDesignator.
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
// Helpers
// ---------------------------------------------------------------------------

/// Base URL used for all test data sources.
const _testBase = 'https://celestrak.test/gp.php';

/// Default TTL used across all tests.
const _defaultTtl = Duration(hours: 2);

/// ISS epoch from `iss_25544_omm.json`.
final _issEpoch = DateTime.utc(2026, 6, 1, 13, 0, 0, 0, 288);

/// Clock starts 1 hour after the ISS epoch so the data is fresh by default.
final DateTime _t0 = _issEpoch.add(const Duration(hours: 1));

/// Advance past BOTH TTL and the 3-day staleThreshold so isStale() is true.
const _epochStaleOffset = Duration(days: 4);

/// Creates a [TleRepositoryImpl] wired to a [MockClient] and a fresh
/// [MemoryCacheStore] with a controllable [FakeClock].
///
/// [ommHandler] handles `FORMAT=JSON` requests.
/// [tleHandler] handles `FORMAT=TLE` requests (defaults to [ommHandler]).
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
    'FR-16 cache-hit staleness — fetchByNoradId',
    () {
      test(
        'cache hit within TTL stamps source=local',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_issOmmFixture, 200),
            tleHandler: (_) async => http.Response(_issTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByNoradId(25544, ttl: _defaultTtl);
          clock.advance(const Duration(minutes: 30));
          final hit = await repo.fetchByNoradId(25544, ttl: _defaultTtl);

          expect(
            hit.source,
            equals(TleSource.local),
            reason: 'cache hit within TTL must stamp source=local (FR-16)',
          );
        },
      );

      test(
        'cache hit within TTL: isStale false when epoch is recent',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_issOmmFixture, 200),
            tleHandler: (_) async => http.Response(_issTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByNoradId(25544, ttl: _defaultTtl);
          clock.advance(const Duration(minutes: 30));
          final hit = await repo.fetchByNoradId(25544, ttl: _defaultTtl);

          expect(
            hit.isStale(
              now: clock.now,
              staleThreshold: const Duration(days: 3),
            ),
            isFalse,
            reason: 'orbital data 1.5 h old is not stale at 3-day threshold',
          );
        },
      );

      test(
        'cache hit with old epoch: isStale true and source still local '
        '(RK-7 — never silently fresh)',
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
          await repo.fetchByNoradId(25544, ttl: _defaultTtl);

          // Advance past TTL so the repo re-fetches — but the fixture epoch
          // remains the same (ISS epoch from the fixture), and the clock is
          // now 4 days ahead of the epoch.
          clock.advance(_epochStaleOffset);
          final hit = await repo.fetchByNoradId(
            25544,
            ttl: const Duration(days: 10), // keep it in TTL
          );

          expect(
            hit.source,
            equals(TleSource.local),
            reason: 'cache hit must stay source=local regardless of epoch age',
          );
          expect(
            hit.isStale(
              now: clock.now,
              staleThreshold: const Duration(days: 3),
            ),
            isTrue,
            reason:
                'staleness must be surfaced — never silently treated as fresh '
                '(RK-7)',
          );
        },
      );

      test(
        'cache hit with old epoch: isStale respects custom staleThreshold',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_issOmmFixture, 200),
            tleHandler: (_) async => http.Response(_issTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByNoradId(25544, ttl: _defaultTtl);
          // Advance 2 hours — within 3-day default threshold but past 1-hour
          // custom threshold.
          clock.advance(const Duration(hours: 2));
          final hit = await repo.fetchByNoradId(
            25544,
            ttl: const Duration(days: 10),
          );

          expect(
            hit.isStale(
              now: clock.now,
              staleThreshold: const Duration(hours: 1),
            ),
            isTrue,
            reason: 'custom staleThreshold must be honoured on cache-hit '
                'records',
          );
          expect(
            hit.isStale(
              now: clock.now,
              staleThreshold: const Duration(days: 3),
            ),
            isFalse,
            reason: 'same record is fresh at the 3-day default threshold',
          );
        },
      );

      test(
        'TLE-format cache hit stamps source=local',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_issTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByNoradId(
            25544,
            format: CelestrakFormat.tle,
            ttl: _defaultTtl,
          );
          clock.advance(const Duration(minutes: 30));
          final hit = await repo.fetchByNoradId(
            25544,
            format: CelestrakFormat.tle,
            ttl: _defaultTtl,
          );

          expect(
            hit.source,
            equals(TleSource.local),
            reason: 'TLE-format cache hit must also stamp source=local',
          );
        },
      );
    },
  );

  // ── fetchCategory ──────────────────────────────────────────────────────────

  group(
    'FR-16 cache-hit staleness — fetchCategory',
    () {
      test(
        'cache hit stamps source=local on all records',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_stationsOmmFixture, 200),
            tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchCategory(
            SatelliteCategory.stations,
            ttl: _defaultTtl,
          );
          clock.advance(const Duration(minutes: 30));
          final hits = await repo.fetchCategory(
            SatelliteCategory.stations,
            ttl: _defaultTtl,
          );

          expect(hits, isNotEmpty);
          expect(
            hits.every((r) => r.source == TleSource.local),
            isTrue,
            reason: 'every record in a category cache hit must be source=local',
          );
        },
      );

      test(
        'stale-epoch records from cache: isStale true, source still local',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_stationsOmmFixture, 200),
            tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchCategory(
            SatelliteCategory.stations,
            ttl: _defaultTtl,
          );
          clock.advance(_epochStaleOffset);
          final hits = await repo.fetchCategory(
            SatelliteCategory.stations,
            ttl: const Duration(days: 10),
          );

          expect(hits, isNotEmpty);
          for (final hit in hits) {
            expect(
              hit.source,
              equals(TleSource.local),
              reason: 'source must remain local even when epoch is stale',
            );
            expect(
              hit.isStale(
                now: clock.now,
                staleThreshold: const Duration(days: 3),
              ),
              isTrue,
              reason: 'staleness must be surfaced, never silently fresh '
                  '(RK-7)',
            );
          }
        },
      );
    },
  );

  // ── fetchCategoryByGroup ───────────────────────────────────────────────────

  group(
    'FR-16 cache-hit staleness — fetchCategoryByGroup',
    () {
      test(
        'cache hit stamps source=local on all records',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_stationsOmmFixture, 200),
            tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);
          clock.advance(const Duration(minutes: 30));
          final hits =
              await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);

          expect(hits, isNotEmpty);
          expect(
            hits.every((r) => r.source == TleSource.local),
            isTrue,
            reason: 'every record in a group cache hit must be source=local',
          );
        },
      );

      test(
        'stale-epoch records from cache: isStale true, source still local',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_stationsOmmFixture, 200),
            tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchCategoryByGroup('stations', ttl: _defaultTtl);
          clock.advance(_epochStaleOffset);
          final hits = await repo.fetchCategoryByGroup(
            'stations',
            ttl: const Duration(days: 10),
          );

          expect(hits, isNotEmpty);
          for (final hit in hits) {
            expect(hit.source, equals(TleSource.local));
            expect(
              hit.isStale(
                now: clock.now,
                staleThreshold: const Duration(days: 3),
              ),
              isTrue,
              reason: 'staleness must be surfaced (RK-7)',
            );
          }
        },
      );
    },
  );

  // ── fetchByName ────────────────────────────────────────────────────────────

  group(
    'FR-16 cache-hit staleness — fetchByName',
    () {
      test(
        'cache hit stamps source=local on all records',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_nameIssOmmFixture, 200),
            tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByName('ISS', ttl: _defaultTtl);
          clock.advance(const Duration(minutes: 30));
          final hits = await repo.fetchByName('ISS', ttl: _defaultTtl);

          expect(hits, isNotEmpty);
          expect(
            hits.every((r) => r.source == TleSource.local),
            isTrue,
            reason: 'every record in a name cache hit must be source=local',
          );
        },
      );

      test(
        'stale-epoch records from cache: isStale true, source still local',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_nameIssOmmFixture, 200),
            tleHandler: (_) async => http.Response(_nameIssTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByName('ISS', ttl: _defaultTtl);
          clock.advance(_epochStaleOffset);
          final hits = await repo.fetchByName(
            'ISS',
            ttl: const Duration(days: 10),
          );

          expect(hits, isNotEmpty);
          for (final hit in hits) {
            expect(hit.source, equals(TleSource.local));
            expect(
              hit.isStale(
                now: clock.now,
                staleThreshold: const Duration(days: 3),
              ),
              isTrue,
              reason: 'staleness must be surfaced (RK-7)',
            );
          }
        },
      );
    },
  );

  // ── fetchByIntlDesignator ──────────────────────────────────────────────────

  group(
    'FR-16 cache-hit staleness — fetchByIntlDesignator',
    () {
      test(
        'cache hit stamps source=local on all records',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_intdesOmmFixture, 200),
            tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByIntlDesignator('1998-067A', ttl: _defaultTtl);
          clock.advance(const Duration(minutes: 30));
          final hits = await repo.fetchByIntlDesignator(
            '1998-067A',
            ttl: _defaultTtl,
          );

          expect(hits, isNotEmpty);
          expect(
            hits.every((r) => r.source == TleSource.local),
            isTrue,
            reason: 'every record in an intl-designator cache hit must be '
                'source=local',
          );
        },
      );

      test(
        'stale-epoch records from cache: isStale true, source still local',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_intdesOmmFixture, 200),
            tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchByIntlDesignator('1998-067A', ttl: _defaultTtl);
          clock.advance(_epochStaleOffset);
          final hits = await repo.fetchByIntlDesignator(
            '1998-067A',
            ttl: const Duration(days: 10),
          );

          expect(hits, isNotEmpty);
          for (final hit in hits) {
            expect(hit.source, equals(TleSource.local));
            expect(
              hit.isStale(
                now: clock.now,
                staleThreshold: const Duration(days: 3),
              ),
              isTrue,
              reason: 'staleness must be surfaced (RK-7)',
            );
          }
        },
      );
    },
  );

  // ── source invariant — never celestrak on a cache hit ─────────────────────

  group(
    'FR-16 RK-7 anti-regression — source is never celestrak on a cache hit',
    () {
      test(
        'fetchByNoradId second call returns source=local, not celestrak',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_issOmmFixture, 200),
            tleHandler: (_) async => http.Response(_issTleFixture, 200),
            clock: clock,
            store: store,
          );

          // First call populates the cache.
          final first = await repo.fetchByNoradId(25544, ttl: _defaultTtl);
          expect(first.source, equals(TleSource.celestrak));

          // Second call within TTL must be a local hit.
          clock.advance(const Duration(minutes: 5));
          final second = await repo.fetchByNoradId(25544, ttl: _defaultTtl);
          expect(
            second.source,
            isNot(equals(TleSource.celestrak)),
            reason: 'a cache hit must never be labelled celestrak — doing so '
                'would silently suppress staleness information (RK-7)',
          );
        },
      );

      test(
        'fetchCategory second call returns source=local, not celestrak',
        () async {
          final clock = FakeClock(_t0);
          final store = MemoryCacheStore();
          final repo = _repo(
            (_) async => http.Response(_stationsOmmFixture, 200),
            tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
            clock: clock,
            store: store,
          );

          await repo.fetchCategory(
            SatelliteCategory.stations,
            ttl: _defaultTtl,
          );
          clock.advance(const Duration(minutes: 5));
          final hits = await repo.fetchCategory(
            SatelliteCategory.stations,
            ttl: _defaultTtl,
          );

          expect(hits, isNotEmpty);
          expect(
            hits.any((r) => r.source == TleSource.celestrak),
            isFalse,
            reason: 'no record in a category cache hit must be source=celestrak'
                ' (RK-7)',
          );
        },
      );
    },
  );
}
