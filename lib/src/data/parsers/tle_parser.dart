/// Parsing of TLE strings into [SatelliteTle] domain models.
library;

import 'package:celestrak/src/domain/enums.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/satellite_tle.dart';

/// Parses Two-Line Element Set (TLE) text into [SatelliteTle] value types.
///
/// The parser is stateless; construct once (`const TleParser()`) and reuse.
/// All parse failures are reported as [TleParseException] — no raw cast,
/// format, or null error escapes.
class TleParser {
  /// Creates a stateless [TleParser].
  const TleParser();

  /// Parses a single TLE record (name + 2 lines) into a [SatelliteTle].
  ///
  /// [line0] is the name; [line1] and [line2] are the orbital lines.
  /// Throws [TleParseException] if [verifyChecksum] fails or if the
  /// orbital lines are malformed.
  SatelliteTle parse(
    String line0,
    String line1,
    String line2, {
    DateTime? fetchedAt,
    bool verifyChecksum = true,
  }) {
    if (verifyChecksum) {
      if (!_verifyChecksum(line1)) {
        throw TleParseException('invalid checksum', field: 'line1');
      }
      if (!_verifyChecksum(line2)) {
        throw TleParseException('invalid checksum', field: 'line2');
      }
    }

    return SatelliteTle(
      noradId: _parseNoradId(line1),
      name: line0.trim(),
      line1: line1.trimRight(),
      line2: line2.trimRight(),
      epoch: _parseEpoch(line1),
      fetchedAt: fetchedAt ?? DateTime.now().toUtc(),
      source: TleSource.celestrak,
      omm: null,
    );
  }

  /// Parses a multi-record TLE body into a list of [SatelliteTle].
  ///
  /// [body] must consist of non-empty lines in multiples of three.
  /// Throws [TleParseException] if the record count is not a multiple of 3.
  List<SatelliteTle> parseAll(
    String body, {
    DateTime? fetchedAt,
    bool verifyChecksum = true,
  }) {
    final resolvedFetchedAt = fetchedAt ?? DateTime.now().toUtc();
    final lines = body.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return [];
    if (lines.length % 3 != 0) {
      throw TleParseException(
        'expected multiple of 3 non-empty lines, got ${lines.length}',
      );
    }

    final result = <SatelliteTle>[];
    for (int i = 0; i < lines.length; i += 3) {
      result.add(parse(
        lines[i],
        lines[i + 1],
        lines[i + 2],
        fetchedAt: resolvedFetchedAt,
        verifyChecksum: verifyChecksum,
      ));
    }
    return result;
  }
}

bool _verifyChecksum(String line) {
  final trimmed = line.trimRight();
  if (trimmed.length < 2) return false;
  final checksumDigit = int.tryParse(trimmed[trimmed.length - 1]);
  if (checksumDigit == null) return false;

  int sum = 0;
  for (int i = 0; i < trimmed.length - 1; i++) {
    final code = trimmed.codeUnitAt(i);
    if (code >= 0x30 && code <= 0x39) {
      sum += code - 0x30;
    } else if (code == 0x2D) {
      sum += 1;
    }
  }
  return sum % 10 == checksumDigit;
}

int _parseNoradId(String line1) {
  if (line1.length < 7) {
    throw TleParseException('line1 too short', field: 'line1');
  }
  final raw = line1.substring(2, 7).trim();
  final parsed = _decodeAlpha5(raw);
  if (parsed == null || parsed < 1) {
    throw TleParseException('invalid NORAD ID format', field: 'line1');
  }
  return parsed;
}

// Decodes a TLE NORAD catalog number field, supporting both plain integers and
// the alpha-5 encoding used for IDs >= 100000 (A=10, B=11, ..., Z=35).
int? _decodeAlpha5(String raw) {
  if (raw.isEmpty) return null;
  final firstCode = raw[0].toUpperCase().codeUnitAt(0);
  if (firstCode >= 0x41 && firstCode <= 0x5A) {
    final leading = (firstCode - 0x41 + 10) * 10000;
    final rest = int.tryParse(raw.substring(1));
    if (rest == null) return null;
    return leading + rest;
  }
  return int.tryParse(raw);
}

DateTime _parseEpoch(String line1) {
  if (line1.length < 32) {
    throw TleParseException('line1 too short for epoch', field: 'line1');
  }
  final epochRaw = line1.substring(18, 32);
  final parts = epochRaw.split('.');
  if (parts.length != 2) {
    throw TleParseException('invalid epoch format', field: 'line1');
  }

  final yyDay = parts[0];
  if (yyDay.length != 5) {
    throw TleParseException('invalid epoch day field', field: 'line1');
  }

  final yy = int.tryParse(yyDay.substring(0, 2));
  final doy = double.tryParse('${yyDay.substring(2)}.${parts[1]}');
  if (yy == null || doy == null) {
    throw TleParseException('invalid epoch date/time', field: 'line1');
  }

  final year = yy < 57 ? 2000 + yy : 1900 + yy;
  final microseconds = ((doy - 1) * 86400000000).round();
  return DateTime.utc(year, 1).add(Duration(microseconds: microseconds));
}
