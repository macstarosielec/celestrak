import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException;

import 'package:celestrak/celestrak.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';
import '../support/fixture_loader.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

late String _issGpFixture;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns a [SpaceTrackClient] backed by a [MockClient].
///
/// [loginHandler] handles POST to the login endpoint (defaults to HTTP 200).
/// [dataHandler] handles GET data requests.
SpaceTrackClient _client(
  MockClientHandler dataHandler, {
  MockClientHandler? loginHandler,
  String baseUrl = 'https://spacetrack.test',
  Duration minRequestInterval = Duration.zero,
  FakeClock? clock,
}) {
  final effectiveClock = clock ?? FakeClock(DateTime.utc(2024, 1, 15, 12));

  return SpaceTrackClient.withClient(
    client: MockClient((request) async {
      if (request.url.path.contains('ajaxauth')) {
        return loginHandler != null
            ? loginHandler(request)
            : http.Response('', 200);
      }
      return dataHandler(request);
    }),
    identity: 'user@example.com',
    password: 'test-password',
    baseUrl: baseUrl,
    minRequestInterval: minRequestInterval,
    timeout: const Duration(seconds: 5),
    clock: effectiveClock,
  );
}

/// Runs [fn] and asserts it throws [AuthenticationException], returning it.
Future<AuthenticationException> _catchAuth(
  Future<void> Function() fn,
) async {
  try {
    await fn();
    fail('Expected AuthenticationException, but completed normally');
  } on AuthenticationException catch (e) {
    return e;
  }
}

/// Runs [fn] and asserts it throws [RateLimitException], returning it.
Future<RateLimitException> _catchRateLimit(
  Future<void> Function() fn,
) async {
  try {
    await fn();
    fail('Expected RateLimitException, but completed normally');
  } on RateLimitException catch (e) {
    return e;
  }
}

