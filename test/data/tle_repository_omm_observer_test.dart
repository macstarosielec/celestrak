import 'dart:convert';
import 'dart:io' show File;

import 'package:celestrak/celestrak.dart';
import 'package:celestrak/src/data/remote/celestrak_data_source.dart';
import 'package:celestrak/src/data/tle_repository_impl.dart';
import 'package:celestrak/src/network/http_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _testBase = 'https://celestrak.test/gp.php';
const _defaultedFields = {
  'CENTER_NAME',
  'REF_FRAME',
  'TIME_SYSTEM',
  'MEAN_ELEMENT_THEORY',
};

String _stripDefaults(String ommBody) {
  final list = (jsonDecode(ommBody) as List).cast<Map<String, dynamic>>();
  for (final record in list) {
    record.removeWhere((key, _) => _defaultedFields.contains(key));
  }
  return jsonEncode(list);
}

int _recordCount(String ommBody) => (jsonDecode(ommBody) as List).length;

TleRepositoryImpl _repo({
  required String ommBody,
  required String tleBody,
  required OmmParseObserver observer,
  bool useIsolate = false,
}) {
  return TleRepositoryImpl(
    dataSource: CelestrakDataSource(
      transport: HttpTransport(
        client: MockClient((req) async {
          final format = req.url.queryParameters['FORMAT'];
          return http.Response(format == 'TLE' ? tleBody : ommBody, 200);
        }),
        maxAttempts: 1,
        timeout: const Duration(seconds: 5),
      ),
      baseUrl: _testBase,
    ),
    cacheStore: MemoryCacheStore(),
    useIsolate: useIsolate,
    observer: observer,
  );
}

void main() {
  late String ommFixture;
  late String tleFixture;
  late String stationsOmmFixture;
  late String stationsTleFixture;

  setUpAll(() async {
    ommFixture = await File('test/fixtures/iss_25544_omm.json').readAsString();
    tleFixture = await File('test/fixtures/iss_25544.tle').readAsString();
    stationsOmmFixture = await File(
      'test/fixtures/stations_group_omm.json',
    ).readAsString();
    stationsTleFixture = await File(
      'test/fixtures/stations_group.txt',
    ).readAsString();
  });

  Map<String, int> expectedCounts(int records) => {
        for (final field in _defaultedFields) field: records,
      };

  test('replays defaulted-field counts to the injected observer', () async {
    final calls = <Map<String, int>>[];
    final repo = _repo(
      ommBody: _stripDefaults(ommFixture),
      tleBody: tleFixture,
      observer: calls.add,
    );

    await repo.fetchByNoradId(25544);

    expect(calls, hasLength(1));
    expect(calls.single.keys, containsAll(_defaultedFields));
  });

  test('does not notify when the OMM body carries the fields', () async {
    final calls = <Map<String, int>>[];
    final repo = _repo(
      ommBody: ommFixture,
      tleBody: tleFixture,
      observer: calls.add,
    );

    await repo.fetchByNoradId(25544);

    expect(calls, isEmpty);
  });

  test('replays aggregate category counts on the main isolate', () async {
    final calls = <Map<String, int>>[];
    final stripped = _stripDefaults(stationsOmmFixture);
    final repo = _repo(
      ommBody: stripped,
      tleBody: stationsTleFixture,
      observer: calls.add,
    );

    await repo.fetchCategory(SatelliteCategory.stations);

    expect(calls, hasLength(1));
    expect(calls.single, expectedCounts(_recordCount(stripped)));
  });

  test('replays aggregate category counts from the worker isolate', () async {
    final calls = <Map<String, int>>[];
    final stripped = _stripDefaults(stationsOmmFixture);
    final repo = _repo(
      ommBody: stripped,
      tleBody: stationsTleFixture,
      observer: calls.add,
      useIsolate: true,
    );

    await repo.fetchCategory(SatelliteCategory.stations);

    expect(calls, hasLength(1));
    expect(calls.single, expectedCounts(_recordCount(stripped)));
  });
}
