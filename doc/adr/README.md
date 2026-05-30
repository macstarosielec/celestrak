# Architecture Decision Records

This directory records the significant architectural decisions for `celestrak`
and the rationale behind them. Each record is self-contained:
**Context → Decision → Consequences**, plus links to related records.

New decisions are added as numbered files; superseded ones are marked rather
than deleted.

| # | Decision | Status |
|---|----------|--------|
| [0001](0001-http-client.md) | HTTP client: `package:http` + thin retry/timeout wrapper | Accepted |
| [0002](0002-lint-ruleset.md) | Lint ruleset: Very Good Analysis + strict modes | Accepted |
| [0003](0003-default-format-omm.md) | Default wire format = OMM JSON; fetch the requested format directly | Accepted |
| [0004](0004-path-provider-decoupling.md) | Core is `path_provider`-free; caller supplies the cache directory | Accepted |
| [0005](0005-web-caching-fallback.md) | Pluggable `CacheStore`; in-memory fallback on web | Accepted |
| [0006](0006-omm-field-scope.md) | OMM field scope: mandatory CCSDS keywords + always-emitted fields | Accepted |
| [0007](0007-spacetrack-separate-client.md) | Space-Track as a separate, optional client with conservative throttle | Accepted |
| [0008](0008-cache-invalidation.md) | Cache invalidation: TTL + manual `clearCache` only in v1 | Accepted |
| [0009](0009-synchronous-parsing.md) | Synchronous parsing by default; opt-in isolate gated on a benchmark | Accepted |
| [0010](0010-hand-written-models.md) | Hand-written immutable models, no codegen | Accepted |
| [0011](0011-license-mit.md) | License: MIT | Accepted |
| [0012](0012-error-strategy.md) | Exceptions-first; non-throwing `Result` variant deferred | Accepted |
| [0013](0013-min-dart-sdk.md) | Minimum Dart SDK = `>=3.4.0 <4.0.0` | Accepted |
