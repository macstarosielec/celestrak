/// Immutable satellite TLE domain model.
///
/// Hand-written immutable value type per ADR-10. Backs FR-9, FR-10, US-9,
/// US-10 and the forward-compatibility contract for Package B.
///
/// See Also:
/// - [[ADR-10]] — hand-written immutability, no codegen
/// - [[03-data-models-and-api#SatelliteTLE]] — binding field contract
/// - [[CEL-17]] — implementing issue
library;

import 'package:celestrak/src/domain/omm.dart';
import 'package:meta/meta.dart';

/// Origin of the TLE data.
enum TLESource {
  /// Fetched live from CelesTrak GP API.
  celestrak,

  /// Fetched live from Space-Track.org (credentialed).
  spacetrack,

  /// Served from the file cache.
  local,
}

/// Minimal, stable satellite record backed by two verbatim TLE lines.
///
/// Immutable value type. Two instances are equal when all stored fields
/// are equal (value equality via [==] and [hashCode]).
///
/// [line1] and [line2] are the canonical SGP4 inputs and are preserved
/// verbatim. Downstream consumers read them directly (US-10, FR-9).
///
/// ```dart
/// final tle = await client.fetchByNoradId(25544);
/// print('${tle.noradId} ${tle.name} age=${tle.age}');
/// ```
@immutable
final class SatelliteTle {
  /// Creates a [SatelliteTle] with the given fields.
  const SatelliteTle({
    required this.noradId,
    required this.name,
    required this.line1,
    required this.line2,
    required this.epoch,
    required this.fetchedAt,
    required this.source,
    this.omm,
  });

  /// NORAD catalog number. Must be >= 1.
  final int noradId;

  /// Object name. Never null; empty-string fallback if absent.
  final String name;

  /// Verbatim TLE Line 1. 69 characters, checksum-valid.
  final String line1;

  /// Verbatim TLE Line 2. 69 characters, checksum-valid.
  final String line2;

  /// UTC epoch of the orbital elements.
  final DateTime epoch;

  /// UTC timestamp when this record was fetched or cache-served.
  final DateTime fetchedAt;

  /// Data source provenance.
  final TLESource source;

  /// Full OMM message when fetched in OMM format; `null` for pure-TLE fetches.
  final OMM? omm;

  /// Age of the orbital data: time elapsed since [epoch].
  ///
  /// Evaluated at call-time using [DateTime.now].
  Duration get age => DateTime.now().toUtc().difference(epoch);

  /// Whether orbital data is older than [staleThreshold].
  ///
  /// Defaults to 3 days when no threshold is provided.
  bool isStale({
    Duration staleThreshold = const Duration(days: 3),
  }) {
    return age > staleThreshold;
  }

  /// Classification from Line 1 column 8 (`'U'`, `'C'`, or `'S'`).
  ///
  /// Returns `null` if [line1] is too short to contain the
  /// classification field (less than 9 characters).
  String? get classification {
    if (line1.length < 9) return null;
    return line1[7];
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SatelliteTle &&
        other.noradId == noradId &&
        other.name == name &&
        other.line1 == line1 &&
        other.line2 == line2 &&
        other.epoch == epoch &&
        other.fetchedAt == fetchedAt &&
        other.source == source &&
        other.omm == omm;
  }

  @override
  int get hashCode {
    return Object.hash(
      noradId,
      name,
      line1,
      line2,
      epoch,
      fetchedAt,
      source,
      omm,
    );
  }

  /// Returns a new [SatelliteTle] with the specified fields replaced.
  ///
  /// Fields not provided retain their current values.
  SatelliteTle copyWith({
    int? noradId,
    String? name,
    String? line1,
    String? line2,
    DateTime? epoch,
    DateTime? fetchedAt,
    TLESource? source,
    OMM? updateOmm,
  }) {
    return SatelliteTle(
      noradId: noradId ?? this.noradId,
      name: name ?? this.name,
      line1: line1 ?? this.line1,
      line2: line2 ?? this.line2,
      epoch: epoch ?? this.epoch,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      source: source ?? this.source,
      omm: updateOmm ?? omm,
    );
  }

  @override
  String toString() {
    return 'SatelliteTle(noradId: $noradId, name: $name, '
        'epoch: $epoch, age: ${age.inHours}h, source: $source)';
  }
}
