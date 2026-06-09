import 'dart:io' show SocketException;

/// Returns `true` when [e] is a `dart:io` [SocketException].
bool isSocketException(Object e) => e is SocketException;
