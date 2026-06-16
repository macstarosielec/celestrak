import 'dart:io' show File;

import 'package:celestrak/celestrak.dart';
import 'package:celestrak/src/data/remote/satcat_data_source.dart';
import 'package:celestrak/src/data/satcat_repository_impl.dart';
import 'package:celestrak/src/network/http_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

late String _issSatcatObject;
late String _groupStations;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testBase = 'https://celestrak.test/satcat/records.php';

/// Creates a [SatcatRepositoryImpl] wired to a [MockClient] data source.
SatcatRepositoryImpl _repo(
  MockClientHandler handler, {
  int maxAttempts = 1,
}) =>
    SatcatRepositoryImpl(
      dataSource: SatcatDataSource(
        transport: HttpTransport(
          client: MockClient(handler),
          maxAttempts: maxAttempts,
          timeout: const Duration(seconds: 5),
        ),
        baseUrl: _testBase,
      ),
    );

void main() {
  setUpAll(() async {
    _issSatcatObject =
        await File('test/fixtures/satcat/iss_25544_satcat.json').readAsString();
    _groupStations = await File(
      'test/fixtures/satcat/satcat_group_stations.json',
    ).readAsString();
  });

  test('implements the SatcatRepository interface', () {
    final repo = _repo((_) async => http.Response(_issSatcatObject, 200));
    expect(repo, isA<SatcatRepository>());
  });

  group('SatcatRepositoryImpl - fetchByNoradId', () {
    test('returns the parsed ISS SatcatEntry', () async {
      final repo = _repo((_) async => http.Response(_issSatcatObject, 200));

      final entry = await repo.fetchByNoradId(25544);

      expect(entry.noradId, equals(25544));
      expect(entry.name, equals('ISS (ZARYA)'));
      expect(entry.owner.isEuSovereign, isFalse);
    });

    test('single-record miss surfaces SatelliteNotFoundException', () async {
      final repo = _repo((_) async => http.Response('[]', 200));

      await expectLater(
        repo.fetchByNoradId(99999),
        throwsA(isA<SatelliteNotFoundException>()),
      );
    });

    test('transport failure surfaces NetworkException', () async {
      final repo = _repo(
        (_) async => http.Response('server error', 503),
      );

      await expectLater(
        repo.fetchByNoradId(25544),
        throwsA(isA<NetworkException>()),
      );
    });

    test('malformed body surfaces SatcatParseException', () async {
      final repo = _repo((_) async => http.Response('not json', 200));

      await expectLater(
        repo.fetchByNoradId(25544),
        throwsA(isA<SatcatParseException>()),
      );
    });

    test('propagates ArgumentError for noradId < 1', () async {
      final repo = _repo((_) async => http.Response(_issSatcatObject, 200));

      await expectLater(
        repo.fetchByNoradId(0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('SatcatRepositoryImpl - bulk methods', () {
    test('fetchByGroup returns the parsed list', () async {
      final repo = _repo((_) async => http.Response(_groupStations, 200));

      final entries = await repo.fetchByGroup('stations');

      expect(entries, hasLength(3));
    });

    test('fetchByGroup with no match returns an empty list', () async {
      final repo = _repo((_) async => http.Response('[]', 200));

      expect(await repo.fetchByGroup('none'), isEmpty);
    });

    test('fetchByIntlDesignator returns the parsed list', () async {
      final repo = _repo((_) async => http.Response(_groupStations, 200));

      final entries = await repo.fetchByIntlDesignator('1998-067');

      expect(entries, hasLength(3));
    });

    test('fetchByIntlDesignator with no match returns an empty list', () async {
      final repo = _repo((_) async => http.Response('[]', 200));

      expect(await repo.fetchByIntlDesignator('1957-001A'), isEmpty);
    });

    test('fetchAll returns the parsed list', () async {
      final repo = _repo((_) async => http.Response(_groupStations, 200));

      final entries = await repo.fetchAll();

      expect(entries, hasLength(3));
    });

    test('fetchAll with empty catalogue returns an empty list', () async {
      final repo = _repo((_) async => http.Response('[]', 200));

      expect(await repo.fetchAll(), isEmpty);
    });
  });
}
