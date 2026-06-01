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
      if (!await file.exists()) return null;
      // Treat a missing .ts file as a torn write — return null (FR-15/NFR-9).
      final tsFile = File(_tsPath(key));
      if (!await tsFile.exists()) return null;
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
    await File(_dataPath(key)).writeAsBytes(bytes);
    await File(_tsPath(key)).writeAsString(writtenAt.toIso8601String());
  }

  @override
  Future<Duration?> age(String key, DateTime now) async {
    try {
      final tsFile = File(_tsPath(key));
      if (!await tsFile.exists()) return null;
      final raw = await tsFile.readAsString();
      final ts = DateTime.parse(raw.trim());
      return now.difference(ts);
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> clear({String? keyPrefix}) async {
    if (!await directory.exists()) return;
    final entities = await directory.list().toList();
    for (final entity in entities) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (keyPrefix == null || name.startsWith(keyPrefix)) {
        await entity.delete();
      }
    }
  }
}
