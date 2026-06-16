/// Abstract repository interface for fetching CelesTrak SATCAT metadata.
///
/// Implementations orchestrate remote fetch and parsing (and, from P9.5,
/// dataset-discriminated caching) into [SatcatEntry] values. SATCAT is a
/// concern distinct from the orbital GP/OMM data (ADR-14), so this interface is
/// separate from `TleRepository`: a SATCAT-specific type with its own methods
/// and its own (future) cache namespace.
library;

import 'package:celestrak/src/domain/failures.dart'
    show NetworkException, SatcatParseException, SatelliteNotFoundException;
import 'package:celestrak/src/domain/satcat_entry.dart';

/// Contract for fetching [SatcatEntry] records.
///
/// The repository hides the fetch and parse pipeline from callers. A
/// single-record lookup ([fetchByNoradId]) raises
/// [SatelliteNotFoundException] when the object is not catalogued; the bulk
/// methods ([fetchByGroup], [fetchByIntlDesignator], [fetchAll]) return an
/// empty list when nothing matches.
///
/// Caching is introduced in a later phase; the current contract fetches on
/// every call. The interface is the stable seam against which the cache is
/// wired without changing callers.
abstract interface class SatcatRepository {
  /// Fetches the SATCAT metadata record for a single satellite by NORAD
  /// catalog number.
  ///
  /// Throws [SatelliteNotFoundException] when the object is not in the SATCAT
  /// catalogue.
  ///
  /// Throws [SatcatParseException] when the response body is present but
  /// malformed.
  ///
  /// Throws [NetworkException] on transport failure.
  ///
  /// Throws [ArgumentError] if [noradId] is less than 1.
  Future<SatcatEntry> fetchByNoradId(int noradId);

  /// Fetches the SATCAT metadata records for a satellite group.
  ///
  /// Returns an empty list when the group matches no records; a zero result is
  /// never thrown.
  ///
  /// Throws [NetworkException] on transport failure.
  ///
  /// Throws [ArgumentError] if [group] is empty.
  Future<List<SatcatEntry>> fetchByGroup(String group);

  /// Fetches the SATCAT metadata records matching an international designator.
  ///
  /// Returns an empty list when the designator matches no records; a zero
  /// result is never thrown.
  ///
  /// Throws [NetworkException] on transport failure.
  ///
  /// Throws [ArgumentError] if [intlDesignator] is empty.
  Future<List<SatcatEntry>> fetchByIntlDesignator(String intlDesignator);

  /// Fetches the full active SATCAT catalogue.
  ///
  /// Returns an empty list when the catalogue is empty; a zero result is never
  /// thrown. The result is large (tens of thousands of records).
  ///
  /// Throws [NetworkException] on transport failure.
  Future<List<SatcatEntry>> fetchAll();
}
