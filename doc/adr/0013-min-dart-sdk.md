# 13. Minimum Dart SDK = `>=3.4.0 <4.0.0`

Status: Accepted

## Context

The package needs sound null safety, sealed classes for the exception hierarchy,
and `Isolate.run` availability. pub.dev rewards a current, reasonable lower
bound.

## Decision

SDK constraint **`>=3.4.0 <4.0.0`** (declared as `^3.4.0`). Pure-Dart, with no
Flutter constraint. Dart 3 sealed classes back the exception hierarchy and
exhaustive switches; `Isolate.run` is available.

## Consequences

- **+** Modern language features (sealed classes, exhaustive switches).
- **−** Excludes Dart 2.x — acceptable for a brand-new package.

## Related

[0009](0009-synchronous-parsing.md), [0012](0012-error-strategy.md)
