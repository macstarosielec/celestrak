/// Remote data source for the CelesTrak SATCAT API.
///
/// Builds and issues HTTP GET requests to the `satcat/records.php` endpoint,
/// then parses the response into [SatcatEntry] values via [SatcatParser].
/// Single-record (`CATNR`) misses map to a typed [SatelliteNotFoundException];
/// all other transport failures propagate as [NetworkException] from
/// [HttpTransport].
///
/// SATCAT is a dataset distinct from GP/OMM (ADR-14), so this data source is a
/// separate concern from the GP `CelestrakDataSource`: its own URLs, its own
/// parser, and (from P9.5) its own cache namespace. It does not extend or reuse
/// the GP data source.
library;

import 'dart:convert' show jsonDecode;

import 'package:celestrak/src/data/parsers/satcat_parser.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/satcat_entry.dart';
import 'package:celestrak/src/network/http_transport.dart';

/// Base URL for the CelesTrak SATCAT query API.
///
/// Endpoint for catalogue lookups by NORAD number (`CATNR=`), group
/// (`GROUP=`), or international designator (`INTDES=`), as published in the
/// CelesTrak SATCAT documentation: https://celestrak.org/satcat/
const String kSatcatBaseUrl = 'https://celestrak.org/satcat/records.php';

/// CelesTrak group string for the full active-catalogue SATCAT query.
///
/// The SATCAT endpoint has no unqualified "everything" query; the documented
/// full-catalogue form is `GROUP=active` (plan section 2). Callers that want a
/// narrower slice pass an explicit group to [SatcatDataSource.fetchByGroup].
const String kSatcatFullCatalogGroup = 'active';

/// Wire format string for SATCAT requests.
///
/// JSON is the default per the plan (forward-compatible with 6+ digit catalog
/// numbers; avoids the deprecated legacy fixed-field SATCAT format).
const String _kSatcatJsonFormat = 'JSON';

/// Raw-data access layer for the CelesTrak SATCAT API (`satcat/records.php`).
///
/// Constructs query URIs (uppercase keys, HTTPS only), issues the request
/// through [HttpTransport], and parses the response with [SatcatParser]:
/// - [fetchByNoradId] takes the single-record path: an absent record maps to
///   [SatelliteNotFoundException]; a malformed body raises
///   [SatcatParseException].
/// - [fetchByGroup], [fetchByIntlDesignator], and [fetchAll] take the bulk
///   path: zero matches yield an **empty list** (never an exception).
///   Non-object array elements (e.g. a stray JSON scalar) are silently
///   pre-filtered out before parsing, and malformed *object* rows are skipped
///   by [SatcatParser]. These methods return only the parsed [SatcatEntry]
///   values; no skip count is surfaced at this layer.
///
/// All transport-level failures (timeouts, socket errors, 5xx after retries,
/// non-retryable 4xx) surface as [NetworkException] - they originate inside
/// [HttpTransport] and are never swallowed here.
final class SatcatDataSource {
  /// Creates a [SatcatDataSource] backed by [transport].
  ///
  /// [baseUrl] defaults to the production CelesTrak SATCAT endpoint; override
  /// in tests to redirect requests without real network access. [parser] is
  /// injectable for testing but defaults to a `const SatcatParser()`.
  const SatcatDataSource({
    required HttpTransport transport,
    String baseUrl = kSatcatBaseUrl,
    SatcatParser parser = const SatcatParser(),
  })  : _transport = transport,
        _baseUrl = baseUrl,
        _parser = parser;

  final HttpTransport _transport;
  final String _baseUrl;
  final SatcatParser _parser;

