# 10. Hand-written immutable models, no codegen

Status: Accepted

## Context

The data models (`SatelliteTLE`, `Omm`) could use `freezed` /
`json_serializable`, or be hand-written. Codegen adds dev dependencies, a
`build_runner` step, and CI time, against the "minimal dependencies" goal.

## Decision

**Hand-write** `SatelliteTLE` and `Omm` as immutable classes with `const`
constructors, value `==`/`hashCode`, `copyWith`, and explicit parser/factory
constructors (`fromOmmJson`, etc.). No `freezed`, no `json_serializable`, no
`build_runner`.

## Consequences

- **+** Zero runtime and zero codegen dependencies; faster CI; full control over
  the rendered dartdoc.
- **−** Manual `==`/`copyWith` boilerplate for ~2 models — small and
  test-covered.
- Revisited only if the model count grows materially.

## Related

[0006](0006-omm-field-scope.md)
