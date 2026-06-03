/// Domain-layer constants shared across all layers of the celestrak package.
///
/// Placing these constants here prevents lower-level layers (network, data)
/// from being imported by higher-level layers just to access a constant.
library;

/// Default cache time-to-live; entries older than this trigger a remote fetch.
const Duration kDefaultTtl = Duration(hours: 2);
