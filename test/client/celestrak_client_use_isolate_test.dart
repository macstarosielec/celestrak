/// Tests for the `useIsolate` opt-in on [CelestrakClient].
///
/// The isolate path must return the same records as the synchronous path.
/// We test it via [CelestrakClient.withStore] with a [MemoryCacheStore] and
/// [MockClient] so the suite runs fully offline.
library;

import 'package:celestrak/celestrak.dart';
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
late String _starlinkOmmFixture;
late String _starlinkTleFixture;
late String _nameOmmFixture;
late String _nameTleFixture;
late String _intdesOmmFixture;
late String _intdesTleFixture;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [CelestrakClient] via [CelestrakClient.withStore] backed by a
/// [MemoryCacheStore] and [MockClient].
///
/// [useIsolate] is forwarded to the client; all other parameters use test
/// defaults.
CelestrakClient _client(
  MockClientHandler ommHandler, {
  MockClientHandler? tleHandler,
  bool useIsolate = false,
  MemoryCacheStore? store,
}) {
  final effectiveStore = store ?? MemoryCacheStore();
  final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));

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
    clock: clock,
    maxAttempts: 1,
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
    _starlinkOmmFixture = await loadFixture(
      'test/fixtures/starlink_multi_omm.json',
    );
    _starlinkTleFixture = await loadFixture(
      'test/fixtures/group_starlink.tle',
    );
    _nameOmmFixture = await loadFixture('test/fixtures/name_iss_omm.json');
    _nameTleFixture = await loadFixture('test/fixtures/name_iss.txt');
    _intdesOmmFixture = await loadFixture(
      'test/fixtures/intdes_1998_067a_omm.json',
    );
    _intdesTleFixture = await loadFixture(
      'test/fixtures/intdes_1998_067a.txt',
    );
  });

  // ── fetchCategory ──────────────────────────────────────────────────────────

  group('CelestrakClient(useIsolate: true).fetchCategory', () {
    test('returns the same records as the synchronous path', () async {
      Future<List<SatelliteTle>> fetch({required bool useIsolate}) {
        final client = _client(
          (_) async => http.Response(_stationsOmmFixture, 200),
          tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
          useIsolate: useIsolate,
        );
        return client.fetchCategory(SatelliteCategory.stations);
      }

      final syncResult = await fetch(useIsolate: false);
      final isoResult = await fetch(useIsolate: true);

      expect(isoResult.length, equals(syncResult.length));
      expect(
        isoResult.map((t) => t.noradId).toList(),
        equals(syncResult.map((t) => t.noradId).toList()),
      );
    });

    test('result is non-empty', () async {
      final client = _client(
        (_) async => http.Response(_stationsOmmFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        useIsolate: true,
      );

      final result = await client.fetchCategory(SatelliteCategory.stations);

      expect(result, isNotEmpty);
    });

    test('source is TleSource.celestrak on fresh fetch', () async {
      final client = _client(
        (_) async => http.Response(_stationsOmmFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        useIsolate: true,
      );

      final result = await client.fetchCategory(SatelliteCategory.stations);

      expect(result.every((t) => t.source == TleSource.celestrak), isTrue);
    });

    test('source is TleSource.local on cache hit', () async {
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_stationsOmmFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        useIsolate: true,
        store: store,
      );

      // Warm the cache.
      await client.fetchCategory(SatelliteCategory.stations);

      // Reuse same store — second call is a cache hit.
      final client2 = _client(
        (_) async => http.Response('', 500), // must not be called
        useIsolate: true,
        store: store,
      );
      final result = await client2.fetchCategory(SatelliteCategory.stations);

      expect(result.every((t) => t.source == TleSource.local), isTrue);
    });
  });

  // ── fetchCategoryByGroup ───────────────────────────────────────────────────

  group('CelestrakClient(useIsolate: true).fetchCategoryByGroup', () {
    test('returns the same records as the synchronous path', () async {
      Future<List<SatelliteTle>> fetch({required bool useIsolate}) {
        final client = _client(
          (_) async => http.Response(_starlinkOmmFixture, 200),
          tleHandler: (_) async => http.Response(_starlinkTleFixture, 200),
          useIsolate: useIsolate,
        );
        return client.fetchCategoryByGroup('starlink');
      }

      final syncResult = await fetch(useIsolate: false);
      final isoResult = await fetch(useIsolate: true);

      expect(isoResult.length, equals(syncResult.length));
    });
  });

  // ── fetchByName ────────────────────────────────────────────────────────────

  group('CelestrakClient(useIsolate: true).fetchByName', () {
    test('returns the same records as the synchronous path', () async {
      Future<List<SatelliteTle>> fetch({required bool useIsolate}) {
        final client = _client(
          (_) async => http.Response(_nameOmmFixture, 200),
          tleHandler: (_) async => http.Response(_nameTleFixture, 200),
          useIsolate: useIsolate,
        );
        return client.fetchByName('ISS');
      }

      final syncResult = await fetch(useIsolate: false);
      final isoResult = await fetch(useIsolate: true);

      expect(isoResult.length, equals(syncResult.length));
      if (syncResult.isNotEmpty) {
        expect(isoResult.first.noradId, equals(syncResult.first.noradId));
      }
    });
  });

  // ── fetchByIntlDesignator ──────────────────────────────────────────────────

  group('CelestrakClient(useIsolate: true).fetchByIntlDesignator', () {
    test('returns the same records as the synchronous path', () async {
      Future<List<SatelliteTle>> fetch({required bool useIsolate}) {
        final client = _client(
          (_) async => http.Response(_intdesOmmFixture, 200),
          tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
          useIsolate: useIsolate,
        );
        return client.fetchByIntlDesignator('1998-067A');
      }

      final syncResult = await fetch(useIsolate: false);
      final isoResult = await fetch(useIsolate: true);

      expect(isoResult.length, equals(syncResult.length));
      if (syncResult.isNotEmpty) {
        expect(isoResult.first.noradId, equals(syncResult.first.noradId));
      }
    });

    test('result is non-empty', () async {
      final client = _client(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        useIsolate: true,
      );

      final result = await client.fetchByIntlDesignator('1998-067A');

      expect(result, isNotEmpty);
    });
  });

  // ── TLE format with useIsolate ─────────────────────────────────────────────

  group('CelestrakClient(useIsolate: true) with CelestrakFormat.tle', () {
    test('fetchCategory TLE format returns same records as synchronous path',
        () async {
      Future<List<SatelliteTle>> fetch({required bool useIsolate}) {
        final client = _client(
          (_) async => http.Response(_stationsOmmFixture, 200),
          tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
          useIsolate: useIsolate,
        );
        return client.fetchCategory(
          SatelliteCategory.stations,
          format: CelestrakFormat.tle,
        );
      }

      final syncResult = await fetch(useIsolate: false);
      final isoResult = await fetch(useIsolate: true);

      expect(isoResult.length, equals(syncResult.length));
      expect(
        isoResult.map((t) => t.noradId).toList(),
        equals(syncResult.map((t) => t.noradId).toList()),
      );
    });

    test('fetchCategoryByGroup TLE format result is non-empty', () async {
      final client = _client(
        (_) async => http.Response(_starlinkOmmFixture, 200),
        tleHandler: (_) async => http.Response(_starlinkTleFixture, 200),
        useIsolate: true,
      );

      final result = await client.fetchCategoryByGroup(
        'starlink',
        format: CelestrakFormat.tle,
      );

      expect(result, isNotEmpty);
    });
  });

  // ── TleRepositoryImpl.useIsolate wiring ───────────────────────────────────

  group('CelestrakClient useIsolate constructor parameter', () {
    test('useIsolate defaults to false (synchronous path)', () async {
      // Verify that a client without useIsolate produces correct results.
      final client = _client(
        (_) async => http.Response(_stationsOmmFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
      );

      final result = await client.fetchCategory(SatelliteCategory.stations);

      expect(result, isNotEmpty);
    });

    test('useIsolate: true and useIsolate: false yield identical noradIds',
        () async {
      final store1 = MemoryCacheStore();
      final store2 = MemoryCacheStore();

      final syncClient = _client(
        (_) async => http.Response(_stationsOmmFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        store: store1,
      );
      final isoClient = _client(
        (_) async => http.Response(_stationsOmmFixture, 200),
        tleHandler: (_) async => http.Response(_stationsTleFixture, 200),
        useIsolate: true,
        store: store2,
      );

      final syncIds =
          (await syncClient.fetchCategory(SatelliteCategory.stations))
              .map((t) => t.noradId)
              .toSet();
      final isoIds = (await isoClient.fetchCategory(SatelliteCategory.stations))
          .map((t) => t.noradId)
          .toSet();

      expect(isoIds, equals(syncIds));
    });
  });
}
