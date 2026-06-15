/// Immutable CelesTrak SATCAT (Satellite Catalog) metadata domain model.
///
/// SATCAT carries per-object *metadata* - owner/country, launch, decay, object
/// type, operational status, and size - as a concern **separate** from the
/// orbital `SatelliteTle`/`Omm` records. The two datasets are joined only by
/// NORAD catalog number; this model never references or mutates the GP types.
///
/// See also:
/// - [ADR-0010: hand-written models](https://github.com/macstarosielec/celestrak/blob/main/doc/adr/0010-hand-written-models.md)
/// - [ADR-0014: SATCAT as a separate concern](https://github.com/macstarosielec/celestrak/blob/main/doc/adr/0014-satcat-separate-concern.md)
library;

import 'package:celestrak/src/domain/satcat_owner.dart';
import 'package:meta/meta.dart';

/// Classification of a catalogued space object by the SATCAT `OBJECT_TYPE`
/// field.
enum SatcatObjectType {
  /// An operational or payload object (`PAYLOAD`).
  payload,

  /// A spent rocket body (`ROCKET BODY`).
  rocketBody,

  /// Fragmentation or mission-related debris (`DEBRIS`).
  debris,

  /// Type unspecified, unrecognised, or absent.
  unknown;

  /// Resolves a raw CelesTrak `OBJECT_TYPE` string to a [SatcatObjectType].
  ///
  /// `PAYLOAD` -> [payload], `ROCKET BODY` -> [rocketBody], `DEBRIS` ->
  /// [debris]. `null`, an empty string, or any unrecognised value -> [unknown].
  /// Matching is case-insensitive and tolerant of surrounding whitespace.
  static SatcatObjectType fromCode(String? code) {
    final normalised = code?.trim().toUpperCase();
    return switch (normalised) {
      'PAYLOAD' => SatcatObjectType.payload,
      'ROCKET BODY' => SatcatObjectType.rocketBody,
      'DEBRIS' => SatcatObjectType.debris,
      _ => SatcatObjectType.unknown,
    };
  }
}

/// Sentinel marking an omitted [SatcatEntry.copyWith] argument.
const Object _unset = Object();

/// Resolves a nullable [SatcatEntry.copyWith] argument.
///
/// Returns [fallback] when [value] is the [_unset] sentinel (argument
/// omitted); otherwise returns [value] cast to `T`. Callers only ever pass
/// the sentinel, `null`, or a `T`, so the cast is safe.
T _resolve<T>(Object? value, T fallback) {
  if (identical(value, _unset)) return fallback;
  return value as T;
}

/// A single CelesTrak SATCAT catalogue record.
///
/// Immutable value type. Two instances are equal when all stored fields are
/// equal (value equality via [==] and [hashCode]). Joined to orbital data by
/// [noradId]; the package never merges this into `SatelliteTle`.
///
/// ```dart
/// final entry = SatcatEntry.fromCelestrakJson(json);
/// if (entry.isPayload && entry.isOnOrbit) {
///   print('${entry.name} (${entry.ownerCode}) is an active payload');
/// }
/// ```
@immutable
final class SatcatEntry {
  /// Creates a [SatcatEntry] with the given fields.
  const SatcatEntry({
    required this.noradId,
    required this.name,
    required this.ownerCode,
    required this.objectType,
    this.objectId,
    this.launchDate,
    this.launchSite,
    this.decayDate,
    this.periodMinutes,
    this.inclination,
    this.apogeeKm,
    this.perigeeKm,
    this.rcs,
    this.opsStatusCode,
  });

