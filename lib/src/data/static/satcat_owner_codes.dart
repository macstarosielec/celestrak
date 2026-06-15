/// Bundled, offline CelesTrak SATCAT `OWNER`/source code table.
///
/// CelesTrak uses bespoke, *non-ISO* owner/source codes (for example `PRC` for
/// China, `CIS` for the former-USSR/Russia bloc, `GER` for Germany). The
/// authoritative list is published at `celestrak.org/satcat/sources.php`.
///
/// IMPORTANT: this is a deliberately CONSERVATIVE, high-confidence subset. At
/// the time it was authored the live CelesTrak sources list was unreachable
/// from every network path, so the table was built from established knowledge
/// rather than scraped from the authoritative source. To keep the package
/// correct, only codes whose exact CelesTrak spelling and country/organisation
/// meaning are well-established are included here; the speculative long tail of
/// obscure single-country codes was intentionally OMITTED. Omission is safe:
/// any code absent from this map degrades gracefully to a passthrough
/// [SatcatOwner] that echoes the raw code (see [satcatOwnerForCode]), so an
/// unmapped owner is never an error - only an un-prettified one.
///
/// Full reconciliation of this table against the authoritative
/// `celestrak.org/satcat/sources.php` list is tracked as CEL-150.
///
/// The map is a compile-time `const`: it carries no assets, performs no I/O,
/// and needs no `path_provider`. It is pure-Dart and tree-shakeable, so unused
/// entries are dropped by the compiler.
///
/// Each entry maps a raw SATCAT `OWNER` code to a human-readable [SatcatOwner]
/// carrying the country/organisation name, a coarse continental `region`, and
/// the `isEuSovereign` flag (see the criterion documented on [SatcatOwner]).
///
/// See also:
/// - [ADR-0015: bundled owner mapping](https://github.com/macstarosielec/celestrak/blob/main/doc/adr/0015-bundled-owner-mapping.md)
library;

import 'package:celestrak/src/domain/satcat_owner.dart';
import 'package:meta/meta.dart';

/// Region label for Africa.
const String _africa = 'Africa';

/// Region label for Asia.
const String _asia = 'Asia';

/// Region label for Europe.
const String _europe = 'Europe';

/// Region label for North America.
const String _northAmerica = 'North America';

/// Region label for South America.
const String _southAmerica = 'South America';

/// Region label for Oceania.
const String _oceania = 'Oceania';

/// Region label for multinational / multi-region owners and consortia.
const String _multinational = 'Multinational';

