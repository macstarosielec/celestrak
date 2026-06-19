# 14. Silent-by-default OMM parse defaults, observed via a callback

Status: Accepted

## Context

`OmmParser` defaults four optional CCSDS metadata fields when a record omits
them: `CENTER_NAME` (EARTH), `REF_FRAME` (TEME), `TIME_SYSTEM` (UTC), and
`MEAN_ELEMENT_THEORY` (SGP4). CelesTrak's GP endpoint always omits these and the
defaults are authoritative, so for the primary use case every record is a
default.

The parser previously logged a `dart:developer` warning per defaulted field,
unconditionally and with no consumer control. A single large category fetch
(e.g. Starlink, thousands of records) produced tens of thousands of log lines
plus the `log()` cost on the calling isolate, with no way to silence it short of
switching the wire format to TLE. The warning's real purpose, flagging a
non-CelesTrak OMM source whose true reference frame may differ from the default,
was lost in the noise (alarm fatigue).

## Decision

Remove the unconditional `dart:developer` logging. Replace it with an optional
`OmmParseObserver`, a `void Function(Map<String, int> countsByField)` typedef
injected at parser construction and threaded through `CelestrakClient`,
`SpaceTrackClient`, and `TleRepositoryImpl`. The default is `null`: silent.

The observer is called at most once per parse operation (once per `parse`, once
after a `parseAllLazy` iteration) with the aggregate count of defaulted fields
across the operation, a summary rather than a per-record callback, so an
observer that logs cannot reintroduce the volume problem.

For category parses that run in a worker isolate, the defaulted-field counts are
accumulated as plain data inside the worker and returned alongside the records;
the caller replays them to the observer on the main isolate. The observer
therefore never runs inside the worker isolate, consistent with the existing
`ParseBenchmarkHook` isolate limitation.

A typedef (not an interface mirroring `ParseBenchmarkHook`) was chosen because
the observer has a single method: a function type is idiomatic, satisfies the
`one_member_abstracts` lint, and makes `null` a natural no-op default and an
in-isolate capturing closure trivial.

## Consequences

- **+** Default `CelestrakClient` usage is silent during OMM parsing; no console
  spam, no per-record `log()` cost.
- **+** Consumers can opt in to a single summary notification (to log, or to
  handle a non-CelesTrak source strictly).
- **+** The library no longer writes to the console unconditionally.
- **-** A behaviour change: code that relied on the warning output sees nothing
  by default. No internal consumer existed; surfaced in the CHANGELOG and a
  minor version bump.
- Exposing the existing `ParseBenchmarkHook` through the client (a separate
  latent gap with the same threading) is deliberately deferred to its own
  change.
