/// Live integration tests - hit the real CelesTrak SATCAT API.
///
/// These tests are excluded from the default `dart test` run.
/// Run explicitly with:
///   dart test --tags integration
///
/// They require an active internet connection and a reachable celestrak.org.
/// CelesTrak may be unreachable; these tests are skipped offline and are not
/// part of the default green bar.
@Tags(['integration'])
library;

import 'package:celestrak/celestrak.dart';
import 'package:celestrak/src/data/remote/satcat_data_source.dart';
import 'package:celestrak/src/network/http_transport.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Timeout generous enough for a cold network request with one retry.
const _timeout = Duration(seconds: 30);

/// Creates a live [SatcatDataSource] against the production SATCAT endpoint.
///
/// Returns the data source and the owning [http.Client] so the caller can
/// close the client after the test.
({SatcatDataSource source, http.Client client}) _liveSource() {
  final client = http.Client();
  return (
    source: SatcatDataSource(
      transport: HttpTransport(client: client, maxAttempts: 2),
    ),
    client: client,
  );
}

void main() {
  group(
    'CelesTrak SATCAT live API',
    () {
      test(
        'fetchByNoradId returns the ISS SATCAT record (25544)',
        () async {
          final (:source, :client) = _liveSource();
          try {
            final entry = await source.fetchByNoradId(25544);
            expect(entry.noradId, equals(25544));
            expect(entry.name, isNotEmpty);
            expect(entry.ownerCode, isNotEmpty);
          } finally {
            client.close();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );

      test(
        'fetchByNoradId throws SatelliteNotFoundException for an unknown id',
        () async {
          final (:source, :client) = _liveSource();
          try {
            await expectLater(
              source.fetchByNoradId(99999999),
              throwsA(isA<SatelliteNotFoundException>()),
            );
          } finally {
            client.close();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );

      test(
        'fetchByGroup returns a non-empty list for "stations"',
        () async {
          final (:source, :client) = _liveSource();
          try {
            final entries = await source.fetchByGroup('stations');
            expect(entries, isNotEmpty);
            expect(entries.every((e) => e.noradId > 0), isTrue);
          } finally {
            client.close();
          }
        },
        timeout: const Timeout(_timeout),
        tags: 'integration',
      );
    },
    // CelesTrak may reset connections under rapid successive requests;
    // one retry avoids false negatives from transient network errors.
    retry: 1,
  );
}