  /// Fetches the SATCAT metadata record for a single satellite by NORAD
  /// catalog number.
  ///
  /// Builds a `satcat/records.php?CATNR=<noradId>&FORMAT=JSON` URI (uppercase
  /// query keys, per the CelesTrak API contract) and issues an HTTPS GET.
  ///
  /// Throws [SatelliteNotFoundException] when CelesTrak returns no record for
  /// [noradId] (the CelesTrak "No ... data found" sentinel, an empty body, or
  /// an empty JSON array).
  ///
  /// Throws [SatcatParseException] when the body is present but malformed.
  ///
  /// Throws [NetworkException] on transport failures (propagated from
  /// [HttpTransport] without wrapping).
  ///
  /// Throws [ArgumentError] if [noradId] is less than 1.
  Future<SatcatEntry> fetchByNoradId(int noradId) async {
    if (noradId < 1) {
      throw ArgumentError.value(
        noradId,
        'noradId',
        'NORAD catalog numbers must be >= 1',
      );
    }

    final uri = _buildUri(queryKey: 'CATNR', queryValue: noradId.toString());
    final body = await _transport.get(uri);

    final record = _singleRecordOrNull(body);
    if (record == null) {
      throw SatelliteNotFoundException(
        'No SATCAT data found for NORAD ID $noradId',
        noradId: noradId,
        uri: uri,
      );
    }

    return _parser.parseJson(record);
  }

  /// Fetches the SATCAT metadata records for a satellite group by CelesTrak
  /// group string.
  ///
  /// Builds a `satcat/records.php?GROUP=<group>&FORMAT=JSON` URI (uppercase
  /// query keys, per the CelesTrak API contract) and issues an HTTPS GET.
  ///
  /// Returns an **empty list** when the group matches no records (a zero
  /// result is never thrown). Non-object array elements are silently
  /// pre-filtered out, and malformed *object* rows are skipped by
  /// [SatcatParser]; this method surfaces only the parsed entries (no skip
  /// count is returned).
  ///
  /// Throws [NetworkException] on transport failures (propagated from
  /// [HttpTransport] without wrapping).
  ///
  /// Throws [ArgumentError] if [group] is empty.
  Future<List<SatcatEntry>> fetchByGroup(String group) async {
    if (group.trim().isEmpty) {
      throw ArgumentError.value(
        group,
        'group',
        'group must not be empty or whitespace-only',
      );
    }

    final uri = _buildUri(queryKey: 'GROUP', queryValue: group.trim());
    return _fetchList(uri);
  }

  /// Fetches the SATCAT metadata records matching an international designator.
  ///
  /// Builds a `satcat/records.php?INTDES=<intlDesignator>&FORMAT=JSON` URI
  /// (uppercase query keys, per the CelesTrak API contract) and issues an
  /// HTTPS GET.
  ///
  /// The designator is passed verbatim; CelesTrak performs the matching. A
  /// partial designator (e.g. a launch-year prefix `1998-067`) matches every
  /// piece of that launch, so this is a bulk path.
  ///
  /// Returns an **empty list** when the designator matches no records (a zero
  /// result is never thrown).
  ///
  /// Throws [NetworkException] on transport failures (propagated from
  /// [HttpTransport] without wrapping).
  ///
  /// Throws [ArgumentError] if [intlDesignator] is empty.
  Future<List<SatcatEntry>> fetchByIntlDesignator(
    String intlDesignator,
  ) async {
    if (intlDesignator.trim().isEmpty) {
      throw ArgumentError.value(
        intlDesignator,
        'intlDesignator',
        'international designator must not be empty or whitespace-only',
      );
    }

    final uri = _buildUri(
      queryKey: 'INTDES',
      queryValue: intlDesignator.trim(),
    );
    return _fetchList(uri);
  }

  /// Fetches the full active SATCAT catalogue.
  ///
  /// Builds a `satcat/records.php?GROUP=active&FORMAT=JSON` URI: the SATCAT
  /// endpoint has no unqualified "everything" form, so the documented
  /// full-catalogue query (plan section 2) is used. The result is tens of
  /// thousands of records; see the plan's size note. Returns an **empty list**
  /// when the catalogue is empty (never thrown).
  ///
  /// Throws [NetworkException] on transport failures (propagated from
  /// [HttpTransport] without wrapping).
  Future<List<SatcatEntry>> fetchAll() async {
    final uri = _buildUri(
      queryKey: 'GROUP',
      queryValue: kSatcatFullCatalogGroup,
    );
    return _fetchList(uri);
  }

