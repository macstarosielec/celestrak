/// Error types raised by the celestrak package.
///
/// Every failure is surfaced as a typed exception under a single sealed
/// [CelestrakException] base, so callers can handle them exhaustively in a
/// `switch`. No raw `http` or `dart:io` exception escapes the public API.
///
/// See also:
/// - [ADR-0012: error strategy](https://github.com/macstarosielec/celestrak/blob/main/doc/adr/0012-error-strategy.md)
library;

/// Base type for every error raised by the celestrak package.
///
/// Sealed: all subtypes are declared in this library, which lets consumers
/// handle failures exhaustively in a `switch`.
sealed class CelestrakException implements Exception {
  /// Creates a [CelestrakException] with a human-readable [message].
  const CelestrakException(this.message);

  /// Human-readable explanation of the failure.
  final String message;

  @override
  String toString() => 'CelestrakException: $message';
}

/// Thrown when CelesTrak OMM JSON cannot be parsed into an `Omm`.
///
/// [field] names the offending OMM keyword when the failure is specific to a
/// single field (missing, null, or an unexpected type or format).
final class OmmParseException extends CelestrakException {
  /// Creates an [OmmParseException] describing [message], optionally for a
  /// specific OMM [field].
  const OmmParseException(super.message, {this.field});

  /// The OMM keyword that failed to parse, when applicable.
  final String? field;

  @override
  String toString() => field == null
      ? 'OmmParseException: $message'
      : 'OmmParseException($field): $message';
}

/// Thrown when a raw TLE string cannot be parsed into a [SatelliteTle].
///
/// [field] identifies the offending TLE line when the failure is specific
/// (e.g. `'line1'` for a bad checksum or truncated epoch field).
final class TleParseException extends CelestrakException {
  /// Creates a [TleParseException] describing [message], optionally for a
  /// specific TLE [field].
  const TleParseException(super.message, {this.field});

  /// The TLE field that failed to parse, when applicable.
  final String? field;

  @override
  String toString() => field == null
      ? 'TleParseException: $message'
      : 'TleParseException($field): $message';
}
