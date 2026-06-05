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
/// Truncated or missing files are treated as cache misses.
final class FileCacheStore implements CacheStore {
  /// Creates a [FileCacheStore] rooted at [directory].
  const FileCacheStore(this.directory);

  /// The directory where cache files are stored.
  final Directory directory;

  // Windows reserves ':' for drive-letter notation; replace with '-' so
  // keys like 'norad:25544~fmt:omm~src:celestrak' are valid file names on
  // all platforms.
  static String _encode(String key) => key.replaceAll(':', '-');

  String _dataPath(String key) =>
      '${directory.path}${Platform.pathSeparator}${_encode(key)}.bin';

  String _tsPath(String key) =>
      '${directory.path}${Platform.pathSeparator}${_encode(key)}.ts';

  @override
  Future<Uint8List?> read(String key) async {
    // Use EAFP rather than exists()-then-read to avoid the avoid_slow_async_io
    // lint (FileSystemEntity.exists() uses the OS thread pool) and to eliminate
    // the TOCTOU race between a check and the subsequent read.
    try {
      final bytes = await File(_dataPath(key)).readAsBytes();
      if (bytes.isEmpty) return null;
      // Treat a missing .ts file as a torn write — return null.
      // readAsString throws FileSystemException when the file is absent.
      await File(_tsPath(key)).readAsString();
      return bytes;
    } on FileSystemException {
      // File absent or unreadable — treat as cache miss.
      return null;
    } on Exception {
      // Treat any other I/O or format error as a cache miss.
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
    // Two-phase rename write: write both .tmp files first, then rename.
    //
    // Rename order: .bin first, .ts second.
    // read() checks .bin then .ts. A crash between the two renames leaves
    // .bin present but .ts absent — read() returns null (cache miss).
    // This is safer than the reverse order, which would leave a .ts with no
    // .bin and force a spurious stale-age read on the next age() call.
    //
    // Note: rename() is atomic on POSIX when source and destination share the
    // same directory. On Windows rename() is not atomic; cache writes may
    // produce a torn entry on power loss. Callers should treat a cache miss
    // as a normal condition.
    final tmpData = File('${_dataPath(key)}.tmp');
    final tmpTs = File('${_tsPath(key)}.tmp');
    try {
      await tmpData.writeAsBytes(bytes);
      await tmpTs.writeAsString(writtenAt.toIso8601String());
      await tmpData.rename(_dataPath(key));
      await tmpTs.rename(_tsPath(key));
    } on Object catch (_) {
      // Clean up any surviving .tmp files on partial failure.
      for (final tmp in [tmpData, tmpTs]) {
        try {
          await tmp.delete();
        } on FileSystemException {
          // Best-effort cleanup; ignore secondary errors.
        }
      }
      rethrow;
    }
  }

  @override
  Future<Duration?> age(String key, DateTime now) async {
    // Use EAFP rather than exists()-then-read to avoid the avoid_slow_async_io
    // lint and the TOCTOU race between a check and the subsequent read.
    try {
      final raw = await File(_tsPath(key)).readAsString();
      final ts = DateTime.parse(raw.trim());
      return now.difference(ts);
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> clear({String? keyPrefix}) async {
    // Use EAFP rather than directory.exists()-then-list to avoid the
    // avoid_slow_async_io lint and a TOCTOU race. If the directory does not
    // exist, list() throws a FileSystemException which we treat as "nothing to
    // clear".
    final List<FileSystemEntity> entities;
    try {
      entities = await directory.list().toList();
    } on FileSystemException {
      // Directory absent — nothing to clear.
      return;
    }

    // Collect all files and group them by stem (filename without extension).
    // Processing by stem ensures both .bin and .ts are always removed together,
    // preventing orphaned .ts files from returning stale age() values.
    final stems = <String>{};
    for (final entity in entities) {
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
      final encodedPrefix = keyPrefix != null ? _encode(keyPrefix) : null;
      if (stem != null &&
          (encodedPrefix == null || stem.startsWith(encodedPrefix))) {
        stems.add(stem);
      }
    }

    // Delete both files for each matching stem in parallel.
    // Stems are already encoded (colons replaced with '-') — build paths
    // directly from the directory without re-encoding to avoid a latent
    // double-encode bug if _encode is ever extended.
    await Future.wait(
      stems.map((stem) async {
        for (final path in [
          '${directory.path}${Platform.pathSeparator}$stem.bin',
          '${directory.path}${Platform.pathSeparator}$stem.ts',
        ]) {
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
