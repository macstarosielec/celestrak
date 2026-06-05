/// Public facade for fetching satellite GP data from Space-Track.org.
///
/// Wraps `SpaceTrackDataSource` with login management, JSON→`SatelliteTle`
/// parsing, and `TleSource.spacetrack` provenance stamping.
///
/// ## Authentication
///
/// Space-Track requires a registered account. Supply your credentials via
/// `identity` (email) and `password`. The facade calls login automatically
/// on the first `fetchByQuery` call. Credentials are kept in memory only
/// and are never written to disk.
///
/// ## Rate limiting
///
/// A minimum inter-request interval is enforced by the underlying data
/// source (default 2 seconds). Override via `minRequestInterval` at
/// construction time.
///
/// ## Error mapping
///
/// | Condition | Exception |
/// |-----------|-----------|
/// | Bad credentials / expired session | [AuthenticationException] |
/// | HTTP 429 | [RateLimitException] |
/// | Transport failure | [NetworkException] |
///
/// ## Example
///
/// ```dart
/// final client = SpaceTrackClient(
///   identity: 'user@example.com',
///   password: 'secret',
/// );
/// try {
///   final iss = await client.fetchByQuery(
///     SpaceTrackQuery.byNoradId(25544),
///   );
///   print(iss.source); // TleSource.spacetrack
/// } finally {
///   client.dispose();
/// }
/// ```
///
/// See also:
/// - [SpaceTrackQuery] — describes what to fetch.
/// - [AuthenticationException] — raised on 401/403.
/// - [RateLimitException] — raised on HTTP 429.
/// - [NetworkException] — raised on transport failures.
library;

import 'dart:convert' show jsonDecode;

import 'package:celestrak/src/client/spacetrack_query.dart';
import 'package:celestrak/src/data/parsers/omm_parser.dart';
import 'package:celestrak/src/data/remote/spacetrack_data_source.dart';
import 'package:celestrak/src/domain/clock.dart';
import 'package:celestrak/src/domain/enums.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/satellite_tle.dart';
import 'package:http/http.dart' as http;

/// High-level facade for the Space-Track.org GP API.
///
/// Handles authentication, JSON parsing, and [TleSource.spacetrack]
/// provenance stamping for every result. The underlying HTTP client is either
/// owned (created internally) or caller-supplied via
/// [SpaceTrackClient.withClient].
///
/// ## Credential gating
///
/// When `identity` or `password` is `null` or empty the client is
/// **disabled**: [isEnabled] returns `false`, construction succeeds without
/// error, but calling [fetchByQuery] throws a [StateError]. This allows
/// applications to construct a [SpaceTrackClient] unconditionally and gate on
/// [isEnabled] rather than wrapping construction in a try/catch.
///
/// ```dart
/// final client = SpaceTrackClient(
///   identity: Platform.environment['SPACETRACK_USER'],
///   password: Platform.environment['SPACETRACK_PASS'],
/// );
/// if (client.isEnabled) {
///   final tle = await client.fetchByQuery(SpaceTrackQuery.byNoradId(25544));
/// }
/// ```
///
/// ## Lifecycle
///
/// Instances created with the default [SpaceTrackClient.new] constructor
/// own their internal `http.Client`. Call [dispose] to release it.
///
/// Instances created with [SpaceTrackClient.withClient] do **not** own the
/// supplied client; the caller is responsible for closing it.
final class SpaceTrackClient {
  /// Creates a [SpaceTrackClient] that owns an internal `http.Client`.
  ///
  /// Call [dispose] when finished to close the owned client.
  ///
  /// [identity] and [password] are the Space-Track.org account credentials.
  /// Pass `null` or an empty string to create a **disabled** client that
  /// constructs without error but throws [StateError] on [fetchByQuery].
  ///
  /// [baseUrl] overrides the production Space-Track origin (for testing).
  ///
  /// [minRequestInterval] is the minimum time between successive data
  /// requests (default: 2 seconds).
  ///
  /// [timeout] is the per-request HTTP deadline.
  ///
  /// [clock] is the injectable time source used for rate-limit enforcement.
  /// See also: [isEnabled] — check whether credentials were accepted.
  SpaceTrackClient({
    String? identity,
    String? password,
    String baseUrl = kSpaceTrackBaseUrl,
    Duration minRequestInterval = kDefaultMinRequestInterval,
    Duration timeout = kSpaceTrackDefaultTimeout,
    Clock clock = const SystemClock(),
  }) : this._init(
          client: http.Client(),
          identity: identity,
          password: password,
          baseUrl: baseUrl,
          minRequestInterval: minRequestInterval,
          timeout: timeout,
          clock: clock,
          ownsClient: true,
        );

