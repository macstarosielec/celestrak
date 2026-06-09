/// Returns `false` on platforms without `dart:io` (web, WASM).
bool isSocketException(Object e) => false;
