# 12. Exceptions-first; non-throwing `Result` variant deferred

Status: Accepted

## Context

Errors can be surfaced as typed exceptions or as a non-throwing
`Result`/`Either` return type. Mandating `Result` everywhere is over-functional
for an idiomatic Dart library and surprises consumers.

## Decision

**Exceptions are the primary contract.** A sealed `CelestrakException` base has
subtypes: `NetworkException`, `SatelliteNotFoundException`,
`TleParseException`, `OmmParseException`, `CacheMissException`,
`AuthenticationException`, `RateLimitException`. Each carries actionable context
(NORAD ID / group / HTTP status). **No raw `http` or IO exception escapes the
public API.**

A non-throwing `tryFetch…` returning `Result<SatelliteTLE, CelestrakException>`
is **deferred** (post-v1) and added only if demand appears — additive and
semver-safe.

## Consequences

- **+** Dart-idiomatic; no surprises for consumers.
- **+** Smaller v1 public surface.
- **−** Consumers preferring a `Result` style wait for a later minor release.

## Related

[0007](0007-spacetrack-separate-client.md)
