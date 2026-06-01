/// A manually-advanceable clock for deterministic time-based tests.
library;

/// Provides a controllable notion of "now" for deterministic TTL testing.
///
/// Pass [FakeClock.now] wherever a [DateTime] representing the current time
/// is required. Advance time by calling [advance].
final class FakeClock {
  /// Creates a [FakeClock] starting at [initial].
  FakeClock(DateTime initial) : _now = initial;

  DateTime _now;

  /// Returns the current fake time.
  DateTime get now => _now;

  /// Moves the clock forward by [duration].
  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}
