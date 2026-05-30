/// A pure-Dart client for fetching, parsing, and caching satellite TLE and OMM
/// orbital data from CelesTrak and Space-Track.
///
/// This is the public entry point of the package. Everything under `src/` is
/// private implementation and is not part of the public API contract.
///
/// The public surface is exported here as it lands across implementation
/// phases P1–P6 (domain models, parsers, cache, the `CelesTrakClient` facade).
library;

// Public exports are added incrementally per the implementation plan.
// (P1: domain models + enums + failures; P3: CelesTrakClient; ...)
