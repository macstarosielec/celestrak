/// Error types raised by the celestrak package.
///
/// Every failure is surfaced as a typed exception under a single sealed
/// [CelestrakException] base, so callers can handle them exhaustively in a
/// `switch`. No raw `http` or `dart:io` exception escapes the public API.
///
/// See also:
/// - [ADR-0012: error strategy](https://github.com/macstarosielec/celestrak/blob/main/doc/adr/0012-error-strategy.md)
library;

import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException;

/// Base type for every error raised by the celestrak package.
///
/// Sealed: all subtypes are declared in this library, which lets consumers
/// handle failures exhaustively in a `switch`.
sealed class CelestrakException implements Exception {
  /// Creates a [CelestrakException] with a human-readable [message].
  const CelestrakException(this.message);

  /// Human-readable explanation of the failure.
  final String message;

  @override
  String toString() => 'CelestrakException: $message';
}

/// Thrown when CelesTrak OMM JSON cannot be parsed into an `Omm`.
///
/// [field] names the offending OMM keyword when the failure is specific to a
/// single field (missing, null, or an unexpected type or format).
final class OmmParseException extends CelestrakException {
  /// Creates an [OmmParseException] describing [message], optionally for a
  /// specific OMM [field].
  const OmmParseException(super.message, {this.field});

  /// The OMM keyword that failed to parse, when applicable.
  final String? field;

  @override
  String toString() => field == null
      ? 'OmmParseException: $message'
      : 'OmmParseException($field): $message';
}

/// Thrown when an HTTP request fails after all retry attempts are exhausted,
/// or immediately on a non-retryable error (e.g. a 4xx response).
///
/// [statusCode] is the HTTP status code of the last response, when available.
/// [uri] is the target URI of the failing request.
/// [cause] is the underlying exception that triggered the failure, when
/// available (e.g. a [TimeoutException] or [SocketException]).
final class NetworkException extends CelestrakException {
  /// Creates a [NetworkException] describing [message].
  const NetworkException(
    super.message, {
    this.statusCode,
    this.uri,
    this.cause,
  });

  /// The HTTP status code of the last response, if one was received.
  final int? statusCode;

  /// The URI that the request was sent to.
  final Uri? uri;

  /// The underlying exception that caused the failure, if available.
  final Object? cause;

  @override
  String toString() {
    final parts = <String>['NetworkException: $message'];
    if (statusCode != null) parts.add('statusCode=$statusCode');
    if (uri != null) parts.add('uri=$uri');
    if (cause != null) parts.add('cause=${cause.runtimeType}');
    return parts.join(', ');
  }
}

/// Thrown when CelesTrak reports no data for the requested object.
///
/// This is raised when the remote response body is the well-known sentinel
/// `"No GP data found"`, indicating that the requested NORAD catalog ID is
/// not present in the CelesTrak database.
///
/// [noradId] is the catalog number that was queried for per-object lookups.
/// For group or category queries (e.g. fetchCategory or fetchCategoryByGroup),
/// where no single catalog number applies, [noradId] is `0` — a sentinel
/// value, not a real catalog number. Do not use [noradId] to determine what
/// was queried in those contexts; inspect [uri] or [message] instead.
///
/// [uri] is the request URI.
final class SatelliteNotFoundException extends CelestrakException {
  /// Creates a [SatelliteNotFoundException] for [noradId] at [uri].
  const SatelliteNotFoundException(
    super.message, {
    required this.noradId,
    this.uri,
  });

  /// The NORAD catalog number that was not found, or `0` when the exception
  /// relates to a group or category query rather than a per-object lookup.
  final int noradId;

  /// The URI that returned the not-found sentinel.
  final Uri? uri;

  @override
  String toString() {
    final parts = <String>[
      'SatelliteNotFoundException: $message',
      'noradId=$noradId',
    ];
    if (uri != null) parts.add('uri=$uri');
    return parts.join(', ');
  }
}

/// Thrown when Space-Track.org rejects the supplied credentials or the session
/// has expired.
///
/// Space-Track returns HTTP 401 when the `identity`/`password` POST fails, and
/// HTTP 403 when the session cookie is missing or expired on a data request.
/// Both map to this exception so callers can handle authentication failures
/// with a single pattern.
///
/// [statusCode] is the HTTP status code returned by the server.
/// [uri] is the request URI that triggered the failure.
final class AuthenticationException extends CelestrakException {
  /// Creates an [AuthenticationException] describing [message].
  const AuthenticationException(
    super.message, {
    required this.statusCode,
    this.uri,
  });

  /// The HTTP status code returned by the server (401 or 403).
  final int statusCode;

  /// The URI that returned the authentication error.
  final Uri? uri;

  @override
  String toString() {
    final parts = <String>[
      'AuthenticationException: $message',
      'statusCode=$statusCode',
    ];
    if (uri != null) parts.add('uri=$uri');
    return parts.join(', ');
  }
}

/// Thrown when Space-Track.org returns HTTP 429 (Too Many Requests).
///
/// Space-Track enforces a rate limit of 30 requests per minute and 300
/// requests per hour. Exceeding either limit causes the server to respond
/// with 429. Callers should back off and retry after a delay.
///
/// [retryAfter] is parsed from the `Retry-After` response header when present.
/// [uri] is the request URI that was throttled.
final class RateLimitException extends CelestrakException {
  /// Creates a [RateLimitException] describing [message].
  const RateLimitException(super.message, {this.retryAfter, this.uri});

  /// The duration to wait before retrying, parsed from the `Retry-After`
  /// response header. `null` when the header was absent or could not be parsed.
  final Duration? retryAfter;

  /// The URI that returned the 429 response.
  final Uri? uri;

  @override
  String toString() {
    final parts = <String>['RateLimitException: $message'];
    final r = retryAfter;
    if (r != null) parts.add('retryAfter=${r.inSeconds}s');
    if (uri != null) parts.add('uri=$uri');
    return parts.join(', ');
  }
}

/// Thrown when a raw TLE string cannot be parsed into a `SatelliteTle`.
///
/// [field] identifies the offending TLE line when the failure is specific
/// (e.g. `'line1'` for a bad checksum or truncated epoch field).
final class TleParseException extends CelestrakException {
  /// Creates a [TleParseException] describing [message], optionally for a
  /// specific TLE [field].
  const TleParseException(super.message, {this.field});

  /// The TLE field that failed to parse, when applicable.
  final String? field;

  @override
  String toString() => field == null
      ? 'TleParseException: $message'
      : 'TleParseException($field): $message';
}

/// Thrown when a cache-only (`forceCache: true`) fetch finds no cached entry,
/// or when a required companion cache sub-key (e.g. the TLE sub-key for an
/// OMM stitch) is absent.
///
/// This is raised when `forceCache` is `true` and the cache store contains no
/// entry for the requested key, or when a companion cache sub-key is
/// independently evicted mid-read. No network request is ever made when
/// `forceCache` is `true`.
///
/// Callers that encounter this exception from a `forceCache: true` request
/// should retry the same fetch without `forceCache` to allow the library to
/// refresh both sub-keys from the network.
///
/// [key] is the cache key that was not found.
final class CacheMissException extends CelestrakException {
  /// Creates a [CacheMissException] for the given cache [key].
  const CacheMissException(super.message, {required this.key});

  /// The cache key for which no entry was found.
  final String key;

  @override
  String toString() => 'CacheMissException($key): $message';
}
