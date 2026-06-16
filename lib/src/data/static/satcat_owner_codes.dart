/// Bundled, offline CelesTrak SATCAT `OWNER`/source code table.
///
/// CelesTrak uses bespoke, *non-ISO* owner/source codes (for example `PRC` for
/// China, `CIS` for the former-USSR/Russia bloc, `GER` for Germany). The
/// authoritative list is published at `celestrak.org/satcat/sources.php` and
/// this table is reconciled against it (CEL-150): every source code on that
/// page is mapped here, except the two administrative sentinels `TBD`
/// ("To Be Determined") and `UNK` ("Unknown"), which are not real owners and
/// are deliberately left to the passthrough path below.
///
/// Any code absent from this map degrades gracefully to a passthrough
/// [SatcatOwner] that echoes the raw code (see [satcatOwnerForCode]), so a code
/// CelesTrak adds before this table catches up is never an error - only an
/// un-prettified one.
///
/// The map is a compile-time `const`: it carries no assets, performs no I/O,
/// and needs no `path_provider`. It is pure-Dart and tree-shakeable, so unused
/// entries are dropped by the compiler.
///
/// Each entry maps a raw SATCAT `OWNER` code to a human-readable [SatcatOwner]
/// carrying the country/organisation name, a coarse continental `region`, and
/// the `isEuSovereign` flag (see the criterion documented on [SatcatOwner]).
/// Names are cleaned, ASCII, human-readable labels rather than verbatim copies
/// of the CelesTrak descriptions (e.g. `China`, not "People's Republic of
/// China"; `Morocco`, not the site's "Morroco" typo).
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

