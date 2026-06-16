/// Production implementation of [SatcatRepository].
///
/// For P9.4 the repository is a thin orchestration seam over
/// [SatcatDataSource]: it delegates each call to the data source, which fetches
/// and parses in one step. Caching (a dataset-discriminated key, TTL, and
/// staleness) is wired in a later phase; the data source dependency is injected
/// so that the cache can be layered in without changing this contract or its
/// callers.
library;

import 'package:celestrak/src/data/remote/satcat_data_source.dart';
import 'package:celestrak/src/domain/satcat_entry.dart';
import 'package:celestrak/src/domain/satcat_repository.dart';

/// Production [SatcatRepository] backed by a [SatcatDataSource].
///
/// Each method delegates straight to the data source. The data source owns the
/// URL construction, transport, and SATCAT parsing; this type exists so the
/// fetch pipeline is addressed through a stable interface and so the cache seam
/// (P9.5) has a single place to live.
final class SatcatRepositoryImpl implements SatcatRepository {
  /// Creates a [SatcatRepositoryImpl].
  ///
  /// [dataSource] is the raw CelesTrak SATCAT HTTP data source.
  const SatcatRepositoryImpl({required SatcatDataSource dataSource})
      : _dataSource = dataSource;

  final SatcatDataSource _dataSource;

  @override
  Future<SatcatEntry> fetchByNoradId(int noradId) =>
      _dataSource.fetchByNoradId(noradId);

  @override
  Future<List<SatcatEntry>> fetchByGroup(String group) =>
      _dataSource.fetchByGroup(group);

  @override
  Future<List<SatcatEntry>> fetchByIntlDesignator(String intlDesignator) =>
      _dataSource.fetchByIntlDesignator(intlDesignator);

  @override
  Future<List<SatcatEntry>> fetchAll() => _dataSource.fetchAll();
}
