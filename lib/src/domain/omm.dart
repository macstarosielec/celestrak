/// Minimal OMM placeholder — fully implemented in a later task.
///
/// Supports value equality so SatelliteTle equality is testable today.
/// Replaced by the full CCSDS OMM class once the OMM domain task lands.
///
/// See Also:
/// - ADR-10 (hand-written immutability, no codegen)
library;

import 'package:meta/meta.dart';

/// Skeleton Orbit Mean-Elements Message.
///
/// All mandatory CCSDS keywords are deferred to the full implementation.
/// This stub exists so that SatelliteTle.omm can be typed and equality
/// tests compile during the SatelliteTle task (CEL-17).
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
