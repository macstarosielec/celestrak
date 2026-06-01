/// Helpers for creating and tearing down temporary cache directories.
library;

import 'dart:io';

/// Creates a temporary directory for use in a single test.
///
/// Call [tearDown] in the test's `tearDown` callback to remove it.
final class TempCache {
  TempCache() : directory = Directory.systemTemp.createTempSync('celestrak_');

  /// The temporary directory created for this test.
  final Directory directory;

  /// Deletes [directory] and all its contents.
  void tearDown() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}
