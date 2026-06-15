/// Parsing of CelesTrak SATCAT JSON and CSV into [SatcatEntry] domain models.
library;

import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/satcat_entry.dart';
import 'package:meta/meta.dart';

/// Outcome of a bulk (multi-record) SATCAT parse.
///
/// Carries the successfully parsed [entries] alongside the number of rows that
/// were [skipped] because they failed to yield a valid [SatcatEntry] (per the
/// lenient bulk tolerance rule: one bad row is never fatal). A clean parse has
/// `skipped == 0`.
@immutable
final class SatcatParseResult {
  /// Creates a [SatcatParseResult] from [entries] and the [skipped] count.
  ///
  /// [entries] is wrapped in an unmodifiable view so a retained reference to
  /// the result cannot mutate the parsed records.
  SatcatParseResult({
    required List<SatcatEntry> entries,
    required this.skipped,
  }) : entries = List.unmodifiable(entries);

  /// The records that parsed successfully, in source order. Unmodifiable.
  final List<SatcatEntry> entries;

  /// The number of source rows skipped because they failed to parse.
  final int skipped;

  @override
  bool operator ==(Object other) =>
      other is SatcatParseResult &&
      other.skipped == skipped &&
      _listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(skipped, Object.hashAll(entries));

  @override
  String toString() =>
      'SatcatParseResult(entries: ${entries.length}, skipped: $skipped)';
}

