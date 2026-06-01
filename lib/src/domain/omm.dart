/// Minimal OMM placeholder — the full CCSDS OMM implementation is pending.
///
/// Provides value equality over its field map so that `SatelliteTle`
/// equality is well-defined before the complete OMM model lands.
library;

import 'package:meta/meta.dart';

/// Skeleton Orbit Mean-Elements Message (stub).
///
/// All mandatory CCSDS keywords are deferred to the full implementation.
/// This stub types the `SatelliteTle.omm` field and gives it value
/// equality while the complete OMM model is in progress.
@immutable
final class Omm {
  /// Creates a skeletal OMM from a raw field map.
  ///
  /// The fields are compared by value: two [Omm]s are equal when their
  /// maps hold the same key/value pairs. Callers must not mutate the
  /// provided map after construction.
  const Omm(this._fields);

  final Map<String, Object?> _fields;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Omm) return false;
    final otherFields = other._fields;
    if (_fields.length != otherFields.length) return false;
    for (final entry in _fields.entries) {
      if (!otherFields.containsKey(entry.key) ||
          otherFields[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
        _fields.entries.map((e) => Object.hash(e.key, e.value)),
      );
}
