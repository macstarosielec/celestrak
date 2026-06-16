/// Remote data source for the Space-Track.org GP API.
///
/// Implements a POST-login / cookie-session flow against the Space-Track REST
/// API, maps the GP class query to typed responses, and enforces a conservative
/// minimum request interval to comply with the published rate-limit policy
/// (30 req/min, 300 req/hour).
///
/// ## Login flow
///
/// Space-Track does not use API keys. Instead, callers POST their registered
/// email address and password to `/ajaxauth/login`; the server responds with a
/// `Set-Cookie` header that carries the session token. All subsequent data
/// requests include that cookie automatically via the shared [http.Client].
///
/// The session cookie is kept **in-memory only** and is never written to disk,
/// ensuring no persistent credential storage.
///
/// ## Usage
///
/// ```dart
/// final client = http.Client();
/// final source = SpaceTrackDataSource(
///   client: client,
///   identity: 'user@example.com',
///   password: 'secret',
/// );
/// try {
///   final json = await source.fetchByNoradId(25544);
/// } finally {
///   client.close(); // the caller owns the client and is responsible for closing it
/// }
/// ```
///
/// See also:
/// - [AuthenticationException] — raised on 401/403.
/// - [RateLimitException] — raised on 429.
/// - [NetworkException] — raised on other transport failures.
library;

import 'dart:async' show TimeoutException;

import 'package:celestrak/src/domain/clock.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/network/socket_exception_stub.dart'
    if (dart.library.io) 'package:celestrak/src/network/socket_exception_io.dart';
import 'package:http/http.dart' as http;

/// Base URL for the Space-Track REST API.
///
/// All login and query paths are resolved relative to this origin.
const String kSpaceTrackBaseUrl = 'https://www.space-track.org';

/// Path for the JSON login endpoint.
///
/// Accepts a POST with `application/x-www-form-urlencoded` body containing
/// `identity=<email>&password=<password>`. On success the server returns a
/// `Set-Cookie` header; on failure it returns HTTP 401.
const String _kSpaceTrackLoginPath = '/ajaxauth/login';

/// URL-encoded body template for the login POST.
///
/// Parameters are substituted at call time via [SpaceTrackDataSource.login].
/// Credentials are never stored beyond the scope of the login call.
// Not for direct use — always call SpaceTrackDataSource.login() instead.
const String _kSpaceTrackLoginBodyTemplate =
    'identity={identity}&password={password}';

/// Base path for the basic space-data API.
///
/// Full GP query path:
/// `{_kSpaceTrackDataPath}/class/gp/NORAD_CAT_ID/<id>/format/json`
const String _kSpaceTrackDataPath = '/basicspacedata/query';

/// GP class path segment within the basic space-data API.
const String _kSpaceTrackGpClassPath = '/class/gp';

/// SATCAT class path segment within the basic space-data API.
///
/// Full SATCAT query path:
/// `{_kSpaceTrackDataPath}/class/satcat/NORAD_CAT_ID/<id>/CURRENT/Y/format/json`
const String _kSpaceTrackSatcatClassPath = '/class/satcat';

/// Predicate segment restricting a SATCAT query to the current record.
///
/// Space-Track keeps historical SATCAT rows; appending `CURRENT/Y` returns
/// only the single current record for an object, giving single-record
/// semantics analogous to the GP path's per-NORAD filter.
const String _kSpaceTrackCurrentFilter = '/CURRENT/Y';

/// Format segment appended to every GP query.
const String _kSpaceTrackJsonFormat = '/format/json';

/// Minimum interval between successive Space-Track API requests.
///
/// Space-Track enforces ≤30 requests/minute and ≤300 requests/hour. A 2-second
/// floor keeps automated scripts well within the per-minute budget even under
/// continuous polling (max 30 req/min = 1 req/2 s). Override via the
/// `minRequestInterval` constructor parameter of [SpaceTrackDataSource].
const Duration kDefaultMinRequestInterval = Duration(seconds: 2);

/// Default per-request timeout forwarded to the underlying HTTP client.
const Duration kSpaceTrackDefaultTimeout = Duration(seconds: 30);

