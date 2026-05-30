# 7. Space-Track as a separate, optional client with conservative throttle

Status: Accepted

## Context

Space-Track.org requires registration, session-cookie login, and enforces rate
limits that differ from CelesTrak's `gp.php`. It is a valuable authoritative
second source but should not complicate or destabilise the CelesTrak path.

## Decision

Implement a **separate `SpaceTrackClient`** (not bolted onto `CelesTrakClient`).
The caller supplies `identity`/`password` at runtime — never bundled. Login is a
POST that yields a session cookie held **in memory only**; subsequent
`basicspacedata/query/class/gp` requests reuse it.

A built-in **conservative client-side throttle** spaces requests to respect the
documented limits. HTTP 429 maps to `RateLimitException`; an auth failure maps
to `AuthenticationException`. Returned records are stamped
`source == TLESource.spacetrack`. The Space-Track path ships **after** the
CelesTrak path is solid.

## Consequences

- **+** Optional source degrades cleanly when no credentials are provided.
- **+** Isolated blast radius if Space-Track's auth or limits change.
- **−** Separate auth/throttle code, gated to its own development phase.
- Scope guard: Space-Track stays read-only GP data — no broader API surface.

## Related

[0001](0001-http-client.md), [0012](0012-error-strategy.md)
