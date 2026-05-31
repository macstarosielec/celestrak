# 1. HTTP client: `package:http` + thin retry/timeout wrapper

Status: Accepted

## Context

The network layer needs request timeouts and bounded retry. The dependency
footprint matters: a smaller transitive tree means fewer version constraints
that could conflict for consumers, and keeps the package's "minimal
dependencies" promise. The realistic choice was `package:http` vs `package:dio`.

## Decision

Use **`package:http`**, wrapped in a small internal `HttpTransport` that adds:

- connect/read timeouts;
- bounded retry with exponential backoff — retry on timeout, 5xx, and transient
  socket errors; **never** on 4xx;
- HTTPS-only enforcement.

The inner `http.Client` is injectable, so tests pass a `MockClient`.

## Consequences

- **+** Lightest option, official, fewest transitive dependencies — the
  smallest possible conflict surface for consumers.
- **+** Trivial to mock in tests.
- **−** We hand-roll retry (~40 lines), fully unit-tested.
- All HTTP lives behind `HttpTransport`, so switching to `dio` later would be an
  internal `lib/src` change with no public-API impact.

## Related

[0013](0013-min-dart-sdk.md)
