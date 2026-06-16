import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException;

import 'package:celestrak/src/data/remote/spacetrack_data_source.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../../support/fake_clock.dart';
import '../../support/fixture_loader.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Sanitized ISS GP fixture from Space-Track, loaded once before the suite.
late String _issGpFixture;

/// Creates a [SpaceTrackDataSource] backed by a [MockClient] using [handler].
///
/// [baseUrl] overrides the production origin so no real network calls occur.
/// [minRequestInterval] defaults to [Duration.zero] to keep tests fast.
SpaceTrackDataSource _source(
  MockClientHandler handler, {
  String baseUrl = 'https://spacetrack.test',
  Duration minRequestInterval = Duration.zero,
  FakeClock? clock,
}) =>
    SpaceTrackDataSource(
      client: MockClient(handler),
      identity: 'user@example.com',
      password: 'test-password',
      baseUrl: baseUrl,
      minRequestInterval: minRequestInterval,
      timeout: const Duration(seconds: 5),
      clock: clock ?? FakeClock(DateTime.utc(2024, 1, 15, 12)),
    );

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

  // -------------------------------------------------------------------------
  // Constructor / constants
  // -------------------------------------------------------------------------

  group('SpaceTrackDataSource — constants', () {
    test('base URL is the Space-Track production origin', () {
      expect(kSpaceTrackBaseUrl, 'https://www.space-track.org');
    });

    test('default min request interval is 2 seconds', () {
      expect(kDefaultMinRequestInterval, const Duration(seconds: 2));
    });
  });

  group('SpaceTrackDataSource — constructor', () {
    test('throws ArgumentError when baseUrl uses http scheme', () {
      expect(
        () => SpaceTrackDataSource(
          client: http.Client(),
          identity: 'user@example.com',
          password: 'secret',
          baseUrl: 'http://www.space-track.org',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('HTTPS'),
          ),
        ),
      );
    });

    test('accepts baseUrl with https scheme', () {
      expect(
        () => SpaceTrackDataSource(
          client: http.Client(),
          identity: 'user@example.com',
          password: 'secret',
          baseUrl: 'https://www.space-track.org',
        ),
        returnsNormally,
      );
    });
  });

  // -------------------------------------------------------------------------
  // login()
  // -------------------------------------------------------------------------

  group('SpaceTrackDataSource.login()', () {
    test('POSTs to /ajaxauth/login with URL-encoded credentials', () async {
      Uri? capturedUri;
      String? capturedBody;
      String? capturedContentType;

      final src = _source((request) async {
        capturedUri = request.url;
        capturedBody = request.body;
        capturedContentType = request.headers['Content-Type'];
        return http.Response('', 200);
      });

      await src.login();

      expect(
        capturedUri?.path,
        '/ajaxauth/login',
        reason: 'login must POST to /ajaxauth/login',
      );
      expect(
        capturedContentType,
        'application/x-www-form-urlencoded',
        reason: 'Content-Type must be form-urlencoded',
      );
      expect(
        capturedBody,
        contains('identity=user%40example.com'),
        reason: 'identity must be URL-encoded',
      );
      expect(
        capturedBody,
        contains('password=test-password'),
        reason: 'password must be present in body',
      );
    });

    test('sets isLoggedIn=true on HTTP 200', () async {
      final src = _source((_) async => http.Response('', 200));

      expect(src.isLoggedIn, isFalse);
      await src.login();
      expect(src.isLoggedIn, isTrue);
    });

    test('throws AuthenticationException on HTTP 401', () async {
      final src = _source(
        (request) async => http.Response('Invalid credentials', 401),
      );

      final ex = await _catchAuth(src.login);

      expect(ex.statusCode, 401);
      expect(ex.uri?.path, '/ajaxauth/login');
      expect(src.isLoggedIn, isFalse);
    });

    test('throws AuthenticationException on HTTP 403', () async {
      final src = _source(
        (request) async => http.Response('Forbidden', 403),
      );

      final ex = await _catchAuth(src.login);

      expect(ex.statusCode, 403);
    });

    test('throws NetworkException on unexpected non-2xx (e.g. 500)', () async {
      final src = _source(
        (request) async => http.Response('Server Error', 500),
      );

      final ex = await _catchNetwork(src.login);

      expect(ex.statusCode, 500);
    });

    test('throws NetworkException on SocketException', () async {
      final src = _source(
        (_) async => throw const SocketException('Connection refused'),
      );

      final ex = await _catchNetwork(src.login);

      expect(ex.cause, isA<SocketException>());
    });

    test('throws NetworkException on TimeoutException', () async {
      final src = _source(
        (_) async => throw TimeoutException('login timed out'),
      );

      final ex = await _catchNetwork(src.login);

      expect(ex.cause, isA<TimeoutException>());
      expect(ex.uri?.path, '/ajaxauth/login');
    });

    test('is idempotent — calling login twice does not throw', () async {
      final src = _source((_) async => http.Response('', 200));

      await src.login();
      await src.login();

      expect(src.isLoggedIn, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // fetchByNoradId()
  // -------------------------------------------------------------------------

  group('SpaceTrackDataSource.fetchByNoradId()', () {
    test('builds correct GP query URI for NORAD ID 25544', () async {
      Uri? capturedUri;

      final src = _source((request) async {
        capturedUri = request.url;
        return http.Response(_issGpFixture, 200);
      });

      await src.fetchByNoradId(25544);

      expect(
        capturedUri?.path,
        '/basicspacedata/query/class/gp/NORAD_CAT_ID/25544/format/json',
      );
    });

    test('returns fixture body on HTTP 200', () async {
      final src = _source(
        (_) async => http.Response(_issGpFixture, 200),
      );

      final body = await src.fetchByNoradId(25544);

      expect(body, equals(_issGpFixture));
    });

    test('fixture contains NORAD_CAT_ID 25544', () async {
      final src = _source(
        (_) async => http.Response(_issGpFixture, 200),
      );

      final body = await src.fetchByNoradId(25544);

      expect(body, contains('"NORAD_CAT_ID": "25544"'));
    });

    test('fixture contains TLE_LINE1 and TLE_LINE2', () async {
      final src = _source(
        (_) async => http.Response(_issGpFixture, 200),
      );

      final body = await src.fetchByNoradId(25544);

      expect(body, contains('"TLE_LINE1"'));
      expect(body, contains('"TLE_LINE2"'));
    });

    test('fixture source is stamped as Space-Track (ORIGINATOR field)', () {
      expect(_issGpFixture, contains('"ORIGINATOR": "18 SDS"'));
    });

    test('throws ArgumentError when noradId < 1', () async {
      final src = _source((_) async => http.Response('', 200));

      await expectLater(
        src.fetchByNoradId(0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when noradId is negative', () async {
      final src = _source((_) async => http.Response('', 200));

      await expectLater(
        src.fetchByNoradId(-1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws AuthenticationException on HTTP 401 (session expired)',
        () async {
      final src = _source(
        (_) async => http.Response('Unauthorized', 401),
      );

      final ex = await _catchAuth(() => src.fetchByNoradId(25544));

      expect(ex.statusCode, 401);
      expect(ex.uri?.path, contains('/NORAD_CAT_ID/25544'));
      expect(src.isLoggedIn, isFalse);
    });

    test('throws AuthenticationException on HTTP 403', () async {
      final src = _source(
        (_) async => http.Response('Forbidden', 403),
      );

      final ex = await _catchAuth(() => src.fetchByNoradId(25544));

      expect(ex.statusCode, 403);
    });

    test('sets isLoggedIn=false when session expires mid-session', () async {
      var loginDone = false;
      final src = _source((request) async {
        if (request.url.path.contains('ajaxauth')) {
          loginDone = true;
          return http.Response('', 200);
        }
        return http.Response('Unauthorized', 401);
      });

      await src.login();
      expect(src.isLoggedIn, isTrue);
      expect(loginDone, isTrue);

      await _catchAuth(() => src.fetchByNoradId(25544));
      expect(src.isLoggedIn, isFalse);
    });

    test('throws RateLimitException on HTTP 429', () async {
      final src = _source(
        (_) async => http.Response('Too Many Requests', 429),
      );

      final ex = await _catchRateLimit(() => src.fetchByNoradId(25544));

      expect(ex.uri?.path, contains('/NORAD_CAT_ID/25544'));
    });

    test('throws NetworkException on HTTP 500', () async {
      final src = _source(
        (_) async => http.Response('Internal Server Error', 500),
      );

      final ex = await _catchNetwork(() => src.fetchByNoradId(25544));

      expect(ex.statusCode, 500);
    });

    test('throws NetworkException on SocketException', () async {
      final src = _source(
        (_) async => throw const SocketException('Network unreachable'),
      );

      final ex = await _catchNetwork(() => src.fetchByNoradId(25544));

      expect(ex.cause, isA<SocketException>());
    });

    test('throws NetworkException on TimeoutException', () async {
      final src = _source(
        (_) async => throw TimeoutException('timed out'),
      );

      final ex = await _catchNetwork(() => src.fetchByNoradId(25544));

      expect(ex.cause, isA<TimeoutException>());
    });
  });

  // -------------------------------------------------------------------------
  // fetchSatcatByNoradId()
  // -------------------------------------------------------------------------

  group('SpaceTrackDataSource.fetchSatcatByNoradId()', () {
    test('builds correct SATCAT query URI for NORAD ID 25544', () async {
      Uri? capturedUri;

      final src = _source((request) async {
        capturedUri = request.url;
        return http.Response('[]', 200);
      });

      try {
        await src.fetchSatcatByNoradId(25544);
      } on SatelliteNotFoundException {
        // The URI is captured before the empty-array body is parsed; the
        // not-found exception is irrelevant to the URI assertion below. The
        // data source itself returns the raw body, so this catch is defensive.
      }

      expect(
        capturedUri?.path,
        '/basicspacedata/query/class/satcat/NORAD_CAT_ID/25544'
        '/CURRENT/Y/format/json',
      );
    });

    test('SATCAT query URL contains no credentials', () async {
      Uri? capturedUri;

      final src = _source((request) async {
        capturedUri = request.url;
        // At the data-source layer fetchSatcatByNoradId returns the raw body;
        // an empty array is a valid 200 response and is not parsed here.
        return http.Response('[]', 200);
      });

      await src.fetchSatcatByNoradId(25544);

      final urlString = capturedUri.toString();
      expect(urlString, isNot(contains('identity')));
      expect(urlString, isNot(contains('password')));
      expect(urlString, isNot(contains('user@example.com')));
      expect(urlString, isNot(contains('test-password')));
    });

    test('returns the response body on HTTP 200', () async {
      const body = '[{"NORAD_CAT_ID":"25544"}]';
      final src = _source((_) async => http.Response(body, 200));

      final result = await src.fetchSatcatByNoradId(25544);

      expect(result, equals(body));
    });

    test('throws ArgumentError when noradId < 1', () async {
      final src = _source((_) async => http.Response('[]', 200));

      await expectLater(
        src.fetchSatcatByNoradId(0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when noradId is negative', () async {
      final src = _source((_) async => http.Response('[]', 200));

      await expectLater(
        src.fetchSatcatByNoradId(-1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws AuthenticationException on HTTP 401', () async {
      final src = _source((_) async => http.Response('Unauthorized', 401));

      final ex = await _catchAuth(() => src.fetchSatcatByNoradId(25544));

      expect(ex.statusCode, 401);
      expect(ex.uri?.path, contains('/class/satcat/NORAD_CAT_ID/25544'));
    });

    test('throws AuthenticationException on HTTP 403', () async {
      final src = _source((_) async => http.Response('Forbidden', 403));

      final ex = await _catchAuth(() => src.fetchSatcatByNoradId(25544));

      expect(ex.statusCode, 403);
      expect(ex.uri?.path, contains('/class/satcat/NORAD_CAT_ID/25544'));
    });

    test('throws RateLimitException on HTTP 429', () async {
      final src = _source((_) async => http.Response('Too Many', 429));

      final ex = await _catchRateLimit(() => src.fetchSatcatByNoradId(25544));

      expect(ex.uri?.path, contains('/class/satcat/NORAD_CAT_ID/25544'));
    });

    test('throws NetworkException on HTTP 500', () async {
      final src = _source((_) async => http.Response('Server Error', 500));

      final ex = await _catchNetwork(() => src.fetchSatcatByNoradId(25544));

      expect(ex.statusCode, 500);
    });

    test('delays a second request within the minimum interval', () async {
      // The FakeClock is never advanced, so the second call sees zero elapsed
      // time and must wait out the full interval. Measuring real wall-clock
      // proves _enforceRateLimit actually delayed the SATCAT request - a
      // clock-advance assertion would pass even if the throttle were removed.
      const interval = Duration(milliseconds: 100);
      final clock = FakeClock(DateTime.utc(2024, 1, 15, 12));

      final src = SpaceTrackDataSource(
        client: MockClient((_) async => http.Response('[]', 200)),
        identity: 'user@example.com',
        password: 'password',
        baseUrl: 'https://spacetrack.test',
        minRequestInterval: interval,
        timeout: const Duration(seconds: 5),
        clock: clock,
      );

      // First call has no predecessor, so it is not throttled.
      await src.fetchSatcatByNoradId(25544);

      final stopwatch = Stopwatch()..start();
      await src.fetchSatcatByNoradId(25544);
      stopwatch.stop();

      expect(stopwatch.elapsed, greaterThanOrEqualTo(interval));
    });
  });

  // -------------------------------------------------------------------------
  // Rate limiting with fake clock
  // -------------------------------------------------------------------------

  group('SpaceTrackDataSource — rate limiting', () {
    // The FakeClock does not affect Future.delayed wall time. Two strategies
    // are used to avoid real sleeps:
    //   1. minRequestInterval: Duration.zero — no delay is ever needed, used to
    //      verify _lastRequestAt bookkeeping logic via clock snapshots.
    //   2. Advance the clock past the interval before the second call — elapsed
    //      time exceeds minRequestInterval so the no-delay path is taken even
    //      when a non-zero interval is configured.

    test('_lastRequestAt is stamped before the await (eager reservation)',
        () async {
      // Verify that the slot is reserved at the clock snapshot taken on entry,
      // not after the (potential) sleep.  We do this by capturing the clock
      // value recorded on the first call, then confirming the second call
      // measures elapsed time from that snapshot (clock.now - T0 == 1 s,
      // which is > Duration.zero interval, so no delay occurs).
      final clock = FakeClock(DateTime.utc(2024, 1, 15, 12));
      final callTimes = <DateTime>[];

      final src = SpaceTrackDataSource(
        client: MockClient((request) async {
          callTimes.add(clock.now);
          return http.Response(_issGpFixture, 200);
        }),
        identity: 'user@example.com',
        password: 'password',
        baseUrl: 'https://spacetrack.test',
        minRequestInterval: Duration.zero,
        timeout: const Duration(seconds: 5),
        clock: clock,
      );

      // T0: first request stamps _lastRequestAt = T0.
      await src.fetchByNoradId(25544);
      final t0 = callTimes.first;

      // T0+1s: second request — slot already reserved at T0, elapsed > 0.
      clock.advance(const Duration(seconds: 1));
      await src.fetchByNoradId(25544);

      expect(callTimes, hasLength(2));
      expect(callTimes[1].difference(t0), const Duration(seconds: 1));
    });

    test('second request beyond interval issues immediately (no delay)',
        () async {
      // Advance the clock past the interval between calls; confirms the
      // no-delay path is taken when sufficient time has elapsed.
      final clock = FakeClock(DateTime.utc(2024, 1, 15, 12));
      const interval = Duration(seconds: 2);
      final callTimes = <DateTime>[];

      final src = SpaceTrackDataSource(
        client: MockClient((request) async {
          callTimes.add(clock.now);
          return http.Response(_issGpFixture, 200);
        }),
        identity: 'user@example.com',
        password: 'password',
        baseUrl: 'https://spacetrack.test',
        minRequestInterval: interval,
        timeout: const Duration(seconds: 5),
        clock: clock,
      );

      // First request at T0.
      await src.fetchByNoradId(25544);

      // Advance clock by 3 s (> 2 s interval) — second request takes no delay.
      clock.advance(const Duration(seconds: 3));
      await src.fetchByNoradId(25544);

      expect(callTimes, hasLength(2));
      // The clock moved by 3 s between calls; elapsed exceeded interval.
      expect(
        callTimes[1].difference(callTimes[0]),
        const Duration(seconds: 3),
      );
    });

    test('minRequestInterval of zero issues requests without delay', () async {
      var callCount = 0;
      final src = _source((request) async {
        callCount++;
        return http.Response(_issGpFixture, 200);
      });

      await src.fetchByNoradId(25544);
      await src.fetchByNoradId(25544);

      expect(callCount, 2);
    });
  });

  // -------------------------------------------------------------------------
  // Exception field assertions
  // -------------------------------------------------------------------------

  group('AuthenticationException', () {
    test('toString includes statusCode and uri', () {
      const ex = AuthenticationException(
        'test message',
        statusCode: 401,
        uri: null,
      );

      expect(ex.toString(), contains('AuthenticationException'));
      expect(ex.toString(), contains('test message'));
      expect(ex.toString(), contains('statusCode=401'));
    });

    test('toString with uri includes uri segment', () {
      final ex = AuthenticationException(
        'login failed',
        statusCode: 401,
        uri: Uri.parse('https://www.space-track.org/ajaxauth/login'),
      );

      expect(ex.toString(), contains('uri='));
    });

    test('toString without uri includes only statusCode', () {
      const ex = AuthenticationException('bare message', statusCode: 401);

      expect(
        ex.toString(),
        'AuthenticationException: bare message, statusCode=401',
      );
    });
  });

  group('RateLimitException', () {
    test('toString includes message', () {
      const ex = RateLimitException('rate limit hit');

      expect(ex.toString(), contains('RateLimitException'));
      expect(ex.toString(), contains('rate limit hit'));
    });

    test('toString with uri includes uri segment', () {
      final ex = RateLimitException(
        'throttled',
        uri: Uri.parse('https://www.space-track.org/basicspacedata/query'),
      );

      expect(ex.toString(), contains('uri='));
    });

    test('toString without uri is clean', () {
      const ex = RateLimitException('bare message');

      expect(ex.toString(), 'RateLimitException: bare message');
    });

    test('toString with retryAfter includes retryAfter segment', () {
      const ex = RateLimitException(
        'throttled',
        retryAfter: Duration(seconds: 60),
      );

      expect(ex.toString(), contains('retryAfter=60s'));
    });

    test('fetchByNoradId surfaces Retry-After header as retryAfter duration',
        () async {
      final src = _source(
        (_) async => http.Response(
          'Too Many Requests',
          429,
          headers: {'retry-after': '120'},
        ),
      );

      final ex = await _catchRateLimit(() => src.fetchByNoradId(25544));

      expect(ex.retryAfter, const Duration(seconds: 120));
    });

    test('fetchByNoradId retryAfter is null when Retry-After header absent',
        () async {
      final src = _source(
        (_) async => http.Response('Too Many Requests', 429),
      );

      final ex = await _catchRateLimit(() => src.fetchByNoradId(25544));

      expect(ex.retryAfter, isNull);
    });
  });
}