/// Runs [fn] and asserts it throws [NetworkException], returning it.
Future<NetworkException> _catchNetwork(Future<void> Function() fn) async {
  try {
    await fn();
    fail('Expected NetworkException, but completed normally');
  } on NetworkException catch (e) {
    return e;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    _issGpFixture = await loadFixture(
      'test/fixtures/spacetrack_iss_25544_gp.json',
    );
  });

  // ── SpaceTrackQuery ────────────────────────────────────────────────────────

  group('SpaceTrackQuery', () {
    test('byNoradId stores the noradId', () {
      final query = SpaceTrackQuery.byNoradId(25544);

      expect(query.noradId, 25544);
    });

    test('byNoradId throws ArgumentError when noradId < 1', () {
      expect(
        () => SpaceTrackQuery.byNoradId(0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('byNoradId throws ArgumentError when noradId is negative', () {
      expect(
        () => SpaceTrackQuery.byNoradId(-5),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('equality — same noradId are equal', () {
      expect(
        SpaceTrackQuery.byNoradId(25544),
        equals(SpaceTrackQuery.byNoradId(25544)),
      );
    });

    test('equality — different noradId are not equal', () {
      expect(
        SpaceTrackQuery.byNoradId(25544),
        isNot(equals(SpaceTrackQuery.byNoradId(99001))),
      );
    });

    test('hashCode is consistent with equality', () {
      expect(
        SpaceTrackQuery.byNoradId(25544).hashCode,
        equals(SpaceTrackQuery.byNoradId(25544).hashCode),
      );
    });

    test('toString contains the noradId', () {
      expect(
        SpaceTrackQuery.byNoradId(25544).toString(),
        contains('25544'),
      );
    });
  });

  // ── SpaceTrackClient — constructor / lifecycle ─────────────────────────────

  group('SpaceTrackClient — constructor', () {
    test('withClient — isLoggedIn is false before first fetch', () {
      final client = _client((_) async => http.Response(_issGpFixture, 200));
      addTearDown(client.dispose);

      expect(client.isLoggedIn, isFalse);
    });

    test('default constructor — dispose does not throw', () {
      final client = SpaceTrackClient(
        identity: 'user@example.com',
        password: 'secret',
      );

      expect(client.dispose, returnsNormally);
    });

    test('withClient — dispose does not close the external client', () async {
      var closeCalled = false;
      final trackingClient = _TrackingMockClient(
        (_) async => http.Response(_issGpFixture, 200),
        onClose: () => closeCalled = true,
      );

      SpaceTrackClient.withClient(
        client: trackingClient,
        identity: 'user@example.com',
        password: 'secret',
        baseUrl: 'https://spacetrack.test',
      ).dispose();

      expect(closeCalled, isFalse);
    });
  });

  // ── fetchByQuery — happy path ─────────────────────────────────────────────

  group('SpaceTrackClient.fetchByQuery() — happy path', () {
    test('returns SatelliteTle with correct noradId', () async {
      final client = _client(
        (_) async => http.Response(_issGpFixture, 200),
      );
      addTearDown(client.dispose);

      final tle = await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(tle.noradId, 25544);
    });

    test('stamps source == TleSource.spacetrack', () async {
      final client = _client(
        (_) async => http.Response(_issGpFixture, 200),
      );
      addTearDown(client.dispose);

      final tle = await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(tle.source, TleSource.spacetrack);
    });

    test('returns satellite name from fixture', () async {
      final client = _client(
        (_) async => http.Response(_issGpFixture, 200),
      );
      addTearDown(client.dispose);

      final tle = await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(tle.name, 'ISS (ZARYA)');
    });

    test('populates TLE line1 from fixture', () async {
      final client = _client(
        (_) async => http.Response(_issGpFixture, 200),
      );
      addTearDown(client.dispose);

      final tle = await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(tle.line1, isNotEmpty);
      expect(tle.line1, startsWith('1 '));
    });

    test('populates TLE line2 from fixture', () async {
      final client = _client(
        (_) async => http.Response(_issGpFixture, 200),
      );
      addTearDown(client.dispose);

      final tle = await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(tle.line2, isNotEmpty);
      expect(tle.line2, startsWith('2 '));
    });

    test('omm field is populated on result', () async {
      final client = _client(
        (_) async => http.Response(_issGpFixture, 200),
      );
      addTearDown(client.dispose);

      final tle = await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(tle.omm, isNotNull);
    });

    test('epoch is parsed from fixture EPOCH field', () async {
      final client = _client(
        (_) async => http.Response(_issGpFixture, 200),
      );
      addTearDown(client.dispose);

      final tle = await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));

      // Fixture EPOCH: 2024-01-15T10:30:00.000000
      expect(tle.epoch, DateTime.utc(2024, 1, 15, 10, 30));
    });

    test('sets isLoggedIn=true after first successful fetch', () async {
      final client = _client(
        (_) async => http.Response(_issGpFixture, 200),
      );
      addTearDown(client.dispose);

      await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(client.isLoggedIn, isTrue);
    });

    test('login is called once — second fetch skips login', () async {
      var loginCount = 0;
      final client = _client(
        (_) async => http.Response(_issGpFixture, 200),
        loginHandler: (_) async {
          loginCount++;
          return http.Response('', 200);
        },
      );
      addTearDown(client.dispose);

      await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));
      await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(loginCount, 1);
    });
  });

  // ── fetchByQuery — error paths ─────────────────────────────────────────────

  group('SpaceTrackClient.fetchByQuery() — error paths', () {
    test('throws SatelliteNotFoundException on empty array response', () async {
      final client = _client(
        (_) async => http.Response('[]', 200),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.fetchByQuery(SpaceTrackQuery.byNoradId(99999)),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });

    test('SatelliteNotFoundException.noradId matches the requested id',
        () async {
      final client = _client(
        (_) async => http.Response('[]', 200),
      );
      addTearDown(client.dispose);

      try {
        await client.fetchByQuery(SpaceTrackQuery.byNoradId(99999));
        fail('expected SatelliteNotFoundException');
      } on SatelliteNotFoundException catch (e) {
        expect(e.noradId, 99999);
      }
    });

    test('throws AuthenticationException on HTTP 401 during login', () async {
      final client = _client(
        (_) async => http.Response(_issGpFixture, 200),
        loginHandler: (_) async => http.Response('Unauthorized', 401),
      );
      addTearDown(client.dispose);

      final ex = await _catchAuth(
        () => client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.statusCode, 401);
    });

    test('throws AuthenticationException on HTTP 403 during data fetch',
        () async {
      final client = _client(
        (_) async => http.Response('Forbidden', 403),
      );
      addTearDown(client.dispose);

      final ex = await _catchAuth(
        () => client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.statusCode, 403);
    });

    test(
        'throws AuthenticationException on HTTP 401 from data fetch '
        'after a prior successful login (session expiry)', () async {
      // Login succeeds once; subsequent data requests return 401 to simulate
      // session expiry. loginCount must be 1 to confirm no retry is attempted.
      var loginCount = 0;
      var dataCallCount = 0;
      final client = _client(
        (_) async {
          dataCallCount++;
          // First data call succeeds; second simulates session expiry.
          if (dataCallCount == 1) return http.Response(_issGpFixture, 200);
          return http.Response('Unauthorized', 401);
        },
        loginHandler: (_) async {
          loginCount++;
          return http.Response('', 200);
        },
      );
      addTearDown(client.dispose);

      // First fetch establishes the session.
      await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));
      expect(loginCount, 1);
      expect(client.isLoggedIn, isTrue);

      // Second fetch: session expired mid-session — 401 propagates as
      // AuthenticationException without re-login attempt.
      final ex = await _catchAuth(
        () => client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.statusCode, 401);
      expect(loginCount, 1, reason: 'login must not be retried automatically');
    });

    test('throws RateLimitException on HTTP 429', () async {
      final client = _client(
        (_) async => http.Response('Too Many Requests', 429),
      );
      addTearDown(client.dispose);

      final ex = await _catchRateLimit(
        () => client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.uri?.path, contains('/NORAD_CAT_ID/25544'));
    });

    test('RateLimitException.retryAfter is parsed from Retry-After header',
        () async {
      final client = _client(
        (_) async => http.Response(
          'Too Many Requests',
          429,
          headers: {'retry-after': '60'},
        ),
      );
      addTearDown(client.dispose);

      final ex = await _catchRateLimit(
        () => client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.retryAfter, const Duration(seconds: 60));
    });

    test('throws NetworkException on HTTP 500', () async {
      final client = _client(
        (_) async => http.Response('Internal Server Error', 500),
      );
      addTearDown(client.dispose);

      final ex = await _catchNetwork(
        () => client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.statusCode, 500);
    });

    test('throws NetworkException on SocketException', () async {
      final client = _client(
        (_) async => throw const SocketException('Network unreachable'),
      );
      addTearDown(client.dispose);

      final ex = await _catchNetwork(
        () => client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.cause, isA<SocketException>());
    });

    test('throws NetworkException on TimeoutException', () async {
      final client = _client(
        (_) async => throw TimeoutException('timed out'),
      );
      addTearDown(client.dispose);

      final ex = await _catchNetwork(
        () => client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.cause, isA<TimeoutException>());
    });
  });

  // ── fetchedAt clock injection ──────────────────────────────────────────────

  group('SpaceTrackClient.fetchByQuery() — fetchedAt clock', () {
    test('fetchedAt matches the injected clock time', () async {
      final clock = FakeClock(DateTime.utc(2024, 6, 1, 9, 0, 0));
      final client = _client(
        (_) async => http.Response(_issGpFixture, 200),
        clock: clock,
      );
      addTearDown(client.dispose);

      final tle = await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(tle.fetchedAt, clock.now);
    });
  });

  // ── malformed GP records ───────────────────────────────────────────────────

  group('SpaceTrackClient.fetchByQuery() — malformed GP records', () {
    test('throws OmmParseException when TLE_LINE1 is absent', () async {
      const body = '''
[{
  "CCSDS_OMM_VERS": "2.0",
  "COMMENT": "GENERATED VIA SPACE-TRACK.ORG API",
  "CREATION_DATE": "2024-01-15T12:00:00.000000",
  "ORIGINATOR": "18 SDS",
  "OBJECT_NAME": "ISS (ZARYA)",
  "OBJECT_ID": "1998-067A",
  "CENTER_NAME": "EARTH",
  "REF_FRAME": "TEME",
  "TIME_SYSTEM": "UTC",
  "MEAN_ELEMENT_THEORY": "SGP4",
  "EPOCH": "2024-01-15T10:30:00.000000",
  "MEAN_MOTION": "15.49560691",
  "ECCENTRICITY": "0.00049420",
  "INCLINATION": "51.6411",
  "RA_OF_ASC_NODE": "123.4567",
  "ARG_OF_PERICENTER": "234.5678",
  "MEAN_ANOMALY": "345.6789",
  "EPHEMERIS_TYPE": "0",
  "CLASSIFICATION_TYPE": "U",
  "NORAD_CAT_ID": "25544",
  "ELEMENT_SET_NO": "999",
  "REV_AT_EPOCH": "12345",
  "BSTAR": "0.00012345",
  "MEAN_MOTION_DOT": "0.00001234",
  "MEAN_MOTION_DDOT": "0.0",
  "TLE_LINE2": "2 25544  51.6411 123.4567 0004942 234.5678 345.6789 15.49560691123455"
}]''';
      final client = _client((_) async => http.Response(body, 200));
      addTearDown(client.dispose);

      await expectLater(
        client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<OmmParseException>()),
      );
    });

    test('throws OmmParseException when TLE_LINE2 is absent', () async {
      const body = '''
[{
  "CCSDS_OMM_VERS": "2.0",
  "COMMENT": "GENERATED VIA SPACE-TRACK.ORG API",
  "CREATION_DATE": "2024-01-15T12:00:00.000000",
  "ORIGINATOR": "18 SDS",
  "OBJECT_NAME": "ISS (ZARYA)",
  "OBJECT_ID": "1998-067A",
  "CENTER_NAME": "EARTH",
  "REF_FRAME": "TEME",
  "TIME_SYSTEM": "UTC",
  "MEAN_ELEMENT_THEORY": "SGP4",
  "EPOCH": "2024-01-15T10:30:00.000000",
  "MEAN_MOTION": "15.49560691",
  "ECCENTRICITY": "0.00049420",
  "INCLINATION": "51.6411",
  "RA_OF_ASC_NODE": "123.4567",
  "ARG_OF_PERICENTER": "234.5678",
  "MEAN_ANOMALY": "345.6789",
  "EPHEMERIS_TYPE": "0",
  "CLASSIFICATION_TYPE": "U",
  "NORAD_CAT_ID": "25544",
  "ELEMENT_SET_NO": "999",
  "REV_AT_EPOCH": "12345",
  "BSTAR": "0.00012345",
  "MEAN_MOTION_DOT": "0.00001234",
  "MEAN_MOTION_DDOT": "0.0",
  "TLE_LINE1": "1 25544U 98067A   24015.43750000  .00001234  00000-0  12345-4 0  9990"
}]''';
      final client = _client((_) async => http.Response(body, 200));
      addTearDown(client.dispose);

      await expectLater(
        client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<OmmParseException>()),
      );
    });

    test('throws OmmParseException when TLE_LINE1 is empty string', () async {
      const body = '''
[{
  "CCSDS_OMM_VERS": "2.0",
  "COMMENT": "GENERATED VIA SPACE-TRACK.ORG API",
  "CREATION_DATE": "2024-01-15T12:00:00.000000",
  "ORIGINATOR": "18 SDS",
  "OBJECT_NAME": "ISS (ZARYA)",
  "OBJECT_ID": "1998-067A",
  "CENTER_NAME": "EARTH",
  "REF_FRAME": "TEME",
  "TIME_SYSTEM": "UTC",
  "MEAN_ELEMENT_THEORY": "SGP4",
  "EPOCH": "2024-01-15T10:30:00.000000",
  "MEAN_MOTION": "15.49560691",
  "ECCENTRICITY": "0.00049420",
  "INCLINATION": "51.6411",
  "RA_OF_ASC_NODE": "123.4567",
  "ARG_OF_PERICENTER": "234.5678",
  "MEAN_ANOMALY": "345.6789",
  "EPHEMERIS_TYPE": "0",
  "CLASSIFICATION_TYPE": "U",
  "NORAD_CAT_ID": "25544",
  "ELEMENT_SET_NO": "999",
  "REV_AT_EPOCH": "12345",
  "BSTAR": "0.00012345",
  "MEAN_MOTION_DOT": "0.00001234",
  "MEAN_MOTION_DDOT": "0.0",
  "TLE_LINE1": "",
  "TLE_LINE2": "2 25544  51.6411 123.4567 0004942 234.5678 345.6789 15.49560691123455"
}]''';
      final client = _client((_) async => http.Response(body, 200));
      addTearDown(client.dispose);

      await expectLater(
        client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<OmmParseException>()),
      );
    });
  });

  // ── dispose idempotency ────────────────────────────────────────────────────

  group('SpaceTrackClient — dispose idempotency', () {
    test('calling dispose twice on an owned-client instance does not throw',
        () {
      final client = SpaceTrackClient(
        identity: 'user@example.com',
        password: 'secret',
      );

      expect(client..dispose(), isA<void>());
      expect(client.dispose, returnsNormally);
    });
  });

  // ── rate limiting with fake clock ──────────────────────────────────────────

  group('SpaceTrackClient — rate limiting', () {
    test('minRequestInterval zero — two fetches complete without delay',
        () async {
      var callCount = 0;
      final client = _client((request) async {
        callCount++;
        return http.Response(_issGpFixture, 200);
      });
      addTearDown(client.dispose);

      await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));
      await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(callCount, 2);
    });

    test('second fetch beyond interval completes without real delay', () async {
      final clock = FakeClock(DateTime.utc(2024, 1, 15, 12));
      const interval = Duration(seconds: 2);
      final callTimes = <DateTime>[];

      final client = SpaceTrackClient.withClient(
        client: MockClient((request) async {
          if (request.url.path.contains('ajaxauth')) {
            return http.Response('', 200);
          }
          callTimes.add(clock.now);
          return http.Response(_issGpFixture, 200);
        }),
        identity: 'user@example.com',
        password: 'test-password',
        baseUrl: 'https://spacetrack.test',
        minRequestInterval: interval,
        timeout: const Duration(seconds: 5),
        clock: clock,
      );
      addTearDown(client.dispose);

      await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));
      clock.advance(const Duration(seconds: 3));
      await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(callTimes, hasLength(2));
      expect(
        callTimes[1].difference(callTimes[0]),
        const Duration(seconds: 3),
      );
    });
  });

  // ── SpaceTrackClient._parseBody ────────────────────────────────────────────

  group(
    'SpaceTrackClient._parseBody — non-array JSON body',
    () {
      test(
        'throws OmmParseException when Space-Track returns a JSON object',
        () async {
          // Space-Track should always return a JSON array; an object indicates
          // an unexpected API change or error payload.
          const objectBody = '{"error": "something went wrong"}';
          final client = _client(
            (request) async => http.Response(objectBody, 200),
          );
          addTearDown(client.dispose);

          await expectLater(
            client.fetchByQuery(SpaceTrackQuery.byNoradId(25544)),
            throwsA(isA<OmmParseException>()),
          );
        },
      );

      test(
        'OmmParseException.field is null for unexpected JSON type',
        () async {
          const objectBody = '{"status": "error"}';
          final client = _client(
            (request) async => http.Response(objectBody, 200),
          );
          addTearDown(client.dispose);

          try {
            await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));
            fail('expected OmmParseException');
          } on OmmParseException catch (e) {
            expect(e.field, isNull);
          }
        },
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

final class _TrackingMockClient extends http.BaseClient {
  _TrackingMockClient(this._handler, {required void Function() onClose})
      : _onClose = onClose;

  final MockClientHandler _handler;
  final void Function() _onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) {
      throw StateError(
        '_TrackingMockClient only handles http.Request, '
        'got ${request.runtimeType}',
      );
    }
    final r = await _handler(request);
    return http.StreamedResponse(
      Stream.value(r.bodyBytes),
      r.statusCode,
      headers: r.headers,
    );
  }

  @override
  void close() => _onClose();
}
