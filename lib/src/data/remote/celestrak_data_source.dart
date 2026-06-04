/// Remote data source for the CelesTrak GP API.
///
/// Builds and issues HTTP GET requests to the `gp.php` endpoint, mapping
/// the well-known `"No GP data found"` response to a typed
/// [SatelliteNotFoundException]. All other transport failures
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
/// not-found sentinel to a [SatelliteNotFoundException].
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
  /// keys, per the CelesTrak API contract), issues an HTTPS GET,
  /// and returns the response body verbatim.
  ///
  /// Throws [SatelliteNotFoundException] when the response body equals the
  /// CelesTrak not-found sentinel `"No GP data found"` (case-sensitive).
  ///
  /// Throws [NetworkException] on transport failures (propagated from
  /// [HttpTransport] without wrapping).
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
  /// keys, per the CelesTrak API contract), issues an HTTPS GET,
  /// and returns the response body verbatim.
  ///
  /// Returns the empty string when the response body equals the CelesTrak
  /// not-found sentinel `"No GP data found"` (case-sensitive). Callers
  /// should treat an empty string as a zero-result response.
  ///
  /// Throws [NetworkException] on transport failures (propagated from
  /// [HttpTransport] without wrapping).
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

    // CelesTrak returns HTTP 404 (or HTTP 200 + sentinel body) when no
    // satellite matches a NAME= query. Both cases map to an empty-string
    // result. This 404 suppression follows the documented CelesTrak GP API
    // contract — it is not a general "ignore all 404s" policy. Other 4xx/5xx
    // status codes (e.g. 400 Bad Request, 503 Service Unavailable) are still
    // surfaced as NetworkException by the rethrow below.
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

  /// Fetches raw orbital data for satellites matching an international
  /// designator.
  ///
  /// Builds a `gp.php?INTDES=<intlDesignator>&FORMAT=<format>` URI (uppercase
  /// query keys, per the CelesTrak API contract), issues an HTTPS GET,
  /// and returns the response body verbatim.
  ///
  /// Returns the empty string when the response body equals the CelesTrak
  /// not-found sentinel `"No GP data found"` (case-sensitive). Callers should
  /// treat an empty string as a zero-result response.
  ///
  /// International designators must match the pattern:
  /// `YYYY-NNNP` where `YYYY` is a 4-digit launch year (1957–2999), `NNN` is
  /// a 1–3 digit launch number, and `P` is a 1–3 letter piece identifier. The
  /// year and number components may optionally be separated by a hyphen.
  /// Leading/trailing whitespace is not permitted.
  ///
  /// Throws [ArgumentError] when [intlDesignator] is malformed.
  ///
  /// Throws [NetworkException] on transport failures (propagated from
  /// [HttpTransport] without wrapping).
  Future<String> fetchByIntlDesignator(
    String intlDesignator, {
    CelestrakFormat format = CelestrakFormat.omm,
  }) async {
    final trimmed = _validateIntlDesignator(intlDesignator);

    final uri = _buildUri(
      queryKey: 'INTDES',
      queryValue: trimmed,
      format: format,
    );

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
  /// keys, per the CelesTrak API contract), issues an HTTPS GET,
  /// and returns the response body verbatim.
  ///
  /// Throws [SatelliteNotFoundException] when the response body equals the
  /// CelesTrak not-found sentinel `"No GP data found"` (case-sensitive),
  /// indicating the group name is unknown to CelesTrak. A sentinel `noradId`
  /// of 0 is used; callers should inspect the exception message for the group
  /// name.
  ///
  /// Throws [NetworkException] on transport failures (propagated from
  /// [HttpTransport] without wrapping).
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

  /// Regex for international designators: 4-digit year (1957–2999), optional
  /// hyphen, 1–3 digit launch number, 1–3 letter piece identifier.
  ///
  /// Allocated once as a static field to avoid per-call allocation.
  static final _intlDesPattern =
      RegExp(r'^(195[7-9]|19[6-9]\d|[2-9]\d{3})-?\d{1,3}[A-Za-z]{1,3}$');

  /// Returns `true` when [value] is a structurally valid international
  /// designator after trimming.
  ///
  /// Valid format: `YYYY-NNNP…` where `YYYY` is 1957–2999, `NNN` is 1–3
  /// digits, and `P…` is 1–3 letters. The hyphen is optional.
  ///
  /// This method is provided for callers that need to validate a designator
  /// before a cache read — before the value reaches [fetchByIntlDesignator].
  static bool isValidIntlDesignator(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && _intlDesPattern.hasMatch(trimmed);
  }

  /// Validates an international designator string and returns the trimmed form.
  ///
  /// Valid format: `YYYY-NNNP…` where:
  /// - `YYYY` is a 4-digit year (1957–2999).
  /// - `NNN` is 1–3 digits (launch number within year).
  /// - `P…` is 1–3 letters (piece identifier).
  ///
  /// Leading/trailing whitespace is not accepted (the value after trimming must
  /// not differ from the original — callers must pass a clean string).
  ///
  /// Throws [ArgumentError] when the designator does not match.
  ///
  /// Returns the trimmed designator string for callers to forward to the API.
  String _validateIntlDesignator(String value) {
    // Reject leading/trailing whitespace outright: a padded designator would
    // produce a malformed URI query value if forwarded verbatim.
    final trimmed = value.trim();
    if (trimmed.isEmpty || !_intlDesPattern.hasMatch(trimmed)) {
      throw ArgumentError.value(
        value,
        'intlDesignator',
        'International designator must match YYYY-NNNP… '
            '(e.g. "1998-067A"). Got: "$value"',
      );
    }
    return trimmed;
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
