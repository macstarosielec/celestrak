# 6. OMM field scope: mandatory CCSDS keywords + always-emitted fields

Status: Accepted

## Context

OMM payloads carry many keywords. The question was whether to model only the
mandatory CCSDS keywords or everything CelesTrak emits, and whether to keep
numeric values as `double`/`int` or preserve string precision.

## Decision

Ship the field set covering all **mandatory CCSDS keywords** plus the
header/metadata fields CelesTrak always emits (`CENTER_NAME`, `REF_FRAME`,
`TIME_SYSTEM`, `MEAN_ELEMENT_THEORY`). Numeric values are parsed to
`double`/`int`. Fields are nullable **only** where genuinely optional
(`OBJECT_NAME`, `OBJECT_ID`).

For SGP4 precision, the **verbatim `line1`/`line2` remain the source of truth**
(see ADR 3), so `double` rounding in OMM never degrades propagation inputs.

## Consequences

- **+** Complete enough for downstream needs (e.g. `bstar`, mean-motion
  derivatives) without over-modelling.
- **−** Unmodelled extra keywords are dropped silently — acceptable and
  additive later, since adding nullable fields is semver-safe.

## Related

[0003](0003-default-format-omm.md), [0010](0010-hand-written-models.md)
