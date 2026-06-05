/// Parsing of TLE strings into [SatelliteTle] domain models.
library;

import 'package:celestrak/src/data/parsers/parse_benchmark_hook.dart';
import 'package:celestrak/src/domain/enums.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/satellite_tle.dart';

/// Parses Two-Line Element Set (TLE) text into [SatelliteTle] value types.
///
/// The parser is stateless; construct once (`const TleParser()`) and reuse.
/// All parse failures are reported as [TleParseException] — no raw cast,
/// format, or null error escapes.
///
/// Use [parseAllLazy] instead of [parseAll] when processing large category
/// bodies: it yields records one-at-a-time so the intermediate line
/// buffer is released as iteration proceeds.
final class TleParser {
  /// Creates a [TleParser].
  ///
  /// [benchmarkHook] receives timing signals around multi-record parses;
  /// defaults to [NullParseBenchmarkHook].
  const TleParser({
    ParseBenchmarkHook benchmarkHook = const NullParseBenchmarkHook(),
  }) : _hook = benchmarkHook;

  final ParseBenchmarkHook _hook;

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
        throw const TleParseException('invalid checksum', field: 'line1');
      }
      if (!_verifyChecksum(line2)) {
        throw const TleParseException('invalid checksum', field: 'line2');
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
  ///
  /// For large category bodies prefer [parseAllLazy] to avoid holding the
  /// full output list in memory while iterating.
  List<SatelliteTle> parseAll(
    String body, {
    DateTime? fetchedAt,
    bool verifyChecksum = true,
  }) =>
      parseAllLazy(
        body,
        fetchedAt: fetchedAt,
        verifyChecksum: verifyChecksum,
      ).toList();

  /// Lazily parses a multi-record TLE body, yielding one [SatelliteTle] at a
  /// time.
  ///
  /// Unlike [parseAll], this generator does not accumulate the full output
  /// list in memory: each record is yielded as soon as it is parsed, allowing
  /// callers to process or discard it before the next record is produced.
  ///
  /// Note: the input line buffer (`body.split('\n')`) is fully materialised
  /// upfront so that the multiple-of-3 guard can run before any records are
  /// yielded. The memory saving is therefore only the output list, not the
  /// input.
  ///
  /// [body] must consist of non-empty lines in multiples of three.
  /// Throws [TleParseException] if the record count is not a multiple of 3.
  ///
  /// The [ParseBenchmarkHook] injected at construction receives
  /// [ParseBenchmarkHook.onParseStart] / [ParseBenchmarkHook.onParseEnd]
  /// signals bracketing the full iteration.
  Iterable<SatelliteTle> parseAllLazy(
    String body, {
    DateTime? fetchedAt,
    bool verifyChecksum = true,
  }) sync* {
    final resolvedFetchedAt = fetchedAt ?? DateTime.now().toUtc();
    final lines = body.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return;
    if (lines.length % 3 != 0) {
      throw TleParseException(
        'expected multiple of 3 non-empty lines, got ${lines.length}',
      );
    }

    _hook.onParseStart(ParseBenchmarkHook.labelTle);
    var count = 0;
    final sw = Stopwatch()..start();
    try {
      for (var i = 0; i < lines.length; i += 3) {
        yield parse(
          lines[i],
          lines[i + 1],
          lines[i + 2],
          fetchedAt: resolvedFetchedAt,
          verifyChecksum: verifyChecksum,
        );
        count++;
      }
    } finally {
      sw.stop();
      _hook.onParseEnd(ParseBenchmarkHook.labelTle, count, sw.elapsed);
    }
  }
}

bool _verifyChecksum(String line) {
  final trimmed = line.trimRight();
  if (trimmed.length < 2) return false;
  final checksumDigit = int.tryParse(trimmed[trimmed.length - 1]);
  if (checksumDigit == null) return false;

  var sum = 0;
  for (var i = 0; i < trimmed.length - 1; i++) {
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
    throw const TleParseException('line1 too short', field: 'line1');
  }
  final raw = line1.substring(2, 7).trim();
  final parsed = _decodeAlpha5(raw);
  if (parsed == null || parsed < 1) {
    throw const TleParseException('invalid NORAD ID format', field: 'line1');
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
    throw const TleParseException('line1 too short for epoch', field: 'line1');
  }
  final epochRaw = line1.substring(18, 32);
  final parts = epochRaw.split('.');
  if (parts.length != 2) {
    throw const TleParseException('invalid epoch format', field: 'line1');
  }

  final yyDay = parts[0];
  if (yyDay.length != 5) {
    throw const TleParseException('invalid epoch day field', field: 'line1');
  }

  final yy = int.tryParse(yyDay.substring(0, 2));
  final doy = double.tryParse('${yyDay.substring(2)}.${parts[1]}');
  if (yy == null || doy == null) {
    throw const TleParseException('invalid epoch date/time', field: 'line1');
  }

  final year = yy < 57 ? 2000 + yy : 1900 + yy;
  final microseconds = ((doy - 1) * 86400000000).round();
  return DateTime.utc(year, 1).add(Duration(microseconds: microseconds));
}
