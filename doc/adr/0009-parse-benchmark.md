# 9. Starlink OMM Parse Benchmark — Isolate Opt-In Decision

Status: Accepted

## Context

[ADR-0009 (synchronous-parsing)](0009-synchronous-parsing.md) deferred the
question of whether large category parses could cause Flutter frame jank. It
required a benchmark of the worst-case category (full Starlink OMM JSON) before
shipping any `Isolate.run` code.

## Benchmark

**Date:** 2026-06-05  
**Toolchain:** Dart SDK 3.4+ (AOT-compiled via `dart compile exe`)  
**Dataset:** 7 000 synthetic Starlink OMM records (~3.5 MB JSON), matching the
live constellation size as of mid-2026.  
**Machine:** Intel i9-9900K (desktop, high-end) — represents the *best-case*
host device; mobile devices are materially slower.  
**Measured operations:** `jsonDecode` + `OmmParser.parseAllLazy().toList()`
on the main isolate (no isolate offload).

> **Note:** The stitch step (`TleOmmStitcher.stitch × N`) was not included in
> the measurement. In production, isolate calls via `_parseOmmInIsolate` also
> run `TleOmmStitcher.stitch` for every record, which re-parses the TLE body
> internally (`TleParser.parseAll`). For 7 000 Starlink records this is an
> additional O(n) pass that would materially increase the measured latency on
> a real device.

| Stat   | Value |
|--------|-------|
| min    | 16 ms |
| median | 17 ms |
| mean   | 16 ms |
| max    | 17 ms |
| p99    | 17 ms |

**Frame budget threshold:** 16 ms (60 fps Flutter target on a mid-range device).

### Why the desktop number is conservative

The i9-9900K is a high-performance desktop CPU. A mid-range mobile device
(e.g. Snapdragon 695 / Dimensity 700 tier, which represents a substantial
share of Flutter's target market) is 3–5× slower on CPU-bound Dart. Projecting
conservatively at 3×, the expected median on a mid-range device is **~51 ms**,
or up to ~85 ms at 5×. Even the raw desktop result (17 ms) already exceeds the
16 ms budget by one frame.

## Decision

The parse **fails** the 16 ms frame-budget criterion measured on a high-end
desktop. The deficit would be substantially larger on a mid-range mobile device.

An **opt-in `useIsolate` flag** is added to `CelestrakClient` and
`TleRepositoryImpl`. When `useIsolate: true`, the multi-record parse
operations (`fetchCategory`, `fetchCategoryByGroup`, `fetchByName`,
`fetchByIntlDesignator`) are offloaded to a worker isolate via `Isolate.run`.
Single-record lookups (`fetchByNoradId`) are never offloaded — their payload
is a single JSON object and parses in well under 1 ms.

The flag **defaults to `false`** so existing callers are unaffected. Flutter
apps that render satellite lists should opt in:

```dart
final client = CelestrakClient(
  cacheDir: appDir,
  useIsolate: true, // offload Starlink-sized parses off the UI thread
);
```

## Consequences

- **+** The main isolate is never blocked for more than ~1 ms on
  single-record fetches regardless of dataset size.
- **+** Flutter apps can opt in to jank-free category fetches with one flag.
- **+** Non-Flutter / server-side consumers pay zero overhead (default `false`).
- **−** `Isolate.run` spawns a new isolate per call; for very frequent small
  category calls the spawn overhead (~2–5 ms) may dominate. Callers that
  cache aggressively (TTL-bound) will rarely trigger this path.
- **−** `useIsolate: true` is not supported on the web (Dart isolates are not
  available in web targets). Web consumers must use the default.

## Related

- [0009-synchronous-parsing.md](0009-synchronous-parsing.md) — original
  deferral decision
- [0005-web-caching-fallback.md](0005-web-caching-fallback.md) — web
  constraints
