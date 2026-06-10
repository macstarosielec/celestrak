/// Web/WASM fallback: no file system, so `cacheDir` is ignored and an
/// in-memory store is returned.
library;

import 'package:celestrak/src/data/local/cache_store.dart';
import 'package:celestrak/src/data/local/memory_cache_store.dart';

/// Returns a [CacheStore] for the current platform. On web/WASM there is no
/// file system, so `cacheDir` is ignored and a [MemoryCacheStore] is returned.
CacheStore defaultCacheStore(String cacheDir) => MemoryCacheStore();
