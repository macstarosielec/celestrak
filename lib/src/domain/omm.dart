/// Full CCSDS Orbit Mean-Elements Message domain model (ADR-6).
///
/// Maps all mandatory OMM keywords plus CelesTrak header fields.
/// Construction via fromCelestrakJson. Null object name / ID
/// tolerated per FR-8.
///
/// See Also:
/// - [[ADR-6]] — field scope and parsing rules
/// - [[03-data-models-and-api#OMM]] — binding field contract
/// - [[CEL-18]] — implementing issue
library;

import 'package:meta/meta.dart';

/// Sentinel marking an omitted copyWith argument.
const Object _unset = Object();

/// Resolves a nullable copyWith argument using sentinel pattern.
T _resolve<T>(Object? value, T fallback) {
  if (identical(value, _unset)) return fallback;
  return value as T;
}

/// Complete Orbit Mean-Elements Message.
///
/// Immutable value type. Two instances are equal when all fields match.
/// Nullable fields (objectName, objectId) tolerate absent values for
/// analyst (80000-series) objects.
@immutable
final class Omm {
  /// Creates an Omm with the given fields.
  const Omm({
    required this.objectName,
    required this.objectId,
    required this.epoch,
    required this.centerName,
    required this.refFrame,
    required this.timeSystem,
    required this.meanElementTheory,
    required this.meanMotion,
    required this.eccentricity,
    required this.inclination,
    required this.raOfAscNode,
    required this.argOfPericenter,
    required this.meanAnomaly,
    required this.ephemerisType,
    required this.classificationType,
    required this.noradCatId,
    required this.elementSetNo,
    required this.revAtEpoch,
    required this.bstar,
    required this.meanMotionDot,
    required this.meanMotionDdot,
  });

  /// Builds an Omm from a CelesTrak OMM JSON map.
  ///
  /// Keys are the uppercase CCSDS keyword names. All mandatory elements
  /// must be present; object name and object ID may be null.
  factory Omm.fromCelestrakJson(Map<String, dynamic> json) {
    final objectName = json['OBJECT_NAME'] as String?;
    final objectId = json['OBJECT_ID'] as String?;
    final epochStr = json['EPOCH'] as String;
    final centerName = _jsonString(json, 'CENTER_NAME');
    final refFrame = _jsonString(json, 'REF_FRAME');
    final timeSystem = _jsonString(json, 'TIME_SYSTEM');
    final meanElementTheory = _jsonString(json, 'MEAN_ELEMENT_THEORY');

    final meanMotion = _jsonDouble(json, 'MEAN_MOTION');
    final eccentricity = _jsonDouble(json, 'ECCENTRICITY');
    final inclination = _jsonDouble(json, 'INCLINATION');
    final raOfAscNode = _jsonDouble(json, 'RA_OF_ASC_NODE');
    final argOfPericenter = _jsonDouble(json, 'ARG_OF_PERICENTER');
    final meanAnomaly = _jsonDouble(json, 'MEAN_ANOMALY');

    final ephemerisType = _jsonInt(json, 'EPHEMERIS_TYPE');
    final classificationType = _jsonString(json, 'CLASSIFICATION_TYPE');
    final noradCatId = _jsonInt(json, 'NORAD_CAT_ID');
    final elementSetNo = _jsonInt(json, 'ELEMENT_SET_NO');
    final revAtEpoch = _jsonInt(json, 'REV_AT_EPOCH');
    final bstar = _jsonDouble(json, 'BSTAR');
    final meanMotionDot = _jsonDouble(json, 'MEAN_MOTION_DOT');
    final meanMotionDdot = _jsonDouble(json, 'MEAN_MOTION_DDOT');

    return Omm(
      objectName: objectName,
      objectId: objectId,
      epoch: _parseIso8601(epochStr),
      centerName: centerName,
      refFrame: refFrame,
      timeSystem: timeSystem,
      meanElementTheory: meanElementTheory,
      meanMotion: meanMotion,
      eccentricity: eccentricity,
      inclination: inclination,
      raOfAscNode: raOfAscNode,
      argOfPericenter: argOfPericenter,
      meanAnomaly: meanAnomaly,
      ephemerisType: ephemerisType,
      classificationType: classificationType,
      noradCatId: noradCatId,
      elementSetNo: elementSetNo,
      revAtEpoch: revAtEpoch,
      bstar: bstar,
      meanMotionDot: meanMotionDot,
      meanMotionDdot: meanMotionDdot,
    );
  }

  // -- Header / metadata --

  /// Object name. Null for some analyst (80000-series) objects.
  final String? objectName;

  /// International Designator (`YYYY-NNNAAA`). Null if unavailable.
  final String? objectId;

  /// UTC epoch of the orbital elements.
  final DateTime epoch;

  /// Center body name; typically `"EARTH"`.
  final String centerName;

  /// Reference frame; typically `"TEME"`.
  final String refFrame;

  /// Time system; typically `"UTC"`.
  final String timeSystem;

  /// Mean element theory; typically `"SGP4"`.
  final String meanElementTheory;

  // -- Mean elements --

  /// Mean motion in revolutions per day.
  final double meanMotion;

