/// Remote data source for the CelesTrak GP API.
///
/// Builds and issues HTTP GET requests to the `gp.php` endpoint, mapping
/// the well-known `"No GP data found"` response to a typed
/// [SatelliteNotFoundException] (FR-23). All other transport failures
/// propagate as [NetworkException] from [HttpTransport].
library;

import 'package:celestrak/src/domain/enums.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/network/http_transport.dart';

/// Base URL for the CelesTrak GP catalog API.
///
/// Endpoint for individual object lookup by NORAD catalog number (`CATNR=`),
/// as published in the CelesTrak GP API documentation:
/// https://celestrak.org/NORAD/elements/gp.php
const String kCelestrakBaseUrl = 'https://celestrak.org/NORAD/elements/gp.php';

/// Sentinel text returned by CelesTrak when a NORAD ID is not in the catalog.
const String kNotFoundSentinel = 'No GP data found';

/// Raw-data access layer for the CelesTrak GP API (`gp.php`).
///
/// Constructs query URIs for individual objects by NORAD catalog number
/// (`CATNR=`), issues the request through [HttpTransport], and maps the
/// not-found sentinel to a [SatelliteNotFoundException] (FR-1, FR-5, FR-23).
///
/// All transport-level failures (timeouts, socket errors, 5xx after retries,
/// non-retryable 4xx) surface as [NetworkException] — they originate inside
/// [HttpTransport] and are never swallowed here.
final class CelestrakDataSource {
  /// Creates a [CelestrakDataSource] backed by [transport].
  ///
  /// [baseUrl] defaults to the production CelesTrak GP endpoint; override in
  /// tests to redirect requests without real network access.
  const CelestrakDataSource({
    required HttpTransport transport,
    String baseUrl = kCelestrakBaseUrl,
  })  : _transport = transport,
        _baseUrl = baseUrl;

  final HttpTransport _transport;
  final String _baseUrl;

  /// Fetches raw orbital data for a single satellite by NORAD catalog number.
  ///
  /// Builds a `gp.php?CATNR=<noradId>&FORMAT=<format>` URI (uppercase query
  /// keys, per the CelesTrak API contract — FR-1/FR-5), issues an HTTPS GET,
  /// and returns the response body verbatim.
  ///
  /// Throws [SatelliteNotFoundException] when the response body equals the
  /// CelesTrak not-found sentinel `"No GP data found"` (case-sensitive).
  ///
  /// Throws [NetworkException] on transport failures (propagated from
  /// [HttpTransport] without wrapping — FR-23).
  ///
  /// Throws [ArgumentError] if [noradId] is less than 1.
  Future<String> fetchByNoradId(
    int noradId, {
    CelestrakFormat format = CelestrakFormat.omm,
  }) async {
    if (noradId < 1) {
      throw ArgumentError.value(
        noradId,
        'noradId',
        'NORAD catalog numbers must be >= 1',
      );
    }

    final uri = _buildUri(
      queryKey: 'CATNR',
      queryValue: noradId.toString(),
      format: format,
    );

    final body = await _transport.get(uri);

    if (_isNotFound(body)) {
      throw SatelliteNotFoundException(
        'No GP data found for NORAD ID $noradId',
        noradId: noradId,
        uri: uri,
      );
    }

    return body;
  }

  /// Fetches raw orbital data for satellites matching a name substring.
  ///
  /// Builds a `gp.php?NAME=<name>&FORMAT=<format>` URI (uppercase query
  /// keys, per the CelesTrak API contract — FR-3), issues an HTTPS GET,
  /// and returns the response body verbatim.
  ///
  /// Returns the empty string when the response body equals the CelesTrak
  /// not-found sentinel `"No GP data found"` (case-sensitive). Callers
  /// should treat an empty string as a zero-result response (FR-3, US-5).
  ///
  /// Throws [NetworkException] on transport failures (propagated from
  /// [HttpTransport] without wrapping — FR-23).
  ///
  /// Throws [ArgumentError] if [name] is empty.
  Future<String> fetchByName(
    String name, {
    CelestrakFormat format = CelestrakFormat.omm,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'name must not be empty or whitespace-only',
      );
    }

    final uri = _buildUri(
      queryKey: 'NAME',
      queryValue: name,
      format: format,
    );

    // CelesTrak returns 404 (or 200 + sentinel) when no satellite matches
    // the name query.  Both map to an empty result (FR-3, US-5).
    final String body;
    try {
      body = await _transport.get(uri);
    } on NetworkException catch (e) {
      if (e.statusCode == 404) return '';
      rethrow;
    }

    if (_isNotFound(body)) return '';

    return body;
  }

  /// Fetches raw orbital data for a satellite group by CelesTrak group string.
  ///
  /// Builds a `gp.php?GROUP=<group>&FORMAT=<format>` URI (uppercase query
  /// keys, per the CelesTrak API contract — FR-2), issues an HTTPS GET,
  /// and returns the response body verbatim.
  ///
  /// Throws [SatelliteNotFoundException] when the response body equals the
  /// CelesTrak not-found sentinel `"No GP data found"` (case-sensitive),
  /// indicating the group name is unknown to CelesTrak. A sentinel `noradId`
  /// of 0 is used; callers should inspect the exception message for the group
  /// name.
  ///
  /// Throws [NetworkException] on transport failures (propagated from
  /// [HttpTransport] without wrapping — FR-23).
  ///
  /// Throws [ArgumentError] if [group] is empty.
  Future<String> fetchByGroup(
    String group, {
    CelestrakFormat format = CelestrakFormat.omm,
  }) async {
    if (group.isEmpty) {
      throw ArgumentError.value(
        group,
        'group',
        'group must not be empty',
      );
    }

    final uri = _buildUri(
      queryKey: 'GROUP',
      queryValue: group,
      format: format,
    );

    final body = await _transport.get(uri);

    if (_isNotFound(body)) {
      throw SatelliteNotFoundException(
        'No GP data found for group "$group"',
        noradId: 0,
        uri: uri,
      );
    }

    return body;
  }

  /// Builds a CelesTrak GP API [Uri] for the given query key/value and format.
  ///
  /// Query parameter names are uppercase (`CATNR`, `FORMAT`) per the API spec.
  ///
  /// Any query parameters already present on [_baseUrl] (e.g. an API-gateway
  /// `apikey=` parameter) are preserved and the new parameters are merged on
  /// top of them.
  Uri _buildUri({
    required String queryKey,
    required String queryValue,
    required CelestrakFormat format,
  }) {
    final base = Uri.parse(_baseUrl);
    final merged = Map<String, String>.from(base.queryParameters)
      ..addAll({
        queryKey: queryValue,
        'FORMAT': _formatString(format),
      });
    return base.replace(queryParameters: merged);
  }

  /// Returns the wire format string for [format].
  String _formatString(CelestrakFormat format) => switch (format) {
        CelestrakFormat.tle => 'TLE',
        CelestrakFormat.omm => 'JSON',
      };

  /// Returns `true` when [body] matches the CelesTrak not-found sentinel.
  ///
  /// The length guard avoids allocating a trimmed copy of large bodies (valid
  /// JSON or TLE data can be tens of kilobytes) on every successful response.
  ///
  /// `+2` allows for the two standard HTTP line-ending characters that an HTTP
  /// server may append to the response body: a single newline (`\n`, +1) or a
  /// CRLF pair (`\r\n`, +2). Bodies longer than this cannot be the sentinel,
  /// so trimming is skipped.
  bool _isNotFound(String body) =>
      body.length <= kNotFoundSentinel.length + 2 &&
      body.trim() == kNotFoundSentinel;
}
