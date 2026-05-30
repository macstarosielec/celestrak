# 2. Lint ruleset: Very Good Analysis + strict modes

Status: Accepted

## Context

The package targets a clean `dart analyze` under strict lints, which the pub.dev
score rewards. The ruleset should match the author's house style across
projects.

## Decision

`analysis_options.yaml` includes **`very_good_analysis`** and enables the
analyzer strict language modes:

```yaml
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
```

`dart format` is enforced in CI. This is a pure-Dart package, so
`flutter_lints` does not apply.

## Consequences

- **+** Maximal lint signal; consistent with the author's other packages.
- **−** Stricter than the baseline `lints` package — accepted deliberately.

## Related

[0013](0013-min-dart-sdk.md)
