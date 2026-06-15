/// Owner / country resolution for CelesTrak SATCAT `OWNER` codes.
///
/// SATCAT records carry a terse owner/source code (e.g. `US`, `PRC`, `ESA`).
/// This file turns that code into a human-readable [SatcatOwner] - country or
/// organisation name, coarse region, and an EU-sovereign flag - using a
/// bundled, compile-time `const` table. The lookup is pure and offline: no
/// network, no I/O, no asset bundling, no `path_provider`.
///
/// The bundled table is a deliberately conservative, high-confidence subset of
/// the CelesTrak owner codes; unmapped codes degrade to a passthrough owner.
/// Full reconciliation against `celestrak.org/satcat/sources.php` is tracked
/// as CEL-150. See `kSatcatOwnerCodes` for the table itself.
///
/// See also:
/// - [ADR-0015: bundled owner mapping](https://github.com/macstarosielec/celestrak/blob/main/doc/adr/0015-bundled-owner-mapping.md)
library;

import 'package:celestrak/src/data/static/satcat_owner_codes.dart';
import 'package:meta/meta.dart';

/// A human-readable resolution of a SATCAT `OWNER` code.
///
/// Immutable value type. Two instances are equal when all stored fields are
/// equal (value equality via [==] and [hashCode]). Obtain instances via
/// [satcatOwnerForCode] or `SatcatEntry.owner`.
///
/// ## EU-sovereign criterion
///
/// [isEuSovereign] is `true` when, and only when, the owner is either:
/// - an **EU-27 member state** (the 27 current members of the European Union),
///   or
/// - a **European multinational organisation controlled by EU members**: the
///   European Space Agency (`ESA`), EUMETSAT (`EUME`), EUTELSAT (`EUTE`), or a
///   bilateral operator whose every participant is an EU member state, such as
///   the joint France/Germany operator (`FGER`).
///
/// It is deliberately `false` for non-EU European nations - for example the
/// United Kingdom (`UK`), Norway (`NOR`), and Switzerland (`SWTZ`) - for the
/// Russia/former-USSR bloc (`CIS`), and for all non-European owners (the US,
/// China, Japan, India, and so on). The flag answers OrbitLens FR-4b ("is this
/// an EU-sovereign asset?") rather than a broader "is this European?" question.
///
/// ```dart
/// final owner = satcatOwnerForCode('FR');
/// print('${owner.name} EU-sovereign: ${owner.isEuSovereign}'); // France, true
/// ```
@immutable
final class SatcatOwner {
  /// Creates a [SatcatOwner] with the given fields.
  const SatcatOwner({
    required this.code,
    required this.name,
    this.region,
    this.isEuSovereign = false,
  });

  /// The raw SATCAT `OWNER` code this owner was resolved from (e.g. `PRC`).
  ///
  /// For an unmapped code this is the (trimmed, upper-cased) input verbatim.
  final String code;

  /// Human-readable country or organisation name (e.g. `China`).
  ///
  /// For an unmapped code this equals [code] (passthrough), never empty unless
  /// the input was empty.
  final String name;

  /// Coarse continental region (e.g. `Europe`, `Asia`), or `Multinational`
  /// for consortia and multi-region operators. `null` for an unmapped code.
  final String? region;

  /// Whether the owner is an EU-sovereign asset.
  ///
  /// See the EU-sovereign criterion documented on [SatcatOwner]. `false` for
  /// any unmapped code.
  final bool isEuSovereign;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SatcatOwner &&
        other.code == code &&
        other.name == name &&
        other.region == region &&
        other.isEuSovereign == isEuSovereign;
  }

  @override
  int get hashCode => Object.hash(code, name, region, isEuSovereign);

  @override
  String toString() {
    return 'SatcatOwner(code: $code, name: $name, region: $region, '
        'isEuSovereign: $isEuSovereign)';
  }
}

/// Resolves a raw SATCAT `OWNER` [code] to a [SatcatOwner], fully offline.
///
/// The input is trimmed and upper-cased before lookup, matching how SATCAT
/// `OWNER` values are published (short upper-case codes). A code present in
/// the bundled table resolves to its full [SatcatOwner].
///
/// An **unknown or empty** code never throws: it degrades gracefully to a
/// passthrough `SatcatOwner(code: normalised, name: normalised, region: null,
/// isEuSovereign: false)`, so callers always get a usable value even as
/// CelesTrak adds owner codes the bundled table has not yet caught up with.
SatcatOwner satcatOwnerForCode(String code) {
  final normalised = code.trim().toUpperCase();
  final mapped = kSatcatOwnerCodes[normalised];
  if (mapped != null) return mapped;
  return SatcatOwner(code: normalised, name: normalised);
}
