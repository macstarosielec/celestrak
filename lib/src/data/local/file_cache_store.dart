/// File-system-backed [CacheStore] implementation.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:celestrak/src/data/local/cache_store.dart';

/// A file-system-backed implementation of [CacheStore].
///
/// Each cache entry is stored as two files under [directory]:
/// - `<key>.bin`  — the raw payload bytes
/// - `<key>.ts`   — the ISO-8601 timestamp string written at cache time
///
/// Truncated or missing files are treated as cache misses (FR-15/NFR-9).
final class FileCacheStore implements CacheStore {
  /// Creates a [FileCacheStore] rooted at [directory].
  const FileCacheStore(this.directory);

  /// The directory where cache files are stored.
  final Directory directory;

  String _dataPath(String key) =>
      '${directory.path}${Platform.pathSeparator}$key.bin';

  String _tsPath(String key) =>
      '${directory.path}${Platform.pathSeparator}$key.ts';

  @override
  Future<Uint8List?> read(String key) async {
    try {
      final file = File(_dataPath(key));
      if (!file.existsSync()) return null;
      // Treat a missing .ts file as a torn write — return null (FR-15/NFR-9).
      final tsFile = File(_tsPath(key));
      if (!tsFile.existsSync()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return bytes;
    } on Exception {
      // Treat any I/O or format error as a cache miss (FR-15).
      return null;
    }
  }

  @override
  Future<void> write(
    String key,
    Uint8List bytes,
    DateTime writtenAt,
  ) async {
    await directory.create(recursive: true);
    // Atomic write: write .ts first so that a crash between the two renames
    // leaves .bin absent (read() returns null) rather than stale .ts paired
    // with new .bin (FR-15).
    final tmpData = File('${_dataPath(key)}.tmp');
    final tmpTs = File('${_tsPath(key)}.tmp');
    try {
      await tmpTs.writeAsString(writtenAt.toIso8601String());
      await tmpData.writeAsBytes(bytes);
      await tmpTs.rename(_tsPath(key));
      await tmpData.rename(_dataPath(key));
    } catch (_) {
      // Clean up any surviving .tmp files on partial failure.
      for (final tmp in [tmpData, tmpTs]) {
        try {
          if (tmp.existsSync()) await tmp.delete();
        } on Exception {
          // Best-effort cleanup; ignore secondary errors.
        }
      }
      rethrow;
    }
  }

  @override
  Future<Duration?> age(String key, DateTime now) async {
    try {
      final tsFile = File(_tsPath(key));
      if (!tsFile.existsSync()) return null;
      final raw = await tsFile.readAsString();
      final ts = DateTime.parse(raw.trim());
      return now.difference(ts);
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> clear({String? keyPrefix}) async {
    if (!directory.existsSync()) return;

    // Collect all files and group them by stem (filename without extension).
    // Processing by stem ensures both .bin and .ts are always removed together,
    // preventing orphaned .ts files from returning stale age() values.
    final stems = <String>{};
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final String? stem;
      if (name.endsWith('.bin')) {
        stem = name.substring(0, name.length - 4);
      } else if (name.endsWith('.ts')) {
        stem = name.substring(0, name.length - 3);
      } else {
        stem = null;
      }
      if (stem != null && (keyPrefix == null || stem.startsWith(keyPrefix))) {
        stems.add(stem);
      }
    }

    // Delete both files for each matching stem in parallel.
    await Future.wait(
      stems.map((stem) async {
        for (final path in [_dataPath(stem), _tsPath(stem)]) {
          try {
            await File(path).delete();
          } on Exception {
            // File may have been concurrently removed;
            // treat as already cleared.
          }
        }
      }),
    );
  }
}