  /// Creates a [SpaceTrackClient] with a caller-supplied [http.Client].
  ///
  /// The client does **not** close [client] on [dispose]. The caller is
  /// responsible for managing the client lifecycle.
  ///
  /// [identity] and [password] are the Space-Track.org account credentials.
  /// Pass `null` or an empty string to create a **disabled** client.
  ///
  /// Use this constructor in tests to inject a mock HTTP client.
  SpaceTrackClient.withClient({
    required http.Client client,
    String? identity,
    String? password,
    String baseUrl = kSpaceTrackBaseUrl,
    Duration minRequestInterval = kDefaultMinRequestInterval,
    Duration timeout = kSpaceTrackDefaultTimeout,
    Clock clock = const SystemClock(),
  }) : this._init(
          client: client,
          identity: identity,
          password: password,
          baseUrl: baseUrl,
          minRequestInterval: minRequestInterval,
          timeout: timeout,
          clock: clock,
          ownsClient: false,
        );

  /// Private initialising constructor. Ownership tracking is expressed only
  /// here; external callers cannot set [ownsClient].
  SpaceTrackClient._init({
    required http.Client client,
    required String? identity,
    required String? password,
    required String baseUrl,
    required Duration minRequestInterval,
    required Duration timeout,
    required Clock clock,
    required bool ownsClient,
  })  : _dataSource = _hasCredentials(identity, password)
            ? SpaceTrackDataSource(
                client: client,
                identity: identity!,
                password: password!,
                baseUrl: baseUrl,
                minRequestInterval: minRequestInterval,
                timeout: timeout,
                clock: clock,
              )
            : null,
        _httpClient = client,
        _clock = clock,
        _ownsClient = ownsClient;

  /// Returns `true` when both [identity] and [password] are non-null and
  /// non-empty.
  ///
  /// Note: whitespace-only strings (e.g. `'   '`) are treated as valid
  /// credentials and passed to [SpaceTrackDataSource] as-is. If the
  /// Space-Track server rejects them, an [AuthenticationException] is raised.
  /// Trim your inputs before construction if whitespace-only should be treated
  /// as absent.
  static bool _hasCredentials(String? identity, String? password) =>
      identity != null &&
      identity.isNotEmpty &&
      password != null &&
      password.isNotEmpty;

  final SpaceTrackDataSource? _dataSource;
  final http.Client _httpClient;
  final Clock _clock;
  final bool _ownsClient;
  bool _disposed = false;

  static const _ommParser = OmmParser();

  /// `true` when credentials were supplied and the source is usable.
  ///
  /// When `false`, [fetchByQuery] throws [StateError] immediately without
  /// making any network request.
  bool get isEnabled => _dataSource != null;

  /// `true` if a successful login has been performed since construction.
  ///
  /// Always `false` when [isEnabled] is `false`.
  bool get isLoggedIn => _dataSource?.isLoggedIn ?? false;