  /// Issues the request at [uri] and parses the body as a bulk SATCAT list.
  ///
  /// An empty body or empty JSON array yields an empty list. Non-object array
  /// elements are silently pre-filtered by [_decodeList] before parsing;
  /// malformed *object* rows are then skipped by [SatcatParser.parseJsonList].
  /// Only the parsed entries are returned.
  Future<List<SatcatEntry>> _fetchList(Uri uri) async {
    final body = await _transport.get(uri);
    final rows = _decodeList(body);
    if (rows.isEmpty) return const [];
    return _parser.parseJsonList(rows).entries;
  }

  /// Decodes a single-record SATCAT response into a JSON object, or `null`
  /// when CelesTrak signalled no record (the no-data sentinel, an empty body,
  /// or an empty array).
  ///
  /// CelesTrak wraps a `FORMAT=JSON` `CATNR` lookup in a JSON array; a present
  /// record is its first element. A bare object body is also accepted for
  /// robustness.
  Map<String, dynamic>? _singleRecordOrNull(String body) {
    if (_isNoDataSentinel(body)) return null;

    final decoded = _decodeJson(body);
    if (decoded is List) {
      if (decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is Map<String, dynamic>) return first;
      throw const SatcatParseException(
        'expected a JSON object in the SATCAT array',
      );
    }
    if (decoded is Map<String, dynamic>) return decoded;
    throw const SatcatParseException(
      'expected a JSON object or array for a single SATCAT record',
    );
  }

  /// Decodes a bulk SATCAT response into a list of JSON objects.
  ///
  /// An empty body or the CelesTrak no-data sentinel yields an empty list. A
  /// top-level JSON object (the
  /// shape CelesTrak uses for a single record) is wrapped in a one-element
  /// list so callers can treat every bulk response uniformly.
  ///
  /// Within a top-level array, any non-object element (e.g. a stray scalar) is
  /// silently dropped here, before [SatcatParser] sees the rows; such elements
  /// are not counted as skipped rows by the parser.
  List<Map<String, dynamic>> _decodeList(String body) {
    if (_isNoDataSentinel(body)) return const [];

    final decoded = _decodeJson(body);
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    if (decoded is Map<String, dynamic>) return [decoded];
    throw const SatcatParseException(
      'expected a JSON array for a SATCAT list response',
    );
  }

  /// Decodes [body] as JSON, mapping a malformed payload to a typed
  /// [SatcatParseException] so no raw [FormatException] escapes the data layer.
  Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException catch (e) {
      throw SatcatParseException('malformed SATCAT JSON: ${e.message}');
    }
  }

  /// Builds a CelesTrak SATCAT API [Uri] for the given query key/value.
  ///
  /// Query parameter names are uppercase (`CATNR`, `GROUP`, `INTDES`, `FORMAT`)
  /// per the API spec, and `FORMAT=JSON` is always set. Any query parameters
  /// already present on [_baseUrl] (e.g. an API-gateway `apikey=` parameter)
  /// are preserved and the new parameters are merged on top of them.
  Uri _buildUri({
    required String queryKey,
    required String queryValue,
  }) {
    final base = Uri.parse(_baseUrl);
    final merged = Map<String, String>.from(base.queryParameters)
      ..addAll({
        queryKey: queryValue,
        'FORMAT': _kSatcatJsonFormat,
      });
    return base.replace(queryParameters: merged);
  }
}

/// Matches the CelesTrak "no data" plain-text response.
///
/// For `FORMAT=JSON` requests CelesTrak returns a short text message (not JSON)
/// when a query matches nothing: `gp.php` returns "No GP data found" and the
/// SATCAT endpoint returns "No SATCAT data found". This pattern covers that
/// family ("No &lt;source&gt; data found"), so a no-match resolves to a
/// not-found / empty result rather than a parse error. A genuinely malformed
/// JSON body does not match and still surfaces as a [SatcatParseException].
final RegExp _noDataSentinel = RegExp(
  r'^no\s+(?:\w+\s+)?data\s+found\.?$',
  caseSensitive: false,
);

/// Whether [body] is a CelesTrak no-data response: an empty body, or the
/// "No ... data found" sentinel.
bool _isNoDataSentinel(String body) {
  final trimmed = body.trim();
  return trimmed.isEmpty || _noDataSentinel.hasMatch(trimmed);
}
