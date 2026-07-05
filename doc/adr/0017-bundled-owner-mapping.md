# 17. Bundled, offline SATCAT owner-code mapping

Status: Accepted

## Context

`SatcatEntry.ownerCode` carries CelesTrak's own terse, non-ISO owner/source
code (`PRC` for China, `CIS` for the former-USSR/Russia bloc, `GER` for
Germany, and so on). OrbitLens needs a human-readable country/organisation
name, a coarse region, and an EU-sovereign flag (FR-4b), not the raw code.

The authoritative code list is published at `celestrak.org/satcat/sources.php`
and changes rarely, a new code appears only when a new state or operator
registers a launch. A live-fetched table would add a second network
dependency and a second cache entry for data that almost never changes, and
it introduces a failure mode where a network outage leaves the library unable
to render an owner name it already knew before the outage.

## Decision

The owner table is bundled as a compile-time `const Map<String, SatcatOwner>`
(`kSatcatOwnerCodes`), reconciled by hand against
`celestrak.org/satcat/sources.php` (CEL-150). `satcatOwnerForCode(code)`
normalises the input (trim, uppercase) and looks it up. A code absent from the
table, including a code CelesTrak adds after this table was generated, and
the `TBD`/`UNK` administrative sentinels, degrades to a passthrough
`SatcatOwner(code: normalised, name: normalised, region: null,
isEuSovereign: false)` rather than throwing.

The table carries no assets and performs no I/O or `path_provider` access; it
is plain Dart data, tree-shakeable, and behaves identically on every
platform including web.

## Consequences

- **+** `satcatOwnerForCode` is pure, synchronous, and fully offline: zero
  network calls, zero I/O, no platform-specific code path.
- **+** An unrecognised code never throws. A consumer always gets a usable
  `SatcatOwner`, even for a code the table has not caught up with yet.
- **+** No new runtime dependency and no asset-bundling step; the table ships
  inside the package the same way as any other Dart source file.
- **-** The table can drift from the authoritative source list: a code
  CelesTrak adds is invisible to already-shipped versions until someone
  reconciles the list and cuts a minor release (mitigated by the CEL-150
  reconciliation pass, but not eliminated).
- **-** Every code addition is a source change plus a release, not something
  a consumer can pick up at runtime; this is the deliberate trade for staying
  offline-first.
