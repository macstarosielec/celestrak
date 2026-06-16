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

late String _issSatcatFixture;
late String _issGpFixture;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns a [SpaceTrackClient] backed by a [MockClient] for the SATCAT path.
///
/// [loginHandler] handles POST to the login endpoint (defaults to HTTP 200).
/// [dataHandler] handles GET data requests (the SATCAT query).
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

/// A no-op [MockClient] that fails the test if any HTTP request is made.
MockClient _neverCalled() => MockClient(
      (_) async => fail('HTTP client must not be called on a disabled source'),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    _issSatcatFixture = await loadFixture(
      'test/fixtures/spacetrack_iss_25544_satcat.json',
    );
    _issGpFixture = await loadFixture(
      'test/fixtures/spacetrack_iss_25544_gp.json',
    );
  });

  // -- fetchSatcatByQuery -- happy path --------------------------------------

  group('SpaceTrackClient.fetchSatcatByQuery() -- happy path', () {
    test('returns a SatcatEntry with the requested noradId', () async {
      final client = _client(
        (_) async => http.Response(_issSatcatFixture, 200),
      );
      addTearDown(client.dispose);

      final entry =
          await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(entry.noradId, 25544);
    });

    test('maps SATNAME/OBJECT_NAME to the entry name', () async {
      final client = _client(
        (_) async => http.Response(_issSatcatFixture, 200),
      );
      addTearDown(client.dispose);

      final entry =
          await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(entry.name, 'ISS (ZARYA)');
    });

    test('maps COUNTRY to ownerCode', () async {
      final client = _client(
        (_) async => http.Response(_issSatcatFixture, 200),
      );
      addTearDown(client.dispose);

      final entry =
          await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(entry.ownerCode, 'ISS');
    });

    test('maps OBJECT_TYPE PAYLOAD to SatcatObjectType.payload', () async {
      final client = _client(
        (_) async => http.Response(_issSatcatFixture, 200),
      );
      addTearDown(client.dispose);

      final entry =
          await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(entry.objectType, SatcatObjectType.payload);
      expect(entry.isPayload, isTrue);
    });

    test('maps OBJECT_ID/INTLDES to objectId', () async {
      final client = _client(
        (_) async => http.Response(_issSatcatFixture, 200),
      );
      addTearDown(client.dispose);

      final entry =
          await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(entry.objectId, '1998-067A');
    });

    test('falls back to SATNAME when OBJECT_NAME is absent', () async {
      // A record carrying only the legacy SATNAME key (no OBJECT_NAME) must
      // still resolve the name via the fallback branch.
      final client = _client(
        (_) async => http.Response(
          '[{"NORAD_CAT_ID": "25544", "SATNAME": "ISS (ZARYA)"}]',
          200,
        ),
      );
      addTearDown(client.dispose);

      final entry =
          await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(entry.name, 'ISS (ZARYA)');
    });

    test('falls back to INTLDES when OBJECT_ID is absent', () async {
      // A record carrying only the legacy INTLDES key (no OBJECT_ID) must
      // still resolve the objectId via the fallback branch.
      final client = _client(
        (_) async => http.Response(
          '[{"NORAD_CAT_ID": "25544", "INTLDES": "1998-067A"}]',
          200,
        ),
      );
      addTearDown(client.dispose);

      final entry =
          await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(entry.objectId, '1998-067A');
    });

    test('parses launchDate from the LAUNCH field as UTC', () async {
      final client = _client(
        (_) async => http.Response(_issSatcatFixture, 200),
      );
      addTearDown(client.dispose);

      final entry =
          await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(entry.launchDate, DateTime.utc(1998, 11, 20));
    });

    test('maps SITE to launchSite', () async {
      final client = _client(
        (_) async => http.Response(_issSatcatFixture, 200),
      );
      addTearDown(client.dispose);

      final entry =
          await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(entry.launchSite, 'TTMTR');
    });

    test('null DECAY yields isOnOrbit true', () async {
      final client = _client(
        (_) async => http.Response(_issSatcatFixture, 200),
      );
      addTearDown(client.dispose);

      final entry =
          await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(entry.decayDate, isNull);
      expect(entry.isOnOrbit, isTrue);
    });

    test('logs in before issuing the SATCAT data request', () async {
      var loginPathSeen = false;
      var loginBeforeData = false;
      var dataSeen = false;

      final client = _client(
        (request) async {
          dataSeen = true;
          if (loginPathSeen) loginBeforeData = true;
          return http.Response(_issSatcatFixture, 200);
        },
        loginHandler: (request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/ajaxauth/login');
          loginPathSeen = true;
          return http.Response('', 200);
        },
      );
      addTearDown(client.dispose);

      await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(loginPathSeen, isTrue, reason: 'login POST must happen');
      expect(dataSeen, isTrue);
      expect(loginBeforeData, isTrue, reason: 'login must precede data fetch');
    });

    test('SATCAT data request URL contains no credentials', () async {
      Uri? capturedUri;

      final client = _client(
        (request) async {
          capturedUri = request.url;
          return http.Response(_issSatcatFixture, 200);
        },
      );
      addTearDown(client.dispose);

      await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      final urlString = capturedUri.toString();
      expect(urlString, isNot(contains('identity')));
      expect(urlString, isNot(contains('password')));
      expect(urlString, isNot(contains('user@example.com')));
      expect(urlString, isNot(contains('test-password')));
    });
  });

  // -- credential gating: disabled client ------------------------------------

  group('SpaceTrackClient.fetchSatcatByQuery() -- disabled source', () {
    test('throws StateError and makes no network call when disabled', () async {
      final client = SpaceTrackClient.withClient(
        client: _neverCalled(),
        identity: null,
        password: null,
        baseUrl: 'https://spacetrack.test',
      );
      addTearDown(client.dispose);

      await expectLater(
        client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('disabled'))
              .having((e) => e.message, 'message', contains('isEnabled')),
        ),
      );
    });

    test('throws StateError when only the password is empty', () async {
      final client = SpaceTrackClient.withClient(
        client: _neverCalled(),
        identity: 'user@example.com',
        password: '',
        baseUrl: 'https://spacetrack.test',
      );
      addTearDown(client.dispose);

      await expectLater(
        client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<StateError>()),
      );
    });
  });

  // -- disposed client -------------------------------------------------------

  group('SpaceTrackClient.fetchSatcatByQuery() -- disposed', () {
    test('throws StateError after dispose', () async {
      final client = SpaceTrackClient.withClient(
        client: _neverCalled(),
        identity: 'user@example.com',
        password: 'secret',
        baseUrl: 'https://spacetrack.test',
      )..dispose();

      await expectLater(
        client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('disposed')),
        ),
      );
    });
  });

  // -- not found / malformed -------------------------------------------------

  group('SpaceTrackClient.fetchSatcatByQuery() -- not found and malformed', () {
    test('throws SatelliteNotFoundException on an empty array', () async {
      final client = _client((_) async => http.Response('[]', 200));
      addTearDown(client.dispose);

      try {
        await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));
        fail('expected SatelliteNotFoundException');
      } on SatelliteNotFoundException catch (e) {
        expect(e.noradId, 25544);
      }
    });

    test('throws SatcatParseException on a JSON object (not an array)',
        () async {
      final client = _client(
        (_) async => http.Response('{"error": "nope"}', 200),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('throws SatcatParseException on invalid JSON', () async {
      final client = _client(
        (_) async => http.Response('{ not json', 200),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('throws SatcatParseException when NORAD_CAT_ID is absent', () async {
      final client = _client(
        (_) async => http.Response('[{"SATNAME": "MYSTERY"}]', 200),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('throws SatcatParseException on a non-object array element', () async {
      final client = _client((_) async => http.Response('[42]', 200));
      addTearDown(client.dispose);

      await expectLater(
        client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544)),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('uses the first record when more than one is returned', () async {
      // Defensive: even though CURRENT/Y should yield a single record, a
      // multi-record response must still resolve to the first without error.
      final client = _client(
        (_) async => http.Response(
          '[{"NORAD_CAT_ID": "25544", "OBJECT_NAME": "ISS (ZARYA)"}, '
          '{"NORAD_CAT_ID": "48274", "OBJECT_NAME": "CSS (TIANHE)"}]',
          200,
        ),
      );
      addTearDown(client.dispose);

      final entry =
          await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(entry.noradId, 25544);
      expect(entry.name, 'ISS (ZARYA)');
    });
  });

  // -- error mapping on the SATCAT path --------------------------------------

  group('SpaceTrackClient.fetchSatcatByQuery() -- error mapping', () {
    test('throws AuthenticationException on HTTP 401 during login', () async {
      final client = _client(
        (_) async => http.Response(_issSatcatFixture, 200),
        loginHandler: (_) async => http.Response('Unauthorized', 401),
      );
      addTearDown(client.dispose);

      final ex = await _catchAuth(
        () => client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.statusCode, 401);
    });

    test('throws AuthenticationException on HTTP 403 during data fetch',
        () async {
      final client = _client((_) async => http.Response('Forbidden', 403));
      addTearDown(client.dispose);

      final ex = await _catchAuth(
        () => client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.statusCode, 403);
    });

    test('throws RateLimitException on HTTP 429', () async {
      final client = _client(
        (_) async => http.Response('Too Many Requests', 429),
      );
      addTearDown(client.dispose);

      final ex = await _catchRateLimit(
        () => client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.uri?.path, contains('/class/satcat/NORAD_CAT_ID/25544'));
    });

    test('throws NetworkException on HTTP 500', () async {
      final client = _client(
        (_) async => http.Response('Internal Server Error', 500),
      );
      addTearDown(client.dispose);

      final ex = await _catchNetwork(
        () => client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.statusCode, 500);
    });

    test('throws NetworkException on SocketException', () async {
      final client = _client(
        (_) async => throw const SocketException('Network unreachable'),
      );
      addTearDown(client.dispose);

      final ex = await _catchNetwork(
        () => client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.cause, isA<SocketException>());
    });

    test('throws NetworkException on TimeoutException', () async {
      final client = _client(
        (_) async => throw TimeoutException('timed out'),
      );
      addTearDown(client.dispose);

      final ex = await _catchNetwork(
        () => client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544)),
      );

      expect(ex.cause, isA<TimeoutException>());
    });
  });

  // -- throttle parity -------------------------------------------------------

  group('SpaceTrackClient.fetchSatcatByQuery() -- throttle parity', () {
    test('a second fetch within the interval is delayed by the throttle',
        () async {
      // The FakeClock does not advance Future.delayed wall time, so the clock
      // stays at T0 across both calls: the second sees zero elapsed time and
      // must wait out the full interval. Measuring real wall-clock proves the
      // throttle actually delayed the request - a clock-advance assertion would
      // pass even if _enforceRateLimit were removed.
      const interval = Duration(milliseconds: 100);
      final client = _client(
        (_) async => http.Response(_issSatcatFixture, 200),
        minRequestInterval: interval,
      );
      addTearDown(client.dispose);

      // First call has no predecessor, so it is not throttled.
      await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      final stopwatch = Stopwatch()..start();
      await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));
      stopwatch.stop();

      expect(stopwatch.elapsed, greaterThanOrEqualTo(interval));
    });

    test('login is performed once across a GP then SATCAT fetch', () async {
      var loginCount = 0;
      final client = SpaceTrackClient.withClient(
        client: MockClient((request) async {
          if (request.url.path.contains('ajaxauth')) {
            loginCount++;
            return http.Response('', 200);
          }
          if (request.url.path.contains('/class/gp/')) {
            return http.Response(_issGpFixture, 200);
          }
          return http.Response(_issSatcatFixture, 200);
        }),
        identity: 'user@example.com',
        password: 'test-password',
        baseUrl: 'https://spacetrack.test',
        minRequestInterval: Duration.zero,
        timeout: const Duration(seconds: 5),
        clock: FakeClock(DateTime.utc(2024, 1, 15, 12)),
      );
      addTearDown(client.dispose);

      // A GP fetch logs in; the subsequent SATCAT fetch reuses that session.
      await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));
      await client.fetchSatcatByQuery(SpaceTrackQuery.byNoradId(25544));

      expect(loginCount, 1);
    });
  });

  // -- credential safety of the fixture --------------------------------------

  group('SATCAT fixture credential safety', () {
    test('fixture contains no credential-like fields', () {
      final lower = _issSatcatFixture.toLowerCase();
      expect(lower, isNot(contains('password')));
      expect(lower, isNot(contains('identity')));
      expect(lower, isNot(contains('secret')));
      // No email-style login string. A bare '@' would false-positive on real
      // SATCAT data (none uses it), so assert the absence of an email address.
      expect(lower, isNot(matches(RegExp('[a-z0-9._%+-]+@[a-z0-9.-]+'))));
    });

    test('fixture is a JSON array with Space-Track field names', () {
      expect(_issSatcatFixture.trimLeft(), startsWith('['));
      expect(_issSatcatFixture, contains('"COUNTRY"'));
      expect(_issSatcatFixture, contains('"SATNAME"'));
      expect(_issSatcatFixture, contains('"RCSVALUE"'));
    });
  });
}
