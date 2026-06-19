/// Observer for CCSDS OMM fields that the parser had to default.
library;

/// Receives a single summary per parse operation describing which optional
/// CCSDS metadata fields were absent and replaced with their canonical
/// defaults.
///
/// `OmmParser` defaults four metadata fields when a record omits them:
/// `CENTER_NAME` (EARTH), `REF_FRAME` (TEME), `TIME_SYSTEM` (UTC), and
/// `MEAN_ELEMENT_THEORY` (SGP4). For CelesTrak GP data these fields are always
/// absent and the defaults are authoritative, so nothing is reported unless an
/// observer is supplied. Supply one to log, or to harden against a
/// non-CelesTrak OMM source whose true reference frame may differ.
///
/// [countsByField] maps each defaulted field name to the number of records in
/// the operation for which that field was defaulted; only defaulted fields
/// appear, the map is never empty, and it is unmodifiable. The callback runs
/// once per parse operation: once per `OmmParser.parse` call, and once after an
/// `OmmParser.parseAllLazy` iteration ends, whether it is fully drained or
/// abandoned early, with the counts for the records actually parsed.
///
/// It is synchronous; do not perform I/O inside it. When category parses run
/// in a worker isolate the counts are accumulated as plain data inside the
/// worker and replayed to the observer on the main isolate, so the callback
/// never runs inside the worker isolate. The map therefore stays primitive
/// (`String` keys, `int` values) so it remains sendable across that boundary.
typedef OmmParseObserver = void Function(Map<String, int> countsByField);