  /// Parses a single CelesTrak SATCAT JSON object into a [SatcatEntry].
  ///
  /// [json] keys are the uppercase CelesTrak SATCAT field names. `NORAD_CAT_ID`
  /// is required and must yield a valid integer; a missing or non-integer value
  /// throws a [FormatException]. `OBJECT_NAME` and `OWNER` fall back to `''`
  /// when absent. Date fields (`LAUNCH_DATE`, `DECAY_DATE`) are parsed as UTC;
  /// empty strings and `N/A` sentinels normalise to `null`. Numeric fields
  /// tolerate both JSON numbers and numeric strings, and absent or
  /// unparseable values become `null` (never `0.0`). Unrecognised `OBJECT_TYPE`
  /// values map to [SatcatObjectType.unknown]. Unmodelled keys are ignored.
  factory SatcatEntry.fromCelestrakJson(Map<String, dynamic> json) {
    return SatcatEntry(
      noradId: _requiredInt(json, 'NORAD_CAT_ID'),
      objectId: _optionalString(json, 'OBJECT_ID'),
      name: _optionalString(json, 'OBJECT_NAME') ?? '',
      ownerCode: _optionalString(json, 'OWNER') ?? '',
      launchDate: _optionalDate(json, 'LAUNCH_DATE'),
      launchSite: _optionalString(json, 'LAUNCH_SITE'),
      decayDate: _optionalDate(json, 'DECAY_DATE'),
      periodMinutes: _optionalDouble(json, 'PERIOD'),
      inclination: _optionalDouble(json, 'INCLINATION'),
      apogeeKm: _optionalDouble(json, 'APOGEE'),
      perigeeKm: _optionalDouble(json, 'PERIGEE'),
      rcs: _optionalDouble(json, 'RCS'),
      objectType:
          SatcatObjectType.fromCode(_optionalString(json, 'OBJECT_TYPE')),
      opsStatusCode: _optionalString(json, 'OPS_STATUS_CODE'),
    );
  }

  /// NORAD catalog number. Required; supports 6+ digit values.
  final int noradId;

  /// International Designator (`YYYY-NNNAAA`). Null if unavailable.
  final String? objectId;

  /// Object name. Never null; empty-string fallback if absent.
  final String name;

  /// Raw SATCAT `OWNER` code (e.g. `US`, `PRC`, `CIS`, `ESA`). `''` if absent.
  ///
  /// Resolution to a human-readable country/region is a separate concern and
  /// is not provided by this model.
  final String ownerCode;

  /// Launch date in UTC. Null if absent or unknown.
  final DateTime? launchDate;

  /// Launch site code (e.g. `AFETR`, `TYMSC`). Null if absent.
  final String? launchSite;

  /// Decay (re-entry) date in UTC. `null` means the object is on-orbit.
  final DateTime? decayDate;

  /// Orbital period in minutes. Null if absent.
  final double? periodMinutes;

  /// Orbital inclination in degrees. Null if absent.
  final double? inclination;

  /// Apogee altitude in kilometres. Null if absent.
  final double? apogeeKm;

  /// Perigee altitude in kilometres. Null if absent.
  final double? perigeeKm;

  /// Radar cross-section in square metres. Null if absent or `N/A`.
  final double? rcs;

  /// Object type classification. [SatcatObjectType.unknown] if unrecognised.
  final SatcatObjectType objectType;

  /// Raw operational-status code (e.g. `+`, `-`, `D`). Null if absent.
  final String? opsStatusCode;

  /// Whether the object is still on-orbit: `true` when [decayDate] is `null`.
  bool get isOnOrbit => decayDate == null;

  /// Whether this object is a payload ([SatcatObjectType.payload]).
  bool get isPayload => objectType == SatcatObjectType.payload;

