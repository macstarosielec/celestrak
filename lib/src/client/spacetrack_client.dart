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
/// and are never written to disk (NFR-15).
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
  ///
  /// [baseUrl] overrides the production Space-Track origin (for testing).
  ///
  /// [minRequestInterval] is the minimum time between successive data
  /// requests (default: 2 seconds, per ADR-7).
  ///
  /// [timeout] is the per-request HTTP deadline.
  ///
  /// [clock] is the injectable time source used for rate-limit enforcement.
  SpaceTrackClient({
    required String identity,
    required String password,
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
  /// Use this constructor in tests to inject a mock HTTP client.
  SpaceTrackClient.withClient({
    required http.Client client,
    required String identity,
    required String password,
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

  SpaceTrackClient._init({
    required http.Client client,
    required String identity,
    required String password,
    required String baseUrl,
    required Duration minRequestInterval,
    required Duration timeout,
    required Clock clock,
    required bool ownsClient,
  })  : _dataSource = SpaceTrackDataSource(
          client: client,
          identity: identity,
          password: password,
          baseUrl: baseUrl,
          minRequestInterval: minRequestInterval,
          timeout: timeout,
          clock: clock,
        ),
        _httpClient = client,
        _clock = clock,
        _ownsClient = ownsClient;

  final SpaceTrackDataSource _dataSource;
  final http.Client _httpClient;
  final Clock _clock;
  final bool _ownsClient;
  bool _disposed = false;

  static const _ommParser = OmmParser();

  /// `true` if a successful login has been performed since construction.
  bool get isLoggedIn => _dataSource.isLoggedIn;

  /// Fetches GP data for the satellite described by [query].
  ///
  /// Logs in automatically on the first call. If the session expires
  /// mid-session and a data request returns 401/403, the exception is surfaced
  /// to the caller (re-login is the caller's responsibility).
  ///
  /// Returns a [SatelliteTle] stamped with [TleSource.spacetrack].
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
    if (!_dataSource.isLoggedIn) {
      await _dataSource.login();
    }

    final body = await _dataSource.fetchByNoradId(query.noradId);
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
    final list =
        (jsonDecode(body) as List<dynamic>).cast<Map<String, dynamic>>();

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

    final line1 = gpJson['TLE_LINE1'] as String?;
    final line2 = gpJson['TLE_LINE2'] as String?;
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
