/// Parsing of CelesTrak OMM JSON into [Omm] domain models.
library;

import 'package:celestrak/src/domain/failures.dart';
import 'package:celestrak/src/domain/omm.dart';

/// Parses CelesTrak OMM JSON objects into [Omm] value types.
///
/// The parser is stateless; construct once (`const OmmParser()`) and reuse.
/// All parse failures are reported as [OmmParseException] — no raw cast,
/// format, or null error escapes.
class OmmParser {
  /// Creates a stateless [OmmParser].
  const OmmParser();

  /// Parses a single CelesTrak OMM JSON object into an [Omm].
  ///
  /// [json] keys are the uppercase CCSDS keyword names. `OBJECT_NAME` and
  /// `OBJECT_ID` may be absent or null (analyst, 80000-series objects); every
  /// other mandatory element must be present and well-typed. Numeric fields
  /// tolerate JSON numbers and numeric strings; `EPOCH` is interpreted as UTC
  /// even when the timestamp omits a zone designator.
  ///
  /// Throws an [OmmParseException] if a mandatory field is missing, null, or
  /// has an unexpected type, or if `EPOCH` is not a valid ISO-8601 timestamp.
  Omm parse(Map<String, dynamic> json) {
    return Omm(
      objectName: _optionalString(json, 'OBJECT_NAME'),
      objectId: _optionalString(json, 'OBJECT_ID'),
      epoch: _epoch(json, 'EPOCH'),
      centerName: _string(json, 'CENTER_NAME'),
      refFrame: _string(json, 'REF_FRAME'),
      timeSystem: _string(json, 'TIME_SYSTEM'),
      meanElementTheory: _string(json, 'MEAN_ELEMENT_THEORY'),
      meanMotion: _double(json, 'MEAN_MOTION'),
      eccentricity: _double(json, 'ECCENTRICITY'),
      inclination: _double(json, 'INCLINATION'),
      raOfAscNode: _double(json, 'RA_OF_ASC_NODE'),
      argOfPericenter: _double(json, 'ARG_OF_PERICENTER'),
      meanAnomaly: _double(json, 'MEAN_ANOMALY'),
      ephemerisType: _int(json, 'EPHEMERIS_TYPE'),
      classificationType: _string(json, 'CLASSIFICATION_TYPE'),
      noradCatId: _int(json, 'NORAD_CAT_ID'),
      elementSetNo: _int(json, 'ELEMENT_SET_NO'),
      revAtEpoch: _int(json, 'REV_AT_EPOCH'),
      bstar: _double(json, 'BSTAR'),
      meanMotionDot: _double(json, 'MEAN_MOTION_DOT'),
      meanMotionDdot: _double(json, 'MEAN_MOTION_DDOT'),
    );
  }
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value?.toString();
}

Object _required(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value == null) {
    throw OmmParseException('missing required field', field: key);
  }
  return value;
}

String _string(Map<String, dynamic> json, String key) =>
    _required(json, key).toString();

int _int(Map<String, dynamic> json, String key) {
  final value = _required(json, key);
  if (value is num) return value.toInt();
  final parsed = int.tryParse(value.toString());
  if (parsed == null) {
    throw OmmParseException('expected an integer, got "$value"', field: key);
  }
  return parsed;
}

double _double(Map<String, dynamic> json, String key) {
  final value = _required(json, key);
  if (value is num) return value.toDouble();
  final parsed = double.tryParse(value.toString());
  if (parsed == null) {
    throw OmmParseException('expected a number, got "$value"', field: key);
  }
  return parsed;
}

DateTime _epoch(Map<String, dynamic> json, String key) {
  final raw = _string(json, key);
  // CelesTrak OMM EPOCH is UTC but usually omits a zone designator; treat a
  // zoneless timestamp as UTC rather than local time.
  final hasZone =
      raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
  final parsed = DateTime.tryParse(hasZone ? raw : '${raw}Z');
  if (parsed == null) {
    throw OmmParseException('invalid ISO-8601 epoch "$raw"', field: key);
  }
  return parsed.toUtc();
}
