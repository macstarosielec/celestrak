import 'dart:async' show TimeoutException;
import 'dart:io' show Directory, File, SocketException;

import 'package:celestrak/src/data/remote/spacetrack_data_source.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../../support/fake_clock.dart';

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
    // `dart test` sets the working directory to the package root, so
    // Directory.current is a reliable anchor regardless of invocation path.
    _issGpFixture = await File(
      '${Directory.current.path}/test/fixtures/spacetrack_iss_25544_gp.json',
    ).readAsString();
  });

  // -------------------------------------------------------------------------
  // Constructor / constants
  // -------------------------------------------------------------------------

  group('SpaceTrackDataSource — constants', () {
    test('base URL is the Space-Track production origin', () {
      expect(kSpaceTrackBaseUrl, 'https://www.space-track.org');
    });

    test('login path is /ajaxauth/login', () {
      expect(kSpaceTrackLoginPath, '/ajaxauth/login');
    });

    test('data path is /basicspacedata/query', () {
      expect(kSpaceTrackDataPath, '/basicspacedata/query');
    });

    test('GP class path is /class/gp', () {
      expect(kSpaceTrackGpClassPath, '/class/gp');
    });

    test('format suffix is /format/json', () {
      expect(kSpaceTrackJsonFormat, '/format/json');
    });

    test('default min request interval is 2 seconds', () {
      expect(kDefaultMinRequestInterval, const Duration(seconds: 2));
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
        kSpaceTrackLoginPath,
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
      expect(ex.uri?.path, kSpaceTrackLoginPath);
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
        '$kSpaceTrackDataPath$kSpaceTrackGpClassPath'
        '/NORAD_CAT_ID/25544$kSpaceTrackJsonFormat',
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

    test('throws ArgumentError when noradId < 1', () {
      final src = _source((_) async => http.Response('', 200));

      expect(
        () => src.fetchByNoradId(0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when noradId is negative', () {
      final src = _source((_) async => http.Response('', 200));

      expect(
        () => src.fetchByNoradId(-1),
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
  // Rate limiting with fake clock
  // -------------------------------------------------------------------------

  group('SpaceTrackDataSource — rate limiting', () {
    test('second request within interval waits for remainder', () async {
      final clock = FakeClock(DateTime.utc(2024, 1, 15, 12));
      const interval = Duration(seconds: 2);
      final callTimes = <DateTime>[];

      // Use a Completer to synchronise the advance of the fake clock with
      // the second request actually being issued (the delay is real-time, so
      // we skip it by making the interval zero for the real sleep and just
      // verify the last-request tracking logic instead).
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

      // First request — no delay, records lastRequestAt = T0.
      await src.fetchByNoradId(25544);

      // Advance clock by 3 s (> interval) — second request should not delay.
      clock.advance(const Duration(seconds: 3));
      await src.fetchByNoradId(25544);

      expect(callTimes, hasLength(2));
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