/// The bundled CelesTrak SATCAT owner/source code table.
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
  // organisations controlled by EU member states. ESRO is the direct
  // predecessor of ESA (merged into it in 1975) and is classified identically.
  'ESA': SatcatOwner(
    code: 'ESA',
    name: 'European Space Agency',
    region: _europe,
    isEuSovereign: true,
  ),
  'ESRO': SatcatOwner(
    code: 'ESRO',
    name: 'European Space Research Organization',
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
  // FGER and FRIT are CelesTrak codes for joint missions whose every
  // participant is an EU-27 member state (France/Germany, France/Italy), so by
  // the all-EU-participant rule they are EU-sovereign and sit in Europe.
  'FGER': SatcatOwner(
    code: 'FGER',
    name: 'France/Germany',
    region: _europe,
    isEuSovereign: true,
  ),
  'FRIT': SatcatOwner(
    code: 'FRIT',
    name: 'France/Italy',
    region: _europe,
    isEuSovereign: true,
  ),

  // -- EU-27 member states (EU-sovereign) ------------------------------------
  // The 23 EU-27 members that have a CelesTrak owner code. Cyprus, Latvia,
  // Malta, and Slovakia have no code on the authoritative list and so are
  // (correctly) absent.
  'ASRA': SatcatOwner(
    code: 'ASRA',
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
  'BUL': SatcatOwner(
    code: 'BUL',
    name: 'Bulgaria',
    region: _europe,
    isEuSovereign: true,
  ),
  'HRV': SatcatOwner(
    code: 'HRV',
    name: 'Croatia',
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
  'EST': SatcatOwner(
    code: 'EST',
    name: 'Estonia',
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
  'IRL': SatcatOwner(
    code: 'IRL',
    name: 'Ireland',
    region: _europe,
    isEuSovereign: true,
  ),
  'IT': SatcatOwner(
    code: 'IT',
    name: 'Italy',
    region: _europe,
    isEuSovereign: true,
  ),
  'LTU': SatcatOwner(
    code: 'LTU',
    name: 'Lithuania',
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
  'ROM': SatcatOwner(
    code: 'ROM',
    name: 'Romania',
    region: _europe,
    isEuSovereign: true,
  ),
  'SVN': SatcatOwner(
    code: 'SVN',
    name: 'Slovenia',
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
  'UKR': SatcatOwner(
    code: 'UKR',
    name: 'Ukraine',
    region: _europe,
  ),
  'BELA': SatcatOwner(
    code: 'BELA',
    name: 'Belarus',
    region: _europe,
  ),
  'MDA': SatcatOwner(
    code: 'MDA',
    name: 'Moldova',
    region: _europe,
  ),
  'MNE': SatcatOwner(
    code: 'MNE',
    name: 'Montenegro',
    region: _europe,
  ),
  'MCO': SatcatOwner(
    code: 'MCO',
    name: 'Monaco',
    region: _europe,
  ),
  'VAT': SatcatOwner(
    code: 'VAT',
    name: 'Vatican City',
    region: _europe,
  ),
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
  // Trans-continental owners whose landmass is mostly in Asia are filed here
  // (Armenia, Azerbaijan, Kazakhstan, Turkey), matching the UN Western/Central
  // Asia geoscheme.
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
  'ISRO': SatcatOwner(
    code: 'ISRO',
    name: 'Indian Space Research Organisation',
    region: _asia,
  ),
  'SKOR': SatcatOwner(
    code: 'SKOR',
    name: 'Republic of Korea',
    region: _asia,
  ),
  'NKOR': SatcatOwner(
    code: 'NKOR',
    name: 'North Korea',
    region: _asia,
  ),
  'ISRA': SatcatOwner(
    code: 'ISRA',
    name: 'Israel',
    region: _asia,
  ),
  'ROC': SatcatOwner(
    code: 'ROC',
    name: 'Taiwan',
    region: _asia,
  ),
  'INDO': SatcatOwner(
    code: 'INDO',
    name: 'Indonesia',
    region: _asia,
  ),
  'RP': SatcatOwner(
    code: 'RP',
    name: 'Philippines',
    region: _asia,
  ),
  'MALA': SatcatOwner(
    code: 'MALA',
    name: 'Malaysia',
    region: _asia,
  ),
  'SING': SatcatOwner(
    code: 'SING',
    name: 'Singapore',
    region: _asia,
  ),
  'THAI': SatcatOwner(
    code: 'THAI',
    name: 'Thailand',
    region: _asia,
  ),
  'VTNM': SatcatOwner(
    code: 'VTNM',
    name: 'Vietnam',
    region: _asia,
  ),
  'PAKI': SatcatOwner(
    code: 'PAKI',
    name: 'Pakistan',
    region: _asia,
  ),
  'BGD': SatcatOwner(
    code: 'BGD',
    name: 'Bangladesh',
    region: _asia,
  ),
  'LKA': SatcatOwner(
    code: 'LKA',
    name: 'Sri Lanka',
    region: _asia,
  ),
  'NPL': SatcatOwner(
    code: 'NPL',
    name: 'Nepal',
    region: _asia,
  ),
  'BHUT': SatcatOwner(
    code: 'BHUT',
    name: 'Bhutan',
    region: _asia,
  ),
  'MMR': SatcatOwner(
    code: 'MMR',
    name: 'Myanmar',
    region: _asia,
  ),
  'LAOS': SatcatOwner(
    code: 'LAOS',
    name: 'Laos',
    region: _asia,
  ),
  'MNG': SatcatOwner(
    code: 'MNG',
    name: 'Mongolia',
    region: _asia,
  ),
  'KAZ': SatcatOwner(
    code: 'KAZ',
    name: 'Kazakhstan',
    region: _asia,
  ),
  'ARM': SatcatOwner(
    code: 'ARM',
    name: 'Armenia',
    region: _asia,
  ),
  'AZER': SatcatOwner(
    code: 'AZER',
    name: 'Azerbaijan',
    region: _asia,
  ),
  'IRAN': SatcatOwner(
    code: 'IRAN',
    name: 'Iran',
    region: _asia,
  ),
  'IRAQ': SatcatOwner(
    code: 'IRAQ',
    name: 'Iraq',
    region: _asia,
  ),
  'SAUD': SatcatOwner(
    code: 'SAUD',
    name: 'Saudi Arabia',
    region: _asia,
  ),
  'UAE': SatcatOwner(
    code: 'UAE',
    name: 'United Arab Emirates',
    region: _asia,
  ),
  'QAT': SatcatOwner(
    code: 'QAT',
    name: 'Qatar',
    region: _asia,
  ),
  'BHR': SatcatOwner(
    code: 'BHR',
    name: 'Bahrain',
    region: _asia,
  ),
  'TURK': SatcatOwner(
    code: 'TURK',
    name: 'Turkey',
    region: _asia,
  ),

  // -- Africa (NOT EU-sovereign) ---------------------------------------------
  'SAFR': SatcatOwner(
    code: 'SAFR',
    name: 'South Africa',
    region: _africa,
  ),
  'EGYP': SatcatOwner(
    code: 'EGYP',
    name: 'Egypt',
    region: _africa,
  ),
  'ALG': SatcatOwner(
    code: 'ALG',
    name: 'Algeria',
    region: _africa,
  ),
  'MA': SatcatOwner(
    code: 'MA',
    name: 'Morocco',
    region: _africa,
  ),
  'TUN': SatcatOwner(
    code: 'TUN',
    name: 'Tunisia',
    region: _africa,
  ),
  'SDN': SatcatOwner(
    code: 'SDN',
    name: 'Sudan',
    region: _africa,
  ),
  'NIG': SatcatOwner(
    code: 'NIG',
    name: 'Nigeria',
    region: _africa,
  ),
  'GHA': SatcatOwner(
    code: 'GHA',
    name: 'Ghana',
    region: _africa,
  ),
  'KEN': SatcatOwner(
    code: 'KEN',
    name: 'Kenya',
    region: _africa,
  ),
  'ETH': SatcatOwner(
    code: 'ETH',
    name: 'Ethiopia',
    region: _africa,
  ),
  'ANG': SatcatOwner(
    code: 'ANG',
    name: 'Angola',
    region: _africa,
  ),
  'BWA': SatcatOwner(
    code: 'BWA',
    name: 'Botswana',
    region: _africa,
  ),
  'ZWE': SatcatOwner(
    code: 'ZWE',
    name: 'Zimbabwe',
    region: _africa,
  ),
  'RWA': SatcatOwner(
    code: 'RWA',
    name: 'Rwanda',
    region: _africa,
  ),
  'MUS': SatcatOwner(
    code: 'MUS',
    name: 'Mauritius',
    region: _africa,
  ),
  'DJI': SatcatOwner(
    code: 'DJI',
    name: 'Djibouti',
    region: _africa,
  ),
  'SEN': SatcatOwner(
    code: 'SEN',
    name: 'Senegal',
    region: _africa,
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
  'MEX': SatcatOwner(
    code: 'MEX',
    name: 'Mexico',
    region: _northAmerica,
  ),
  'GUAT': SatcatOwner(
    code: 'GUAT',
    name: 'Guatemala',
    region: _northAmerica,
  ),
  'CRI': SatcatOwner(
    code: 'CRI',
    name: 'Costa Rica',
    region: _northAmerica,
  ),
  // Bermuda is a North Atlantic territory conventionally grouped with North
  // America.
  'BERM': SatcatOwner(
    code: 'BERM',
    name: 'Bermuda',
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
  'CHLE': SatcatOwner(
    code: 'CHLE',
    name: 'Chile',
    region: _southAmerica,
  ),
  'COL': SatcatOwner(
    code: 'COL',
    name: 'Colombia',
    region: _southAmerica,
  ),
  'VENZ': SatcatOwner(
    code: 'VENZ',
    name: 'Venezuela',
    region: _southAmerica,
  ),
  'PERU': SatcatOwner(
    code: 'PERU',
    name: 'Peru',
    region: _southAmerica,
  ),
  'ECU': SatcatOwner(
    code: 'ECU',
    name: 'Ecuador',
    region: _southAmerica,
  ),
  'BOL': SatcatOwner(
    code: 'BOL',
    name: 'Bolivia',
    region: _southAmerica,
  ),
  'PRY': SatcatOwner(
    code: 'PRY',
    name: 'Paraguay',
    region: _southAmerica,
  ),
  'URY': SatcatOwner(
    code: 'URY',
    name: 'Uruguay',
    region: _southAmerica,
  ),

  // -- Oceania (NOT EU-sovereign) --------------------------------------------
  'AUS': SatcatOwner(
    code: 'AUS',
    name: 'Australia',
    region: _oceania,
  ),
  'NZ': SatcatOwner(
    code: 'NZ',
    name: 'New Zealand',
    region: _oceania,
  ),
  'SLB': SatcatOwner(
    code: 'SLB',
    name: 'Solomon Islands',
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
  'IRID': SatcatOwner(
    code: 'IRID',
    name: 'Iridium',
    region: _multinational,
  ),
  'NICO': SatcatOwner(
    code: 'NICO',
    name: 'New ICO',
    region: _multinational,
  ),
  'ABS': SatcatOwner(
    code: 'ABS',
    name: 'Asia Broadcast Satellite',
    region: _multinational,
  ),
  'AC': SatcatOwner(
    code: 'AC',
    name: 'Asia Satellite Telecommunications Company (AsiaSat)',
    region: _multinational,
  ),
  'RASC': SatcatOwner(
    code: 'RASC',
    name: 'RascomStar-QAF',
    region: _multinational,
  ),
  'SEAL': SatcatOwner(
    code: 'SEAL',
    name: 'Sea Launch',
    region: _multinational,
  ),

  // -- Multinational joint owners (mixed participants, NOT EU-sovereign) ------
  // Bilateral codes with at least one non-EU participant: filed Multinational
  // and never EU-sovereign (contrast FGER/FRIT above, whose participants are
  // all EU members).
  'CHBZ': SatcatOwner(
    code: 'CHBZ',
    name: 'China/Brazil',
    region: _multinational,
  ),
  'CHTU': SatcatOwner(
    code: 'CHTU',
    name: 'China/Turkey',
    region: _multinational,
  ),
  'GRSA': SatcatOwner(
    code: 'GRSA',
    name: 'Greece/Saudi Arabia',
    region: _multinational,
  ),
  'PRES': SatcatOwner(
    code: 'PRES',
    name: 'China/European Space Agency',
    region: _multinational,
  ),
  'SGJP': SatcatOwner(
    code: 'SGJP',
    name: 'Singapore/Japan',
    region: _multinational,
  ),
  'STCT': SatcatOwner(
    code: 'STCT',
    name: 'Singapore/Taiwan',
    region: _multinational,
  ),
  'TMMC': SatcatOwner(
    code: 'TMMC',
    name: 'Turkmenistan/Monaco',
    region: _multinational,
  ),
  'USBZ': SatcatOwner(
    code: 'USBZ',
    name: 'United States/Brazil',
    region: _multinational,
  ),
};
