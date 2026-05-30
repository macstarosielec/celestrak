# 9. Synchronous parsing by default; opt-in isolate gated on a benchmark

Status: Accepted

## Context

Large category responses (e.g. the full Starlink set) could jank a Flutter frame
if parsed on the main isolate.

## Decision

**Parsing is synchronous by default.** A later phase includes a **benchmark** of
the worst-case category (full Starlink OMM JSON). Only if it exceeds a
frame-budget threshold do we add an **opt-in** `useIsolate: true` path via
`Isolate.run`. No isolate code ships before the measurement justifies it.

## Consequences

- **+** No premature complexity; the simplest path is validated first.
- **−** A possible follow-up if the benchmark fails — isolated and additive,
  with no public-API breakage.

## Related

[0010](0010-hand-written-models.md)
