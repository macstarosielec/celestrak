/// Immutable satellite TLE domain model.
///
/// Hand-written immutable value type. Designed to be forward-compatible with
/// downstream consumers such as a planned `satellite_passes` package.
///
/// See also:
/// - [ADR-0010: hand-written models](https://github.com/macstarosielec/celestrak/blob/main/doc/adr/0010-hand-written-models.md)
library;

import 'package:celestrak/src/domain/enums.dart';
import 'package:celestrak/src/domain/omm.dart';
import 'package:celestrak/src/domain/staleness.dart';
import 'package:meta/meta.dart';

/// Minimal, stable satellite record backed by two verbatim TLE lines.
///
/// Immutable value type. Two instances are equal when all stored fields
/// are equal (value equality via [==] and [hashCode]).
///
/// [line1] and [line2] are the canonical SGP4 inputs and are preserved
/// verbatim for direct use by downstream consumers.
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
  final TleSource source;

  /// Full OMM message when fetched in OMM format; `null` for pure-TLE fetches.
  final Omm? omm;

  /// Age of the orbital data: time elapsed since [epoch].
  ///
  /// Evaluated at call-time using [DateTime.now]. For deterministic tests,
  /// prefer [ageAt] with an injected [DateTime].
  Duration get age => DateTime.now().toUtc().difference(epoch);

  /// Age of the orbital data relative to an explicit [now] timestamp.
  ///
  /// Use this in tests (with a fake clock) or whenever a consistent
  /// reference time is required within a single computation.
  Duration ageAt(DateTime now) => now.toUtc().difference(epoch);

  /// Whether orbital data is older than [staleThreshold] at [now].
  ///
  /// [now] defaults to the real current time. Supply a pinned [DateTime] for
  /// deterministic tests. [staleThreshold] defaults to 3 days — override for
  /// orbits requiring tighter accuracy.
  bool isStale({
    DateTime? now,
    Duration staleThreshold = defaultStaleThreshold,
  }) {
    final reference = (now ?? DateTime.now()).toUtc();
    return ageAt(reference) > staleThreshold;
  }

  /// Classification character from Line 1, column 8 (1-indexed; character
  /// index 7): `'U'` unclassified, `'C'` classified, or `'S'` secret.
  ///
  /// Returns `null` if [line1] is too short to contain the
  /// classification field (fewer than 9 characters).
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

  /// Sentinel marking an omitted [copyWith] argument, so callers can
  /// distinguish "leave [omm] unchanged" from "set [omm] to `null`".
  static const Object _unset = Object();

  /// Returns a new [SatelliteTle] with the specified fields replaced.
  ///
  /// Fields not provided retain their current values. Pass `omm: null`
  /// explicitly to clear the optional OMM payload.
  SatelliteTle copyWith({
    int? noradId,
    String? name,
    String? line1,
    String? line2,
    DateTime? epoch,
    DateTime? fetchedAt,
    TleSource? source,
    Object? omm = _unset,
  }) {
    return SatelliteTle(
      noradId: noradId ?? this.noradId,
      name: name ?? this.name,
      line1: line1 ?? this.line1,
      line2: line2 ?? this.line2,
      epoch: epoch ?? this.epoch,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      source: source ?? this.source,
      omm: identical(omm, _unset) ? this.omm : omm as Omm?,
    );
  }

  @override
  String toString() {
    return 'SatelliteTle(noradId: $noradId, name: $name, '
        'epoch: $epoch, source: $source)';
  }
}