  /// Fetches GP data for the satellite described by [query].
  ///
  /// Logs in automatically on the first call. If the session expires
  /// mid-session and a data request returns 401/403, the exception is surfaced
  /// to the caller (re-login is the caller's responsibility).
  ///
  /// Returns a [SatelliteTle] stamped with [TleSource.spacetrack].
  ///
  /// Throws [StateError] when [dispose] has already been called.
  ///
  /// Throws [StateError] when [isEnabled] is `false` (no credentials were
  /// supplied at construction time).
  ///
  /// Throws [AuthenticationException] on HTTP 401 or 403.
  ///
  /// Throws [RateLimitException] on HTTP 429.
  ///
  /// Throws [NetworkException] on transport failures.
  ///
  /// Throws [SatelliteNotFoundException] when the Space-Track response is an
  /// empty array (no record for the requested NORAD catalog number).
  Future<SatelliteTle> fetchByQuery(SpaceTrackQuery query) async {
    if (_disposed) {
      throw StateError('SpaceTrackClient has been disposed');
    }
    final source = _dataSource;
    if (source == null) {
      throw StateError(
        'SpaceTrackClient is disabled: no credentials were supplied. '
        'Provide a non-empty identity and password to enable Space-Track '
        'access, or check isEnabled before calling fetchByQuery.',
      );
    }
    if (!source.isLoggedIn) {
      await source.login();
    }

    final body = await source.fetchByNoradId(query.noradId);
    final fetchedAt = _clock.now;
    return _parseBody(body, query.noradId, fetchedAt);
  }

  /// Parses the Space-Track GP JSON response body into a [SatelliteTle].
  ///
  /// Space-Track returns a JSON array of GP objects. The array may be empty
  /// when no record exists, which maps to [SatelliteNotFoundException].
  ///
  /// Each GP object includes `TLE_LINE1` and `TLE_LINE2` fields, so no
  /// secondary TLE request is needed (unlike the CelesTrak OMM flow).
  SatelliteTle _parseBody(String body, int noradId, DateTime fetchedAt) {
    final decoded = jsonDecode(body);
    if (decoded is! List<dynamic>) {
      throw OmmParseException(
        'Space-Track returned an unexpected response format for NORAD ID '
        '$noradId (expected a JSON array, got ${decoded.runtimeType})',
        field: null,
      );
    }
    final list = decoded.cast<Map<String, dynamic>>();

    if (list.isEmpty) {
      throw SatelliteNotFoundException(
        'Space-Track returned no GP record for NORAD ID $noradId',
        noradId: noradId,
      );
    }

    // Space-Track filters by NORAD_CAT_ID in the URL, so the response contains
    // at most one record. The list.isEmpty guard above handles the "not found"
    // case; no secondary re-filter is needed.
    final gpJson = list.first;

    final omm = _ommParser.parse(gpJson);

    final raw1 = gpJson['TLE_LINE1'];
    final raw2 = gpJson['TLE_LINE2'];
    if (raw1 is! String?) {
      throw OmmParseException(
        'GP record for NORAD ID $noradId has unexpected type for TLE_LINE1: '
        '${raw1.runtimeType}',
        field: 'TLE_LINE1',
      );
    }
    if (raw2 is! String?) {
      throw OmmParseException(
        'GP record for NORAD ID $noradId has unexpected type for TLE_LINE2: '
        '${raw2.runtimeType}',
        field: 'TLE_LINE2',
      );
    }
    final line1 = raw1;
    final line2 = raw2;
    if (line1 == null || line1.isEmpty) {
      throw OmmParseException(
        'GP record for NORAD ID $noradId is missing TLE_LINE1',
        field: 'TLE_LINE1',
      );
    }
    if (line2 == null || line2.isEmpty) {
      throw OmmParseException(
        'GP record for NORAD ID $noradId is missing TLE_LINE2',
        field: 'TLE_LINE2',
      );
    }

    return SatelliteTle(
      noradId: omm.noradCatId,
      name: omm.objectName ?? '',
      line1: line1,
      line2: line2,
      epoch: omm.epoch,
      fetchedAt: fetchedAt,
      source: TleSource.spacetrack,
      omm: omm,
    );
  }

  /// Releases the internal `http.Client` if this instance owns it.
  ///
  /// Has no effect when the client was created via
  /// [SpaceTrackClient.withClient] (caller-owned lifecycle).
  ///
  /// Idempotent: calling [dispose] more than once is safe.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