/// Raw-data access layer for the Space-Track.org GP API.
///
/// Handles the POST-login / cookie-session authentication flow and issues GP
/// class queries for individual objects by NORAD catalog number.
///
/// This class is the data-layer component wrapped by the `SpaceTrackClient`
/// facade. It is intentionally not exported from `lib/celestrak.dart`; use
/// `SpaceTrackClient` directly.
///
/// **Rate limiting.** A minimum inter-request delay (`minRequestInterval`,
/// default: 2 s) is enforced between successive data requests. The login call
/// does not count toward the request interval. The interval is measured against
/// a [Clock] so tests can advance time without real sleeps.
///
/// **Session management.** The session cookie returned by the login endpoint is
/// held in memory by the underlying [http.Client] (if a cookie-aware client is
/// supplied). It is never written to disk. The source becomes usable after the
/// first successful login.
///
/// **Error mapping.**
/// | HTTP status | Exception |
/// |-------------|-----------|
/// | 401, 403    | [AuthenticationException] |
/// | 429         | [RateLimitException] |
/// | 5xx         | [NetworkException] |
/// | Timeout / socket | [NetworkException] |
final class SpaceTrackDataSource {
  /// Creates a [SpaceTrackDataSource].
  ///
  /// [client] is the underlying HTTP client. The caller owns the client and is
  /// responsible for closing it. Use a cookie-aware client (e.g. the default
  /// [http.Client]) so that session cookies are propagated automatically.
  ///
  /// [identity] is the registered Space-Track email address.
  /// [password] is the account password.
  ///
  /// [baseUrl] defaults to the production Space-Track origin; override in tests
  /// to redirect requests to a mock server.
  ///
  /// [minRequestInterval] is the minimum time between successive data requests.
  /// Defaults to [kDefaultMinRequestInterval] (2 s).
  ///
  /// [timeout] is the per-request deadline.
  ///
  /// [clock] is used to measure elapsed time for rate-limit enforcement.
  SpaceTrackDataSource({
    required http.Client client,
    required String identity,
    required String password,
    String baseUrl = kSpaceTrackBaseUrl,
    Duration minRequestInterval = kDefaultMinRequestInterval,
    Duration timeout = kSpaceTrackDefaultTimeout,
    Clock clock = const SystemClock(),
  })  : _client = client,
        _identity = identity,
        _password = password,
        _baseUrl = baseUrl,
        _minRequestInterval = minRequestInterval,
        _timeout = timeout,
        _clock = clock {
    final scheme = Uri.parse(baseUrl).scheme;
    if (scheme != 'https') {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Only HTTPS base URLs are permitted; '
            'got scheme "$scheme". '
            'Credentials must not be transmitted in cleartext.',
      );
    }
  }

  final http.Client _client;
  final String _identity;
  final String _password;
  final String _baseUrl;
  final Duration _minRequestInterval;
  final Duration _timeout;
  final Clock _clock;

  /// Session cookie extracted from the login response Set-Cookie header.
  String? _sessionCookie;

  /// The timestamp of the most recent data request, used for throttling.
  DateTime? _lastRequestAt;

  /// Whether the session is currently authenticated.
  ///
  /// Set to `true` after a successful [login] call. Reset to `false` if a
  /// subsequent data request returns 401 or 403.
  bool _loggedIn = false;

  /// `true` if a successful login has been performed since construction.
  bool get isLoggedIn => _loggedIn;

  /// Authenticates with Space-Track.org using the configured credentials.
  ///
  /// POSTs `identity=<email>&password=<password>` (URL-encoded) to the login
  /// endpoint. On success the server sets a session cookie; subsequent requests
  /// on the same [http.Client] will include that cookie automatically.
  ///
  /// Throws [AuthenticationException] if the server returns HTTP 401.
  ///
  /// Throws [NetworkException] on transport failures (timeout, socket error,
  /// or an unexpected non-2xx response).
  ///
  /// Idempotent: calling [login] when already logged in re-authenticates
  /// (refreshes the session cookie) without error.
  Future<void> login() async {
    final uri = Uri.parse('$_baseUrl$_kSpaceTrackLoginPath');

    final body = _kSpaceTrackLoginBodyTemplate
        .replaceFirst('{identity}', Uri.encodeQueryComponent(_identity))
        .replaceFirst('{password}', Uri.encodeQueryComponent(_password));

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          )
          .timeout(_timeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        _loggedIn = false;
        throw AuthenticationException(
          'Space-Track login failed: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
          uri: uri,
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NetworkException(
          'Space-Track login returned HTTP ${response.statusCode}',
          statusCode: response.statusCode,
          uri: uri,
        );
      }

      _sessionCookie = response.headers['set-cookie'];
      _loggedIn = true;
    } on AuthenticationException {
      rethrow;
    } on NetworkException {
      rethrow;
    } on TimeoutException catch (e) {
      _loggedIn = false;
      throw NetworkException(
        'Space-Track login timed out after $_timeout',
        uri: uri,
        cause: e,
      );
    } catch (e) {
      if (!isSocketException(e)) rethrow;
      _loggedIn = false;
      throw NetworkException(
        'Space-Track login socket error: $e',
        uri: uri,
        cause: e,
      );
    }
  }

  /// Fetches raw GP orbital data for a single satellite by NORAD catalog
  /// number.
  ///
  /// Sends a GET request to
  /// `{baseUrl}/basicspacedata/query/class/gp/NORAD_CAT_ID/<id>/format/json`.
  ///
  /// The minimum inter-request interval (`minRequestInterval`) is enforced
  /// before the network call. If the previous request was too recent, this
  /// method waits for the remaining interval to elapse.
  ///
  /// Throws [AuthenticationException] if the response is 401 or 403 (session
  /// expired; caller should call [login] and retry).
  ///
  /// Throws [RateLimitException] if the server returns HTTP 429.
  ///
  /// Throws [NetworkException] on transport failures (socket, timeout, 5xx).
  ///
  /// Throws [ArgumentError] if [noradId] is less than 1.
  Future<String> fetchByNoradId(int noradId) async {
    if (noradId < 1) {
      throw ArgumentError.value(
        noradId,
        'noradId',
        'NORAD catalog numbers must be >= 1',
      );
    }

    await _enforceRateLimit();

    final uri = Uri.parse(
      '$_baseUrl$_kSpaceTrackDataPath$_kSpaceTrackGpClassPath'
      '/NORAD_CAT_ID/$noradId$_kSpaceTrackJsonFormat',
    );

    return _get(uri);
  }

  /// Fetches raw SATCAT metadata for a single satellite by NORAD catalog
  /// number.
  ///
  /// Sends a GET request to
  /// `{baseUrl}/basicspacedata/query/class/satcat/NORAD_CAT_ID/<id>`
  /// `/CURRENT/Y/format/json`.
  ///
  /// The `CURRENT/Y` predicate restricts the response to the single current
  /// SATCAT record for the object, mirroring the single-record semantics of
  /// the GP path.
  ///
  /// SATCAT is metadata-only (owner, launch, decay, object type, size); it
  /// carries no orbital elements and performs no orbital math. This is part of
  /// the optional Space-Track path and is independent of the core CelesTrak
  /// SATCAT flow.
  ///
  /// The minimum inter-request interval (`minRequestInterval`) is enforced
  /// before the network call. If the previous request was too recent, this
  /// method waits for the remaining interval to elapse.
  ///
  /// Throws [AuthenticationException] if the response is 401 or 403 (session
  /// expired; caller should call [login] and retry).
  ///
  /// Throws [RateLimitException] if the server returns HTTP 429.
  ///
  /// Throws [NetworkException] on transport failures (socket, timeout, 5xx).
  ///
  /// Throws [ArgumentError] if [noradId] is less than 1.
  Future<String> fetchSatcatByNoradId(int noradId) async {
    if (noradId < 1) {
      throw ArgumentError.value(
        noradId,
        'noradId',
        'NORAD catalog numbers must be >= 1',
      );
    }

    await _enforceRateLimit();

    final uri = Uri.parse(
      '$_baseUrl$_kSpaceTrackDataPath$_kSpaceTrackSatcatClassPath'
      '/NORAD_CAT_ID/$noradId$_kSpaceTrackCurrentFilter'
      '$_kSpaceTrackJsonFormat',
    );

    return _get(uri);
  }

  /// Enforces the minimum inter-request interval.
  ///
  /// Snapshots the clock once at entry and immediately records that timestamp
  /// as [_lastRequestAt] — **before** any `await` — so that any concurrent
  /// caller that enters this method during the suspension sees a recent
  /// timestamp and sleeps for the correct remainder rather than bypassing the
  /// throttle entirely.  Successive calls therefore measure the gap between
  /// *intended* issue times rather than wall-clock drift introduced by the
  /// sleep itself.
  Future<void> _enforceRateLimit() async {
    final now = _clock.now;
    final last = _lastRequestAt;
    _lastRequestAt = now; // reserve the slot before any await
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < _minRequestInterval) {
        await Future<void>.delayed(_minRequestInterval - elapsed);
      }
    }
  }

  /// Issues an authenticated GET to [uri] and returns the response body.
  ///
  /// Maps HTTP 401/403 → [AuthenticationException], 429 →
  /// [RateLimitException], and transport failures → [NetworkException].
  Future<String> _get(Uri uri) async {
    try {
      final headers = <String, String>{};
      if (_sessionCookie != null) {
        headers['Cookie'] = _sessionCookie!;
      }
      final response =
          await _client.get(uri, headers: headers).timeout(_timeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        _loggedIn = false;
        _sessionCookie = null;
        throw AuthenticationException(
          'Space-Track session rejected: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
          uri: uri,
        );
      }

      if (response.statusCode == 429) {
        final retryAfterHeader = response.headers['retry-after'];
        // RFC 7231 permits both an integer (delay-seconds) and an HTTP-date
        // string in the Retry-After header.  Only the integer form is parsed
        // here; HTTP-date values (e.g. "Wed, 21 Oct 2025 07:28:00 GMT") yield
        // null, which is surfaced as retryAfter: null in RateLimitException.
        final retryAfterSeconds =
            retryAfterHeader != null ? int.tryParse(retryAfterHeader) : null;
        throw RateLimitException(
          'Space-Track rate limit exceeded: HTTP 429',
          retryAfter: retryAfterSeconds != null
              ? Duration(seconds: retryAfterSeconds)
              : null,
          uri: uri,
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.body;
      }

      throw NetworkException(
        'Space-Track returned HTTP ${response.statusCode}',
        statusCode: response.statusCode,
        uri: uri,
      );
    } on AuthenticationException {
      rethrow;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } on TimeoutException catch (e) {
      throw NetworkException(
        'Space-Track request timed out after $_timeout',
        uri: uri,
        cause: e,
      );
    } catch (e) {
      if (!isSocketException(e)) rethrow;
      throw NetworkException(
        'Space-Track socket error: $e',
        uri: uri,
        cause: e,
      );
    }
  }
}