/// The bundled CelesTrak SATCAT owner/source code table (conservative subset).
///
/// Keys are the raw, upper-case CelesTrak `OWNER` codes exactly as they appear
/// in SATCAT records. Use [satcatOwnerForCode] for lookups: it normalises the
/// input and falls back to a passthrough owner for codes absent from this map.
///
/// Annotated `@internal`: this map is package-internal and is intentionally
/// NOT part of the public `package:celestrak` barrel. Production code reaches
/// it through [satcatOwnerForCode]; tests exercise it directly via a
/// `package:celestrak/src/...` import, the bundled-package convention also used
/// by `satcat_entry_test.dart`. (`@visibleForTesting` would be incorrect here
/// because the symbol is also consumed by production code in
/// [satcatOwnerForCode]; `@internal` signals the same "not public API" intent
/// without that false contract.)
@internal
const Map<String, SatcatOwner> kSatcatOwnerCodes = <String, SatcatOwner>{
  // -- European multinational space organisations (EU-sovereign) -------------
  // EU-sovereign per the criterion on SatcatOwner: European multinational
  // organisations controlled by EU member states.
  'ESA': SatcatOwner(
    code: 'ESA',
    name: 'European Space Agency',
    region: _europe,
    isEuSovereign: true,
  ),
  'EUME': SatcatOwner(
    code: 'EUME',
    name: 'European Organisation for the Exploitation of Meteorological '
        'Satellites (EUMETSAT)',
    region: _europe,
    isEuSovereign: true,
  ),
  'EUTE': SatcatOwner(
    code: 'EUTE',
    name: 'European Telecommunications Satellite Organization (EUTELSAT)',
    region: _europe,
    isEuSovereign: true,
  ),
  // FGER is the CelesTrak code for joint France/Germany missions (for example
  // the Symphonie and TerraSAR-X/TanDEM-X heritage). It is a bilateral
  // operator whose every participant (France and Germany) is an EU-27 member
  // state, so it is EU-sovereign and lives in the Europe region.
  'FGER': SatcatOwner(
    code: 'FGER',
    name: 'France/Germany',
    region: _europe,
    isEuSovereign: true,
  ),

  // -- EU-27 member states (EU-sovereign) ------------------------------------
  'AUS': SatcatOwner(
    code: 'AUS',
    name: 'Austria',
    region: _europe,
    isEuSovereign: true,
  ),
  'BEL': SatcatOwner(
    code: 'BEL',
    name: 'Belgium',
    region: _europe,
    isEuSovereign: true,
  ),
  'CZCH': SatcatOwner(
    code: 'CZCH',
    name: 'Czechia',
    region: _europe,
    isEuSovereign: true,
  ),
  'DEN': SatcatOwner(
    code: 'DEN',
    name: 'Denmark',
    region: _europe,
    isEuSovereign: true,
  ),
  'FIN': SatcatOwner(
    code: 'FIN',
    name: 'Finland',
    region: _europe,
    isEuSovereign: true,
  ),
  'FR': SatcatOwner(
    code: 'FR',
    name: 'France',
    region: _europe,
    isEuSovereign: true,
  ),
  'GER': SatcatOwner(
    code: 'GER',
    name: 'Germany',
    region: _europe,
    isEuSovereign: true,
  ),
  'GREC': SatcatOwner(
    code: 'GREC',
    name: 'Greece',
    region: _europe,
    isEuSovereign: true,
  ),
  'HUN': SatcatOwner(
    code: 'HUN',
    name: 'Hungary',
    region: _europe,
    isEuSovereign: true,
  ),
  'IT': SatcatOwner(
    code: 'IT',
    name: 'Italy',
    region: _europe,
    isEuSovereign: true,
  ),
  'LUXE': SatcatOwner(
    code: 'LUXE',
    name: 'Luxembourg',
    region: _europe,
    isEuSovereign: true,
  ),
  'NETH': SatcatOwner(
    code: 'NETH',
    name: 'Netherlands',
    region: _europe,
    isEuSovereign: true,
  ),
  'POL': SatcatOwner(
    code: 'POL',
    name: 'Poland',
    region: _europe,
    isEuSovereign: true,
  ),
  'POR': SatcatOwner(
    code: 'POR',
    name: 'Portugal',
    region: _europe,
    isEuSovereign: true,
  ),
  'SPN': SatcatOwner(
    code: 'SPN',
    name: 'Spain',
    region: _europe,
    isEuSovereign: true,
  ),
  'SWED': SatcatOwner(
    code: 'SWED',
    name: 'Sweden',
    region: _europe,
    isEuSovereign: true,
  ),

  // -- Non-EU European nations (NOT EU-sovereign) ----------------------------
  'UK': SatcatOwner(
    code: 'UK',
    name: 'United Kingdom',
    region: _europe,
  ),
  'NOR': SatcatOwner(
    code: 'NOR',
    name: 'Norway',
    region: _europe,
  ),
  'SWTZ': SatcatOwner(
    code: 'SWTZ',
    name: 'Switzerland',
    region: _europe,
  ),

  // -- Eurasia (NOT EU-sovereign) --------------------------------------------
  // CIS is the standard CelesTrak owner code for the former-USSR / Russia
  // bloc. Region is reported as Europe because the CIS space programme and its
  // primary owning state (Russia) are centred on European Russia; this is a
  // pragmatic coarse-region choice for a trans-continental owner, not a
  // geopolitical statement.
  'CIS': SatcatOwner(
    code: 'CIS',
    name: 'Commonwealth of Independent States',
    region: _europe,
  ),

  // -- Asia (NOT EU-sovereign) -----------------------------------------------
  'PRC': SatcatOwner(
    code: 'PRC',
    name: 'China',
    region: _asia,
  ),
  'JPN': SatcatOwner(
    code: 'JPN',
    name: 'Japan',
    region: _asia,
  ),
  'IND': SatcatOwner(
    code: 'IND',
    name: 'India',
    region: _asia,
  ),
  'SKOR': SatcatOwner(
    code: 'SKOR',
    name: 'Republic of Korea',
    region: _asia,
  ),
  'ISRA': SatcatOwner(
    code: 'ISRA',
    name: 'Israel',
    region: _asia,
  ),
  'TWN': SatcatOwner(
    code: 'TWN',
    name: 'Taiwan',
    region: _asia,
  ),

  // -- North America (NOT EU-sovereign) --------------------------------------
  'US': SatcatOwner(
    code: 'US',
    name: 'United States',
    region: _northAmerica,
  ),
  'CA': SatcatOwner(
    code: 'CA',
    name: 'Canada',
    region: _northAmerica,
  ),

  // -- South America (NOT EU-sovereign) --------------------------------------
  'BRAZ': SatcatOwner(
    code: 'BRAZ',
    name: 'Brazil',
    region: _southAmerica,
  ),
  'ARGN': SatcatOwner(
    code: 'ARGN',
    name: 'Argentina',
    region: _southAmerica,
  ),

  // -- Africa (NOT EU-sovereign) ---------------------------------------------
  'RSA': SatcatOwner(
    code: 'RSA',
    name: 'South Africa',
    region: _africa,
  ),
  'EGYP': SatcatOwner(
    code: 'EGYP',
    name: 'Egypt',
    region: _africa,
  ),

  // -- Oceania (NOT EU-sovereign) --------------------------------------------
  'AUST': SatcatOwner(
    code: 'AUST',
    name: 'Australia',
    region: _oceania,
  ),

  // -- International consortia & multinational operators (NOT EU-sovereign) ---
  'ISS': SatcatOwner(
    code: 'ISS',
    name: 'International Space Station',
    region: _multinational,
  ),
  'ITSO': SatcatOwner(
    code: 'ITSO',
    name: 'International Telecommunications Satellite Organization (INTELSAT)',
    region: _multinational,
  ),
  'IM': SatcatOwner(
    code: 'IM',
    name: 'International Mobile Satellite Organization (INMARSAT)',
    region: _multinational,
  ),
  'NATO': SatcatOwner(
    code: 'NATO',
    name: 'North Atlantic Treaty Organization',
    region: _multinational,
  ),
  'AB': SatcatOwner(
    code: 'AB',
    name: 'Arab Satellite Communications Organization (ARABSAT)',
    region: _multinational,
  ),
  'SES': SatcatOwner(
    code: 'SES',
    name: 'SES',
    region: _multinational,
  ),
  'O3B': SatcatOwner(
    code: 'O3B',
    name: 'O3b Networks',
    region: _multinational,
  ),
  'GLOB': SatcatOwner(
    code: 'GLOB',
    name: 'Globalstar',
    region: _multinational,
  ),
  'ORB': SatcatOwner(
    code: 'ORB',
    name: 'ORBCOMM',
    region: _multinational,
  ),
};
