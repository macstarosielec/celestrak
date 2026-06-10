/// Native (`dart:io`) implementation of [defaultCacheStore].
library;

import 'dart:io' show Directory;

import 'package:celestrak/src/data/local/cache_store.dart';
import 'package:celestrak/src/data/local/file_cache_store.dart';

/// Returns a [FileCacheStore] rooted at [cacheDir].
CacheStore defaultCacheStore(String cacheDir) =>
    FileCacheStore(Directory(cacheDir));
