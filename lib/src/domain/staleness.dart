/// TTL freshness and stale-threshold classification helpers.
///
/// Staleness is always **reported** to callers and never causes data to be
/// silently discarded (FR-16). Action on stale data is the caller's
/// responsibility.
///
/// See also:
/// - [StalenessChecker] — encapsulates a [Clock] and a `staleThreshold`.
/// - FR-16: staleness is always reported, never causes silent data discard
library;

import 'package:celestrak/src/domain/clock.dart';

/// Default staleness threshold: orbital elements older than 3 days are
/// considered stale for most LEO satellites.
///
/// This value is intentionally conservative. Pass a custom [Duration] to
/// [StalenessChecker] when tighter accuracy is required (e.g. highly
/// elliptical orbits or debris with fast decay).
const Duration defaultStaleThreshold = Duration(days: 3);

/// Classifies whether orbital data is fresh or stale relative to a
/// configurable [staleThreshold].
///
/// Inject a [Clock] for deterministic unit tests; pass [SystemClock] (the
/// default) in production.
///
/// ```dart
/// final checker = StalenessChecker();
/// final age = checker.ageOf(satellite.epoch);
/// if (checker.isStale(satellite.epoch)) {
///   // warn the user
/// }
/// ```
final class StalenessChecker {
  /// Creates a [StalenessChecker].
  ///
  /// [clock] defaults to [SystemClock] for production use.
  /// [staleThreshold] defaults to [defaultStaleThreshold] (3 days).
  const StalenessChecker({
    Clock clock = const SystemClock(),
    Duration staleThreshold = defaultStaleThreshold,
  })  : _clock = clock,
        _staleThreshold = staleThreshold;

  final Clock _clock;
  final Duration _staleThreshold;

  /// The threshold beyond which orbital data is classified as stale.
  Duration get staleThreshold => _staleThreshold;

  /// Returns the age of the orbital element set whose [epoch] is given.
  ///
  /// Age is defined as `now − epoch`. A positive value means the elements
  /// were published in the past (the normal case). A near-zero or negative
  /// value can occur when CelesTrak publishes elements with a future epoch
  /// (propagated ahead of time); treat these as fresh.
  Duration ageOf(DateTime epoch) => _clock.now.difference(epoch.toUtc());

  /// Returns `true` when [ageOf] returns a duration exceeding [staleThreshold].
  ///
  /// Never throws. Staleness is informational — the caller decides what to do
  /// with stale data.
  bool isStale(DateTime epoch) => ageOf(epoch) > _staleThreshold;

  /// Returns `true` when the entry whose cache age is [cacheAge] is within the
  /// given [ttl] (time-to-live).
  ///
  /// A cache entry is considered fresh when its age is strictly less
  /// than [ttl].
  /// When [cacheAge] is `null` (entry not found), returns `false`.
  bool isFresh(Duration? cacheAge, {required Duration ttl}) {
    if (cacheAge == null) return false;
    return cacheAge < ttl;
  }
}
