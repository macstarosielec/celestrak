# 8. Cache invalidation: TTL + manual `clearCache` only in v1

Status: Accepted

## Context

Cache freshness could be managed by a TTL, conditional GETs
(`If-Modified-Since`/ETag), content-hash de-duplication, and/or an eviction cap.
The question was how much of this v1 needs.

## Decision

**v1 = TTL + manual `clearCache()` only.** No conditional GETs and no eviction
cap in v1 (orbital element files are small). The **cache key** is a stable hash
of `{queryType, queryValue, format, source}`
(e.g. `noradId:25544|fmt:omm|src:celestrak`).

Conditional `If-Modified-Since` requests are noted as a **post-v1 politeness
enhancement**.

## Consequences

- **+** Simplest correct model; deterministic and testable with a fake clock.
- **−** No bandwidth savings from conditional GETs yet — caching plus TTL
  already protect CelesTrak's courtesy service.
- Eviction is revisited only if category caches grow materially.

## Related

[0003](0003-default-format-omm.md), [0005](0005-web-caching-fallback.md)
