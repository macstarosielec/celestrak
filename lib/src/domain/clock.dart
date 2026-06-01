/// Clock abstraction for deterministic time-based logic.
///
/// Provides an injectable notion of "now" so that TTL, age, and staleness
/// computations are testable without real-time dependencies.
///
/// See also:
/// - [SystemClock] — production implementation backed by [DateTime.now].
/// - NFR-19: all time-dependent logic must accept an injectable clock.
library;

/// Supplies the current UTC time.
///
/// Inject this into any component that makes decisions based on the current
/// time (TTL checks, age computations, staleness classification). In tests,
/// replace with a [FakeClock]-like implementation to advance time
/// deterministically.
abstract interface class Clock {
  /// Returns the current time as a UTC [DateTime].
  DateTime get now;
}

/// Production [Clock] backed by [DateTime.now].
///
/// Use this as the default when no clock is injected. In unit tests,
/// supply a controllable alternative instead.
final class SystemClock implements Clock {
  /// Creates a [SystemClock].
  const SystemClock();

  @override
  DateTime get now => DateTime.now().toUtc();
}
