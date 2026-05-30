# 4. Core is `path_provider`-free; caller supplies the cache directory

Status: Accepted

## Context

`path_provider` is a Flutter-adjacent plugin. Server / Dart-VM consumers must be
able to use this package without it, and the core must carry **zero**
Flutter-adjacent runtime dependencies.

## Decision

The core `CelesTrakClient` requires an explicit `Directory` (or a `CacheStore`)
and depends on **no** `path_provider`. `path_provider` is **not** a direct
dependency of this package.

The README documents that Flutter consumers obtain a directory in one line
(e.g. `getApplicationSupportDirectory()`) and pass it in. This guarantees a
clean dependency report and a pure-Dart core.

## Consequences

- **+** Server / VM / AOT use is clean; no Flutter-adjacent dependency.
- **+** Cleanest possible dependency report on pub.dev.
- **−** Flutter users write one extra line to obtain a directory — documented in
  the README and `example/`.

## Related

[0005](0005-web-caching-fallback.md), [0008](0008-cache-invalidation.md)
