/// Enumerations used throughout the celestrak package:
/// [TleSource], [CelestrakFormat], and [SatelliteCategory].
library;

/// Origin of a `SatelliteTle` record.
enum TleSource {
  /// Fetched live from the CelesTrak GP API.
  celestrak,

  /// Fetched live from Space-Track.org (credentialed access).
  spacetrack,

  /// Served from the local file cache.
  ///
  /// The original remote source of the cached data is not distinguished here;
  /// use `SatelliteTle.fetchedAt` and `SatelliteTle.epoch` to assess age.
  local,
}

/// Wire format used when requesting data from the CelesTrak GP API.
///
/// The default is [omm], which provides richer fields and supports catalog
/// numbers larger than 99999.
enum CelestrakFormat {
  /// Legacy Three-Line Element (3LE / TLE) text format.
  ///
  /// Simpler to parse but limited to 5-digit catalog numbers and carries
  /// fewer fields than [omm].
  tle,

  /// Modern Orbit Mean-Elements Message (OMM) JSON format.
  ///
  /// Recommended default: supports 9-digit catalog numbers and exposes all
  /// CCSDS mandatory keywords.
  omm,
}

/// A named CelesTrak satellite group, mapping to the `GROUP` query key.
///
/// Pass a value to `fetchCategory` to retrieve all objects in that group.
/// Groups not covered by this enum are not yet supported; file a feature
/// request if you need unlisted groups.
///
/// The mapping between enum values and CelesTrak group strings is tested
/// against fixture data in the test suite.
///
/// ```dart
/// final stations = await client.fetchCategory(SatelliteCategory.stations);
/// ```
enum SatelliteCategory {
  /// Space stations, including the ISS and Tiangong.
  stations,

  /// Starlink constellation.
  starlink,

  /// Weather satellites (NOAA, GOES, Meteosat, and similar).
  weather,

  /// Amateur radio satellites.
  amateur,

  /// The brightest, most visually observable objects.
  visual,

  /// GPS operational constellation.
  gps,

  /// Galileo navigation constellation.
  galileo,

  /// GLONASS operational constellation.
  glonass,

  /// Debris from the 2009 Cosmos 2251 / Iridium 33 collision.
  ///
  /// This value targets the Cosmos 2251 / Iridium 33 collision debris, which
  /// is the largest single tracked debris population on CelesTrak. It does
  /// **not** represent all catalogued debris. Other debris groups (e.g.
  /// Fengyun 1C, Iridium 33) are not yet exposed; additional enum values may
  /// be added in a future release.
  cosmos2251Debris,

  /// All active payloads in the catalog.
  active,

  /// Objects launched in the last 30 days.
  lastThirtyDays;

  /// The CelesTrak `GROUP` query string for this category.
  ///
  /// Used as the `GROUP=` value in the CelesTrak GP API request.
  String get group => switch (this) {
        SatelliteCategory.stations => 'stations',
        SatelliteCategory.starlink => 'starlink',
        SatelliteCategory.weather => 'weather',
        SatelliteCategory.amateur => 'amateur',
        SatelliteCategory.visual => 'visual',
        SatelliteCategory.gps => 'gps-ops',
        SatelliteCategory.galileo => 'galileo',
        SatelliteCategory.glonass => 'glo-ops',
        SatelliteCategory.cosmos2251Debris => 'cosmos-2251-debris',
        SatelliteCategory.active => 'active',
        SatelliteCategory.lastThirtyDays => 'last-30-days',
      };
}
