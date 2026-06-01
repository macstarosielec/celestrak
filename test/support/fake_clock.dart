/// A manually-advanceable clock for deterministic time-based tests.
library;

import 'package:celestrak/src/domain/clock.dart';

/// Provides a controllable notion of "now" for deterministic TTL testing.
///
/// Implements [Clock] so it can be injected wherever a [Clock] is expected.
/// Advance time by calling [advance].
final class FakeClock implements Clock {
  /// Creates a [FakeClock] starting at [initial].
  ///
  /// [initial] is normalised to UTC to match the contract of [Clock.now].
  FakeClock(DateTime initial) : _now = initial.toUtc();

  DateTime _now;

  /// Returns the current fake time.
  @override
  DateTime get now => _now;

  /// Moves the clock forward by [duration].
  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}
