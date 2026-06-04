/// [SpaceTrackQuery] value object for Space-Track GP queries.
library;

import 'package:meta/meta.dart';

/// Describes a single Space-Track GP data query.
///
/// [SpaceTrackQuery] is an immutable value object that carries the parameters
/// of a Space-Track query without coupling the caller to the HTTP layer.
/// Equality and [hashCode] are value-based.
///
/// Currently only NORAD catalog number lookup is supported. Additional query
/// types (international designator, object name) may be added in future
/// releases.
///
/// ```dart
/// final query = SpaceTrackQuery.byNoradId(25544);
/// print(query.noradId); // 25544
/// ```
@immutable
final class SpaceTrackQuery {
  /// Creates a [SpaceTrackQuery] that looks up a satellite by [noradId].
  ///
  /// Throws [ArgumentError] if [noradId] is less than 1.
  SpaceTrackQuery.byNoradId(int noradId) : _noradId = _checkedNoradId(noradId);

  final int _noradId;

  /// The NORAD catalog number to look up.
  int get noradId => _noradId;

  static int _checkedNoradId(int noradId) {
    if (noradId < 1) {
      throw ArgumentError.value(
        noradId,
        'noradId',
        'NORAD catalog numbers must be >= 1',
      );
    }
    return noradId;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SpaceTrackQuery && other._noradId == _noradId;
  }

  @override
  int get hashCode => _noradId.hashCode;

  @override
  String toString() => 'SpaceTrackQuery.byNoradId($_noradId)';
}
