/// Minimal OMM placeholder — the full CCSDS OMM implementation is pending.
///
/// Provides basic equality on its internal field map so that
/// `SatelliteTle` equality is testable before the complete OMM model lands.
library;

import 'package:meta/meta.dart';

/// Skeleton Orbit Mean-Elements Message (stub).
///
/// All mandatory CCSDS keywords are deferred to the full implementation.
/// This stub types the `SatelliteTle.omm` field and allows equality
/// checks to compile while the complete OMM model is in progress.
@immutable
final class OMM {
  /// Creates a skeletal OMM with the given fields map.
  const OMM(this._fields);

  final Map<String, Object?> _fields;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OMM && _fields == other._fields;
  }

  @override
  int get hashCode => _fields.hashCode;
}
