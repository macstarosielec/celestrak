# 16. SATCAT as a separate concern

Status: Accepted

## Context

OrbitLens needs to answer "who owns this object, where/when did it launch,
what type is it, is it still operational?" per NORAD ID (FR-4b, Q-18).
CelesTrak publishes this as SATCAT, a dataset distinct from GP/OMM: different
endpoint (`satcat/records.php`), different field set (owner, launch/decay
dates, object type, ops status), and a much slower change cadence, SATCAT
records drift over days or weeks, GP elements go stale in hours.

The alternative to a new client was folding these fields onto `SatelliteTle`/
`Omm`. That would bloat the frozen v1.0.0 GP contract with fields unrelated to
propagation, force one cache TTL to serve two very different staleness
profiles, and give every GP consumer a wider payload whether or not they need
ownership metadata. SATCAT also has no orbital epoch, so its staleness is
necessarily age-of-fetch rather than age-of-epoch, a different freshness model
than GP's.

## Decision

SATCAT ships as a fully parallel pipeline: `SatcatEntry` (model),
`SatcatDataSource` (remote fetch), `SatcatRepositoryImpl` (cache -> TTL ->
fetch -> parse orchestration), and `SatcatClient` (public facade), mirroring
the shape of the GP path without extending or subclassing it.

The parallel pipeline reuses the existing seams rather than duplicating
infrastructure: `HttpTransport` for retry/timeout, `CacheStore` for the
overridable cache directory (ADR-4), `Clock` for TTL and age calculations
(NFR-19), the exceptions-first tree (ADR-12), gaining `SatcatParseException`
as a sibling of `OmmParseException` and reusing `SatelliteNotFoundException`,
and hand-written immutable models (ADR-10).

The two datasets are joined only by `noradId`, at the call site. The package
never merges a `SatcatEntry` into a `SatelliteTle`; a consumer that wants both
fetches each independently and joins them itself. The frozen GP contract does
not change, and no propagation or orbital math is added (NG1 unchanged).

## Consequences

- **+** The v1.0.0 GP contract stays frozen; SATCAT lands as a pure v1.1.0
  addition with no changed signatures, a safe minor bump.
- **+** GP and SATCAT each get a cache TTL and staleness threshold tuned to
  their own data cadence instead of sharing a compromise value.
- **+** Consumers who don't need ownership metadata pay no cost: no extra
  fields on `SatelliteTle`, no extra parsing, no extra cache entries.
- **-** A consumer that wants both a TLE and SATCAT metadata for one object
  issues two fetches (one per client) and joins them manually; there is no
  combined "full record" convenience type.
- **-** Two client instances means two `dispose()` calls and two cache
  namespaces to manage per app, rather than one.