bool _listEquals(List<SatcatEntry> a, List<SatcatEntry> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Parses CelesTrak SATCAT records (JSON or CSV) into [SatcatEntry] values.
///
/// The parser is stateless; construct once (`const SatcatParser()`) and reuse.
/// Field mapping is delegated to [SatcatEntry.fromCelestrakJson], so the JSON
/// and CSV paths yield identical results for the same logical records (CSV
/// columns are mapped to the same field names before delegation).
///
/// Tolerance follows the SATCAT plan:
/// - **Single-record** parses ([parseJson], [parseCsv]) throw a
///   [SatcatParseException] on a malformed, empty, or `NORAD_CAT_ID`-less body.
/// - **Bulk** parses ([parseJsonList], [parseCsvList]) skip and count any row
///   that fails to yield a valid record; they never throw on one bad row.
final class SatcatParser {
  /// Creates a [SatcatParser].
  const SatcatParser();

  /// Parses a single CelesTrak SATCAT JSON object into a [SatcatEntry].
  ///
  /// [json] keys are the uppercase CelesTrak SATCAT field names. Throws a
  /// [SatcatParseException] when the required `NORAD_CAT_ID` is missing or not
  /// an integer, or when any other field mapping fails.
  ///
  /// Matching the [OmmParseException] precedent, [SatcatParseException.field]
  /// is left `null` on this path; the offending key (when one applies) is named
  /// in the message rather than the structured `field`. The same holds for
  /// [parseCsv] and the bulk variants.
  SatcatEntry parseJson(Map<String, dynamic> json) {
    try {
      return SatcatEntry.fromCelestrakJson(json);
    } on FormatException catch (e) {
      throw SatcatParseException(e.message);
    }
  }

  /// Parses a decoded CelesTrak SATCAT JSON array into a [SatcatParseResult].
  ///
  /// The [jsonList] (the top-level `List<Map<String, dynamic>>`) must already
  /// be decoded by the caller via `jsonDecode`. A row that fails to yield a
  /// valid [SatcatEntry] is skipped and counted in
  /// [SatcatParseResult.skipped]; this method never throws on one bad row.
  SatcatParseResult parseJsonList(List<Map<String, dynamic>> jsonList) {
    final entries = <SatcatEntry>[];
    var skipped = 0;
    for (final json in jsonList) {
      try {
        entries.add(SatcatEntry.fromCelestrakJson(json));
      } on FormatException {
        skipped++;
      }
    }
    return SatcatParseResult(entries: entries, skipped: skipped);
  }

  /// Parses a single-record CelesTrak SATCAT CSV document into a [SatcatEntry].
  ///
  /// [csv] must contain a header row followed by exactly one data row. Throws a
  /// [SatcatParseException] when the body is empty, carries no data row, or the
  /// single row fails to parse (e.g. missing `NORAD_CAT_ID`).
  SatcatEntry parseCsv(String csv) {
    final rows = _parseCsvRows(csv);
    if (rows.length < 2) {
      throw const SatcatParseException(
        'expected a header row and one data row',
      );
    }
    // Header validation is deferred to [SatcatEntry.fromCelestrakJson]: a
    // missing `NORAD_CAT_ID` column simply produces no `NORAD_CAT_ID` key in
    // the mapped row, which the model surfaces as a FormatException. A
    // header-less or wrong CSV therefore still throws here.
    final header = rows.first;
    try {
      return SatcatEntry.fromCelestrakJson(_rowToMap(header, rows[1]));
    } on FormatException catch (e) {
      throw SatcatParseException(e.message);
    }
  }

  /// Parses a multi-record CelesTrak SATCAT CSV document into a
  /// [SatcatParseResult].
  ///
  /// [csv] must contain a header row followed by zero or more data rows. A data
  /// row that fails to yield a valid [SatcatEntry] is skipped and counted in
  /// [SatcatParseResult.skipped]; this method never throws on one bad row. An
  /// empty or header-only document yields an empty result with `skipped == 0`.
  SatcatParseResult parseCsvList(String csv) {
    final rows = _parseCsvRows(csv);
    if (rows.isEmpty) {
      return SatcatParseResult(entries: const [], skipped: 0);
    }
    final header = rows.first;
    final entries = <SatcatEntry>[];
    var skipped = 0;
    for (var i = 1; i < rows.length; i++) {
      try {
        entries.add(SatcatEntry.fromCelestrakJson(_rowToMap(header, rows[i])));
      } on FormatException {
        skipped++;
      }
    }
    return SatcatParseResult(entries: entries, skipped: skipped);
  }

  /// Maps a CSV data row onto a `Map` keyed by the [header] column names,
  /// so the result can be fed to [SatcatEntry.fromCelestrakJson] for free
  /// CSV/JSON parity. Columns beyond the header length are ignored; missing
  /// trailing columns are treated as absent. Empty cells are dropped so the
  /// model's null/`N/A` tolerance applies uniformly.
  Map<String, dynamic> _rowToMap(List<String> header, List<String> row) {
    final map = <String, dynamic>{};
    for (var i = 0; i < header.length; i++) {
      final key = header[i].trim();
      if (key.isEmpty) continue;
      final value = i < row.length ? row[i] : '';
      if (value.isEmpty) continue;
      map[key] = value;
    }
    return map;
  }
}

/// Splits a CSV document into a list of rows, each a list of unescaped fields.
///
/// Quoting rules (a lenient superset of RFC-4180):
/// - A double-quote opens a quoted region **only** when it is the first
///   character of a field (the field buffer is empty and we are not already
///   inside a quoted region). Inside a quoted region a comma, newline, or a
///   doubled (`""`) literal quote is preserved verbatim; a lone `"` closes the
///   region.
/// - A double-quote anywhere else in an unquoted field (i.e. after other
///   characters) is treated as a **literal character**, not a quote opener.
///   This prevents silent data loss on non-RFC input such as `he"llo`.
/// - Both `\n` and `\r\n` line endings are accepted. Blank lines (no fields)
///   are skipped. A leading UTF-8 BOM (`﻿`) is stripped.
///
/// Throws a [SatcatParseException] if the document ends while still inside a
/// quoted region: an unterminated quote corrupts every subsequent row boundary,
/// so it is a document-level error rather than a skippable single row.
List<List<String>> _parseCsvRows(String csv) {
  // Strip a leading UTF-8 BOM so a BOM-prefixed header parses correctly.
  final input = csv.startsWith('﻿') ? csv.substring(1) : csv;

  final rows = <List<String>>[];
  var fields = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var sawAnyChar = false;

  void endField() {
    fields.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    // Skip blank lines (a single empty field with nothing typed before it).
    if (!(fields.length == 1 && fields.first.isEmpty)) {
      rows.add(fields);
    }
    fields = <String>[];
    sawAnyChar = false;
  }

  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (inQuotes) {
      if (char == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(char);
      }
      continue;
    }
    switch (char) {
      case '"':
        // A quote only opens a quoted region at the start of a field; a quote
        // mid-field is a literal character.
        if (field.isEmpty) {
          inQuotes = true;
        } else {
          field.write('"');
        }
        sawAnyChar = true;
      case ',':
        endField();
        sawAnyChar = true;
      case '\r':
        // Consume a following '\n' as part of a single CRLF terminator.
        if (i + 1 < input.length && input[i + 1] == '\n') i++;
        endRow();
      case '\n':
        endRow();
      default:
        field.write(char);
        sawAnyChar = true;
    }
  }

  if (inQuotes) {
    throw const SatcatParseException('unterminated quoted field in CSV');
  }

  // Flush a trailing row that was not newline-terminated.
  if (sawAnyChar || field.isNotEmpty || fields.isNotEmpty) {
    endRow();
  }

  return rows;
}
