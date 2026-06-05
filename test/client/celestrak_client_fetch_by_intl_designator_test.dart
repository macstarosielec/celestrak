import 'package:celestrak/celestrak.dart';
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
  int maxAttempts = 1,
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
    maxAttempts: maxAttempts,
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

  group('CelestrakClient.fetchByIntlDesignator — happy path', () {
    test('returns non-empty list for a valid designator', () async {
      final client = _client(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
      );

      final results = await client.fetchByIntlDesignator('1998-067A');

      expect(results, isNotEmpty);
    });

    test('result contains ISS (noradId=25544)', () async {
      final client = _client(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
      );

      final results = await client.fetchByIntlDesignator('1998-067A');
      final noradIds = results.map((r) => r.noradId).toList();

      expect(noradIds, contains(25544));
    });

    test('stamps source=celestrak on remote fetch', () async {
      final client = _client(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
      );

      final results = await client.fetchByIntlDesignator('1998-067A');

      for (final r in results) {
        expect(r.source, equals(TleSource.celestrak));
      }
    });

    test('passes designator verbatim in INTDES= query parameter', () async {
      String? capturedIntdes;
      final client = _client(
        (req) async {
          capturedIntdes = req.url.queryParameters['INTDES'];
          return http.Response(_intdesOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
      );

      await client.fetchByIntlDesignator('1998-067A');

      expect(capturedIntdes, equals('1998-067A'));
    });
  });

  // ── No-match → empty list ─────────────────────────────────────────────────

  group('CelestrakClient.fetchByIntlDesignator — no match', () {
    test('returns empty list when no satellite matches', () async {
      final client = _client(
        (_) async => http.Response('No GP data found', 200),
      );

      final results = await client.fetchByIntlDesignator('1998-067A');

      expect(results, isEmpty);
    });

    test('no match does not throw — returns [] instead', () async {
      final client = _client(
        (_) async => http.Response('No GP data found', 200),
      );

      await expectLater(
        client.fetchByIntlDesignator('1998-067A'),
        completes,
      );
    });
  });

  // ── Malformed designator → ArgumentError (FR-4) ───────────────────────────

  group(
      'CelestrakClient.fetchByIntlDesignator — '
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
        final client = _client(
          (_) async => http.Response(_intdesOmmFixture, 200),
        );

        await expectLater(
          client.fetchByIntlDesignator(bad),
          throwsA(isA<ArgumentError>()),
        );
      });
    }

    test('ArgumentError.name is "intlDesignator"', () async {
      final client = _client(
        (_) async => http.Response(_intdesOmmFixture, 200),
      );

      await expectLater(
        client.fetchByIntlDesignator('bad'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            equals('intlDesignator'),
          ),
        ),
      );
    });
  });

  // ── Cache behaviour (FR-12) ────────────────────────────────────────────────

  group('CelestrakClient.fetchByIntlDesignator — caching (FR-12)', () {
    test('second call within TTL does not issue transport call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async {
          calls++;
          return http.Response(_intdesOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByIntlDesignator('1998-067A');
      clock.advance(const Duration(minutes: 30));
      await client.fetchByIntlDesignator('1998-067A');

      expect(calls, equals(1));
    });

    test('cache hit stamps source=local', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByIntlDesignator('1998-067A');
      clock.advance(const Duration(minutes: 30));
      final results = await client.fetchByIntlDesignator('1998-067A');

      for (final r in results) {
        expect(r.source, equals(TleSource.local));
      }
    });

    test('cache miss after TTL expiry issues new transport call', () async {
      var calls = 0;
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async {
          calls++;
          return http.Response(_intdesOmmFixture, 200);
        },
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        clock: clock,
        store: store,
        defaultTtl: const Duration(hours: 2),
      );

      await client.fetchByIntlDesignator('1998-067A');
      clock.advance(const Duration(hours: 2, seconds: 1));
      await client.fetchByIntlDesignator('1998-067A');

      expect(calls, greaterThanOrEqualTo(2));
    });
  });

  // ── intlDesignatorAge ─────────────────────────────────────────────────────

  group('CelestrakClient.intlDesignatorAge', () {
    test('returns null before any fetch', () async {
      final client = _client(
        (_) async => http.Response(_intdesOmmFixture, 200),
      );

      final age = await client.intlDesignatorAge('1998-067A');

      expect(age, isNull);
    });

    test('returns Duration after fetch', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByIntlDesignator('1998-067A');
      clock.advance(const Duration(minutes: 20));

      final age = await client.intlDesignatorAge('1998-067A');

      expect(age, equals(const Duration(minutes: 20)));
    });

    test('returns null after clearCache', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_intdesOmmFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        clock: clock,
        store: store,
      );

      await client.fetchByIntlDesignator('1998-067A');
      await client.clearCache();

      final age = await client.intlDesignatorAge('1998-067A');

      expect(age, isNull);
    });
  });

  // ── allowStale (FR-17) ────────────────────────────────────────────────────

  group('CelestrakClient.fetchByIntlDesignator — allowStale (FR-17)', () {
    test('allowStale:true returns stale cache when network fails', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1, 14));
      final store = MemoryCacheStore();
      var fail = false;
      final client = _client(
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

      await client.fetchByIntlDesignator('1998-067A');
      clock.advance(const Duration(hours: 3));
      fail = true;

      final results = await client.fetchByIntlDesignator(
        '1998-067A',
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

      await client.fetchByIntlDesignator('1998-067A');
      clock.advance(const Duration(hours: 3));
      fail = true;

      await expectLater(
        client.fetchByIntlDesignator('1998-067A', allowStale: false),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
        'allowStale:true with no prior cache entry re-throws original '
        'NetworkException', () async {
      final client = _client(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      await expectLater(
        client.fetchByIntlDesignator('1998-067A', allowStale: true),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // ── Error paths ────────────────────────────────────────────────────────────

  group('CelestrakClient.fetchByIntlDesignator — error paths', () {
    test('NetworkException propagates on transport error', () async {
      final client = _client(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      await expectLater(
        client.fetchByIntlDesignator('1998-067A'),
        throwsA(isA<NetworkException>()),
      );
    });

    test('NetworkException.statusCode is set on HTTP error response', () async {
      final client = _client(
        (_) async => http.Response('server error', 503),
        maxAttempts: 1,
      );

      try {
        await client.fetchByIntlDesignator('1998-067A');
        fail('expected NetworkException');
      } on NetworkException catch (e) {
        expect(e.statusCode, equals(503));
      }
    });
  });

  // ── TLE format ────────────────────────────────────────────────────────────

  group('CelestrakClient.fetchByIntlDesignator — TLE format', () {
    test('returns list when format:tle', () async {
      final client = _client(
        (_) async => http.Response(_intdesTleFixture, 200),
        defaultFormat: CelestrakFormat.tle,
      );

      final results = await client.fetchByIntlDesignator('1998-067A');

      expect(results, isNotEmpty);
    });

    test('format override respected per call', () async {
      final store = MemoryCacheStore();
      final client = _client(
        (_) async => http.Response(_intdesTleFixture, 200),
        tleHandler: (_) async => http.Response(_intdesTleFixture, 200),
        store: store,
        defaultFormat: CelestrakFormat.omm,
      );

      final results = await client.fetchByIntlDesignator(
        '1998-067A',
        format: CelestrakFormat.tle,
      );

      for (final r in results) {
        expect(r.omm, isNull);
      }
    });
  });
}
