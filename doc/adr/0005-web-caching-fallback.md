# 5. Pluggable `CacheStore`; in-memory fallback on web

Status: Accepted

## Context

The default `dart:io` file cache does not apply on Flutter web. The package
should still compile and fetch on web without a `dart:io` import.

## Decision

Caching sits behind a `CacheStore` interface:

- `FileCacheStore` (default on VM / Flutter mobile / desktop) uses `dart:io`.
- `MemoryCacheStore` provides an in-memory, non-persistent fallback so fetching
  still works on web.

A **conditional import** keyed on `dart.library.io` selects the file store on
the VM and the memory store on web automatically; consumers may override.

Web is declared **supported-for-fetch, best-effort-for-cache**; the README notes
that persistent caching is unavailable on web.

## Consequences

- **+** Web compiles and runs; no `dart:io` import is reached on web.
- **−** No cache persistence on web — accepted and documented.
- Atomic-write / corruption-tolerance logic applies to the file store only.

## Related

[0004](0004-path-provider-decoupling.md), [0008](0008-cache-invalidation.md)