  /// The owner resolved from [ownerCode] against the bundled, offline
  /// owner-code -> country/region table (see [satcatOwnerForCode]).
  ///
  /// Pure and offline; never throws. An unmapped or empty [ownerCode] yields a
  /// passthrough [SatcatOwner] whose `name` equals the code and whose `region`
  /// is `null`.
  SatcatOwner get owner => satcatOwnerForCode(ownerCode);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SatcatEntry &&
        other.noradId == noradId &&
        other.objectId == objectId &&
        other.name == name &&
        other.ownerCode == ownerCode &&
        other.launchDate == launchDate &&
        other.launchSite == launchSite &&
        other.decayDate == decayDate &&
        other.periodMinutes == periodMinutes &&
        other.inclination == inclination &&
        other.apogeeKm == apogeeKm &&
        other.perigeeKm == perigeeKm &&
        other.rcs == rcs &&
        other.objectType == objectType &&
        other.opsStatusCode == opsStatusCode;
  }

  @override
  int get hashCode {
    return Object.hash(
      noradId,
      objectId,
      name,
      ownerCode,
      launchDate,
      launchSite,
      decayDate,
      periodMinutes,
      inclination,
      apogeeKm,
      perigeeKm,
      rcs,
      objectType,
      opsStatusCode,
    );
  }

  /// Returns a new [SatcatEntry] with the specified fields replaced.
  ///
  /// Fields not provided retain their current values. Pass an explicit `null`
  /// to any nullable field to clear it.
  SatcatEntry copyWith({
    int? noradId,
    Object? objectId = _unset,
    String? name,
    String? ownerCode,
    Object? launchDate = _unset,
    Object? launchSite = _unset,
    Object? decayDate = _unset,
    Object? periodMinutes = _unset,
    Object? inclination = _unset,
    Object? apogeeKm = _unset,
    Object? perigeeKm = _unset,
    Object? rcs = _unset,
    SatcatObjectType? objectType,
    Object? opsStatusCode = _unset,
  }) {
    return SatcatEntry(
      noradId: noradId ?? this.noradId,
      objectId: _resolve<String?>(objectId, this.objectId),
      name: name ?? this.name,
      ownerCode: ownerCode ?? this.ownerCode,
      launchDate: _resolve<DateTime?>(launchDate, this.launchDate),
      launchSite: _resolve<String?>(launchSite, this.launchSite),
      decayDate: _resolve<DateTime?>(decayDate, this.decayDate),
      periodMinutes: _resolve<double?>(periodMinutes, this.periodMinutes),
      inclination: _resolve<double?>(inclination, this.inclination),
      apogeeKm: _resolve<double?>(apogeeKm, this.apogeeKm),
      perigeeKm: _resolve<double?>(perigeeKm, this.perigeeKm),
      rcs: _resolve<double?>(rcs, this.rcs),
      objectType: objectType ?? this.objectType,
      opsStatusCode: _resolve<String?>(opsStatusCode, this.opsStatusCode),
    );
  }

  @override
  String toString() {
    return 'SatcatEntry(noradId: $noradId, name: $name, '
        'ownerCode: $ownerCode, objectType: ${objectType.name})';
  }
}

/// Reads a required integer field, throwing [FormatException] when missing or
/// not parseable as an integer.
int _requiredInt(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value == null) {
    throw FormatException('missing required SATCAT field "$key"');
  }
  if (value is num) return value.toInt();
  final parsed = int.tryParse(value.toString().trim());
  if (parsed == null) {
    throw FormatException('expected an integer for "$key", got "$value"');
  }
  return parsed;
}

/// Reads an optional string field. Returns `null` when absent or when the
/// value normalises to an empty string or the `N/A` sentinel.
String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text.toUpperCase() == 'N/A') return null;
  return text;
}

/// Reads an optional numeric field, tolerating JSON numbers and numeric
/// strings. Returns `null` when absent, empty, `N/A`, or unparseable.
double? _optionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final text = value.toString().trim();
  if (text.isEmpty || text.toUpperCase() == 'N/A') return null;
  return double.tryParse(text);
}

/// Reads an optional UTC date field. Returns `null` when absent, empty, or
/// `N/A`; a zoneless timestamp is interpreted as UTC.
DateTime? _optionalDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text.toUpperCase() == 'N/A') return null;
  final hasZone =
      text.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(text);
  // A date-only value (no time component) cannot take a bare `Z` suffix; widen
  // it to a full UTC midnight timestamp so a zoneless date is read as UTC. A
  // space-separated datetime contains ' ', so it takes the bare-`Z` branch,
  // which `DateTime.tryParse` accepts.
  final isDateOnly = !text.contains('T') && !text.contains(' ');
  final normalised = hasZone
      ? text
      : isDateOnly
          ? '${text}T00:00:00Z'
          : '${text}Z';
  return DateTime.tryParse(normalised)?.toUtc();
}
