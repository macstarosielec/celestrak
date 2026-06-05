/// Dual-format TLE/OMM stitching.
///
/// When CelesTrak data is fetched in OMM format the response carries rich
/// CCSDS keywords but no verbatim TLE lines. Downstream SGP4 consumers
/// (e.g. `satellite_passes`) require the raw Line 1 / Line 2 strings. This
/// library supplies [TleOmmStitcher], which pairs a second `FORMAT=TLE`
/// response with an already-parsed [Omm] to produce a complete [SatelliteTle].
library;

import 'package:celestrak/src/data/parsers/tle_parser.dart';
import 'package:celestrak/src/domain/enums.dart';
import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/omm.dart';
import 'package:celestrak/src/domain/satellite_tle.dart';

/// Merges a parsed [Omm] with verbatim TLE lines extracted from a TLE body.
///
/// CelesTrak's GP endpoint supports two wire formats for the same object:
///
/// - `FORMAT=JSON` (OMM) — rich CCSDS keywords; no raw TLE lines.
/// - `FORMAT=TLE`  — verbatim Line 1 / Line 2 strings; fewer fields.
///
/// [TleOmmStitcher] consumes both responses and produces a single
/// [SatelliteTle] that carries the full [Omm] payload **and** the verbatim
/// lines required by SGP4 propagators.
///
/// Usage:
/// ```dart
/// final stitcher = const TleOmmStitcher();
/// final tle = stitcher.stitch(
///   omm, tleBody, fetchedAt: DateTime.now().toUtc());
/// ```
final class TleOmmStitcher {
  /// Creates a stateless [TleOmmStitcher].
  const TleOmmStitcher();

  /// Stitches an [omm] with verbatim lines found in [tleBody].
  ///
  /// [tleBody] is the raw response string for `FORMAT=TLE`. It may contain
  /// multiple 3-line records (name + Line 1 + Line 2). The record whose
  /// NORAD catalog number matches `omm.noradCatId` is selected.
  ///
  /// [fetchedAt] is stamped as the retrieval time on the returned
  /// [SatelliteTle]; it defaults to [DateTime.now].
  ///
  /// [verifyChecksum] controls TLE checksum validation (default `true`).
  ///
  /// ### 6+-digit catalog numbers
  ///
  /// Objects with NORAD IDs ≥ 100 000 are encoded in alpha-5 format in TLE
  /// bodies. Some CelesTrak groups omit these objects from the `FORMAT=TLE`
  /// response entirely. When the matching record is absent, the returned
  /// [SatelliteTle] carries empty [SatelliteTle.line1] and
  /// [SatelliteTle.line2] strings and the [Omm] epoch is used directly.
  ///
  /// ### Exceptions
  ///
  /// Throws [TleParseException] when [tleBody] is structurally malformed (e.g.
  /// the line count is not a multiple of three) but the stitch is aborted
  /// only when the TLE body itself is unparseable — a missing record for the
  /// requested ID never throws (empty lines are returned instead).
  SatelliteTle stitch(
    Omm omm,
    String tleBody, {
    DateTime? fetchedAt,
    bool verifyChecksum = true,
  }) {
    final resolvedFetchedAt = fetchedAt ?? DateTime.now().toUtc();
    final name = omm.objectName ?? '';

    // Fast path: empty TLE body → no verbatim lines available.
    final trimmed = tleBody.trim();
    if (trimmed.isEmpty) {
      return _stitchWithEmptyLines(omm, name, resolvedFetchedAt);
    }

    // Parse all records in the TLE body.
    final records = _parseAll(trimmed, resolvedFetchedAt, verifyChecksum);

    // Find the record matching the OMM's NORAD catalog number.
    for (final record in records) {
      if (record.noradId == omm.noradCatId) {
        return record.copyWith(
          // Prefer the OMM name (may be more descriptive than the TLE name).
          name: name.isNotEmpty ? name : record.name,
          omm: omm,
          fetchedAt: resolvedFetchedAt,
        );
      }
    }

    // No matching record found — return with empty lines.
    return _stitchWithEmptyLines(omm, name, resolvedFetchedAt);
  }

  /// Parses all TLE records from [body].
  ///
  /// Throws [TleParseException] when the line count is not a multiple of 3.
  List<SatelliteTle> _parseAll(
    String body,
    DateTime fetchedAt,
    bool verifyChecksum,
  ) {
    return const TleParser().parseAll(
      body,
      fetchedAt: fetchedAt,
      verifyChecksum: verifyChecksum,
    );
  }

  /// Builds a [SatelliteTle] with empty lines when no TLE record is available.
  SatelliteTle _stitchWithEmptyLines(
    Omm omm,
    String name,
    DateTime fetchedAt,
  ) {
    return SatelliteTle(
      noradId: omm.noradCatId,
      name: name,
      line1: '',
      line2: '',
      epoch: omm.epoch,
      fetchedAt: fetchedAt,
      source: TleSource.celestrak,
      omm: omm,
    );
  }
}
