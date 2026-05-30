# 3. Default wire format = OMM JSON; fetch the requested format directly

Status: Accepted

## Context

CelesTrak's 5-digit catalog numbers are being exhausted (projected ~2026-07-12).
Beyond that point, 6–9-digit catalog IDs **cannot be encoded** in the legacy
69-character TLE format. Consumers (notably the planned `satellite_passes`
package) need the verbatim `line1`/`line2` strings as SGP4 input when they
exist. The open question was whether to reconstruct TLE lines from OMM, or to
fetch the TLE form directly.

## Decision

**`CelestrakFormat.omm` (JSON) is the default wire format.** The client
**fetches the exact format the caller requests** from `gp.php`
(`&FORMAT=JSON` or `&FORMAT=TLE`). We do **not** hand-roll TLE-from-OMM
serialization in v1.

When a caller needs *both* full OMM fields *and* the verbatim TLE lines, the
client issues a **second `gp.php` request with `FORMAT=TLE`** for the same query
and stitches the lines onto the model — documented as costing one extra
(cacheable) request. For 6+ digit catalog objects where no valid TLE exists,
`line1`/`line2` may be empty and the OMM data is authoritative.

## Consequences

- **+** Sidesteps the checksum/precision bugs that TLE reconstruction invites.
- **+** OMM-default is 9-digit-catalog-safe and future-proof.
- **−** The dual-format case needs two requests, mitigated by caching and a
  polite default TTL.
- Public-API nuance: `line1`/`line2` are guaranteed non-empty only for ≤5-digit
  objects. This is part of the forward-compatibility contract with
  `satellite_passes`.

## Related

[0006](0006-omm-field-scope.md), [0008](0008-cache-invalidation.md)