  /// Eccentricity; 0 <= e < 1.
  final double eccentricity;

  /// Inclination in degrees; 0-180.
  final double inclination;

  /// Right ascension of ascending node in degrees; 0-360.
  final double raOfAscNode;

  /// Argument of pericenter in degrees; 0-360.
  final double argOfPericenter;

  /// Mean anomaly in degrees; 0-360.
  final double meanAnomaly;

  // -- TLE-related parameters --

  /// Ephemeris type number; usually `0`.
  final int ephemerisType;

  /// Classification: `'U'`, `'C'`, or `'S'`.
  final String classificationType;

  /// NORAD catalog number.
  final int noradCatId;

  /// Element set number.
  final int elementSetNo;

  /// Revolution number at epoch.
  final int revAtEpoch;

  /// Drag term (earth radii inverse).
  final double bstar;

  /// First derivative of mean motion (ndot / 2).
  final double meanMotionDot;

  /// Second derivative of mean motion (nddot / 6).
  final double meanMotionDdot;

  // -- Value equality --

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Omm &&
        other.objectName == objectName &&
        other.objectId == objectId &&
        other.epoch == epoch &&
        other.centerName == centerName &&
        other.refFrame == refFrame &&
        other.timeSystem == timeSystem &&
        other.meanElementTheory == meanElementTheory &&
        other.meanMotion == meanMotion &&
        other.eccentricity == eccentricity &&
        other.inclination == inclination &&
        other.raOfAscNode == raOfAscNode &&
        other.argOfPericenter == argOfPericenter &&
        other.meanAnomaly == meanAnomaly &&
        other.ephemerisType == ephemerisType &&
        other.classificationType == classificationType &&
        other.noradCatId == noradCatId &&
        other.elementSetNo == elementSetNo &&
        other.revAtEpoch == revAtEpoch &&
        other.bstar == bstar &&
        other.meanMotionDot == meanMotionDot &&
        other.meanMotionDdot == meanMotionDdot;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      objectName,
      objectId,
      epoch,
      centerName,
      refFrame,
      timeSystem,
      meanElementTheory,
      meanMotion,
      eccentricity,
      inclination,
      raOfAscNode,
      argOfPericenter,
      meanAnomaly,
      ephemerisType,
      classificationType,
      noradCatId,
      elementSetNo,
      revAtEpoch,
      bstar,
      meanMotionDot,
      meanMotionDdot,
    ]);
  }

  /// Returns a new [Omm] with the specified fields replaced.
  ///
  /// Fields not provided retain their current values. Pass `null` for
  /// [updateObjectName] or [updateObjectId] to clear them.
  Omm copyWith({
    Object? updateObjectName = _unset,
    Object? updateObjectId = _unset,
    DateTime? epoch,
    String? centerName,
    String? refFrame,
    String? timeSystem,
    String? meanElementTheory,
    double? meanMotion,
    double? eccentricity,
    double? inclination,
    double? raOfAscNode,
    double? argOfPericenter,
    double? meanAnomaly,
    int? ephemerisType,
    String? classificationType,
    int? noradCatId,
    int? elementSetNo,
    int? revAtEpoch,
    double? bstar,
    double? meanMotionDot,
    double? meanMotionDdot,
  }) {
    return Omm(
      objectName: _resolve<String?>(updateObjectName, objectName),
      objectId: _resolve<String?>(updateObjectId, objectId),
      epoch: epoch ?? this.epoch,
      centerName: centerName ?? this.centerName,
      refFrame: refFrame ?? this.refFrame,
      timeSystem: timeSystem ?? this.timeSystem,
      meanElementTheory: meanElementTheory ?? this.meanElementTheory,
      meanMotion: meanMotion ?? this.meanMotion,
      eccentricity: eccentricity ?? this.eccentricity,
      inclination: inclination ?? this.inclination,
      raOfAscNode: raOfAscNode ?? this.raOfAscNode,
      argOfPericenter: argOfPericenter ?? this.argOfPericenter,
      meanAnomaly: meanAnomaly ?? this.meanAnomaly,
      ephemerisType: ephemerisType ?? this.ephemerisType,
      classificationType: classificationType ?? this.classificationType,
      noradCatId: noradCatId ?? this.noradCatId,
      elementSetNo: elementSetNo ?? this.elementSetNo,
      revAtEpoch: revAtEpoch ?? this.revAtEpoch,
      bstar: bstar ?? this.bstar,
      meanMotionDot: meanMotionDot ?? this.meanMotionDot,
      meanMotionDdot: meanMotionDdot ?? this.meanMotionDdot,
    );
  }

  @override
  String toString() {
    return 'Omm(noradCatId: $noradCatId, objectName: $objectName, '
        'epoch: $epoch)';
  }
}

// -- Private helpers --

String _jsonString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    throw StateError('Missing required OMM field: $key');
  }
  return value.toString();
}

int _jsonInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    throw StateError('Missing required OMM field: $key');
  }
  return value is int ? value : int.parse(value.toString());
}

double _jsonDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    throw StateError('Missing required OMM field: $key');
  }
  return value is double ? value : double.parse(value.toString());
}

DateTime _parseIso8601(String source) {
  return DateTime.parse(source).toUtc();
}
