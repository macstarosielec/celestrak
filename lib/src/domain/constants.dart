/// Domain-layer constants shared across all layers of the celestrak package.
///
/// Placing these constants here prevents lower-level layers (network, data)
/// from being imported by higher-level layers just to access a constant.
library;

/// Default cache time-to-live; entries older than this trigger a remote fetch.
const Duration kDefaultTtl = Duration(hours: 2);

/// Default cache time-to-live for SATCAT metadata; entries older than this
/// trigger a remote refetch.
///
/// SATCAT records carry near-static per-object metadata (owner, launch and
/// decay dates, object type, size) rather than time-sensitive orbital
/// elements, so a much longer TTL than [kDefaultTtl] is appropriate: the data
/// rarely changes within a week and a SATCAT cache hit avoids re-fetching tens
/// of thousands of rows.
const Duration kSatcatDefaultTtl = Duration(days: 7);

/// Staleness threshold for SATCAT metadata.
///
/// Once a cached SATCAT entry ages past this threshold it is considered stale.
/// Unlike GP orbital elements - where staleness is an accuracy hazard because
/// propagated positions degrade rapidly with epoch age - SATCAT staleness is
/// purely informational: a month-old owner code or launch date is still
/// correct, so this threshold flags "you may want to refresh" rather than "do
/// not trust this".
const Duration kSatcatStaleThreshold = Duration(days: 30);
