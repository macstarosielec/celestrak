# 15. Network failure taxonomy: a `kind` field on `NetworkException`

Status: Accepted

## Context

Every transport failure surfaces as a single `NetworkException`. The transport
already distinguishes the causes internally (HTTP status branches, timeout,
socket/client exceptions) but collapses them on the way out; the only clues a
caller gets are an optional `statusCode` and a `cause` holding the raw
underlying exception. Classifying by `cause` would force callers to type-sniff
`dart:io` and `package:http` exceptions, which is exactly what ADR-0012's
"no raw exception escapes the public API" contract exists to prevent.

The concrete consumer is orbit_lens (OL-102): it needs to tell a probable
CelesTrak-side block from a generic outage. CelesTrak blocks present in two
ways: a rejecting status (403/429) or an HTML block page served instead of a
payload, and banned IPs are blackholed, so an established ban usually presents
as timeouts. A DNS/socket failure means no connectivity and is not a block
signal at all. These three situations are indistinguishable today.

A complication: `NetworkException` is also thrown from six non-transport sites
(cache eviction races in the repository implementations) that are not network
failures of any kind.

## Decision

Add a public `NetworkFailureKind` enum and a `kind` field on
`NetworkException`, defaulting to `NetworkFailureKind.unknown`:

- `httpRejected` - the server answered with a rejecting status (4xx, 5xx after
  the retry budget, unexpected 1xx/3xx) or an HTML block page in place of a
  payload. The raw status stays in `statusCode`.
- `timeout` - the request was sent but no response arrived within the
  per-attempt deadline.
- `network` - DNS or socket-level failure; the request never reached a server.
- `unknown` - not attributable to the above; used by the eviction-race throws.
  Consumers building block heuristics should ignore it.

Sealed subtypes were rejected: `NetworkException` is `final` and constructed
directly in the repository implementations and in consumer test doubles, so
converting it to a sealed (hence abstract) base is a breaking change with no
payoff over a `switch (e.kind)`.

When retries exhaust with mixed causes (say 503, then a timeout), `kind`
reflects the last attempt's error - the same rule `cause` already follows, so
the two fields stay consistent.

The HTML block-page sniff lives in `HttpTransport`, not in the data sources:
the transport is the only layer that still has the real status code, and no
endpoint the package talks to (GP JSON/CSV/TLE/XML, SATCAT JSON/CSV,
Space-Track JSON) can legally begin with `<!DOCTYPE` or `<html`. The sniff
matches exactly those two tokens after leading whitespace, case-insensitively;
it must not be widened to a bare `<`, which would false-positive on `<?xml`.
A future endpoint that legitimately serves HTML must revisit this record.

Retry policy is untouched: classification only. Space-Track's semantic
exceptions (`AuthenticationException`, `RateLimitException`) stay as they are,
layered above the transport; a CelesTrak 429 is reported as
`kind == httpRejected` with `statusCode == 429`, which is sufficient for the
consumer heuristic.

## Consequences

- **+** Callers classify failures with an exhaustive `switch` on a package
  enum; no raw exception types leak into consumer code.
- **+** A 200-with-HTML block page now fails honestly as `httpRejected`
  instead of surfacing as a parse error.
- **+** Additive and non-breaking: the constructor default keeps every
  existing construction compiling; shipped as a minor version.
- **-** `toString()` gains a trailing `kind=` segment; code matching on the
  full rendered string (none known) would notice. The message prefix is
  unchanged.
- **-** The two-token sniff is a heuristic. It is deliberately narrow: a block
  page that is HTML but starts with neither token is still misreported as a
  parse error. Accepted; widening requires revisiting this record.
