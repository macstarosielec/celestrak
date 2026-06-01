/// Helpers for creating and tearing down temporary cache directories.
library;

import 'dart:io';

/// Creates a temporary directory for use in a single test.
///
/// Use [TempCache.create] to construct an instance asynchronously, and call
/// [tearDown] in the test's `tearDown` callback to remove it.
final class TempCache {
  TempCache._(this.directory);

  /// The temporary directory created for this test.
  final Directory directory;

  /// Creates a [TempCache] backed by a new temporary directory.
  static Future<TempCache> create() async {
    final dir = await Directory.systemTemp.createTemp('celestrak_');
    return TempCache._(dir);
  }

  /// Deletes [directory] and all its contents.
  Future<void> tearDown() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}
