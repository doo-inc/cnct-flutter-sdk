import 'dart:async';

/// Where a visitor's chat session token is kept between app launches.
///
/// The token is a thirty-day bearer secret scoped to one conversation. Held, the same person comes
/// back to the same thread with their history intact; lost, they are a stranger who has to start
/// again — which is not a failure, just a worse experience.
///
/// **The default is memory, and that is deliberate.** This package has no Flutter dependency and no
/// storage dependency, because forcing `shared_preferences` on a Dart backend or
/// `flutter_secure_storage` on a kiosk build is a decision that belongs to the app rather than to
/// its SDK. Wiring persistence is a handful of lines — see [CnctTokenStore.delegate].
abstract class CnctTokenStore {
  const CnctTokenStore();

  /// Keeps nothing across a restart. Correct for a test, a one-shot script and a kiosk; wrong for
  /// anything a person comes back to.
  factory CnctTokenStore.memory() = _MemoryTokenStore;

  /// Persistence in three callbacks, so any storage plugin fits without this package depending on
  /// one.
  ///
  /// ```dart
  /// final prefs = await SharedPreferences.getInstance();
  /// final store = CnctTokenStore.delegate(
  ///   read: (key) async => prefs.getString(key),
  ///   write: (key, value) async => prefs.setString(key, value),
  ///   clear: (key) async => prefs.remove(key),
  /// );
  /// ```
  factory CnctTokenStore.delegate({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
    required Future<void> Function(String key) clear,
  }) = _DelegateTokenStore;

  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> clear(String key);
}

class _MemoryTokenStore extends CnctTokenStore {
  _MemoryTokenStore();

  final Map<String, String> _held = {};

  @override
  Future<String?> read(String key) async => _held[key];

  @override
  Future<void> write(String key, String value) async => _held[key] = value;

  @override
  Future<void> clear(String key) async => _held.remove(key);
}

class _DelegateTokenStore extends CnctTokenStore {
  _DelegateTokenStore({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
    required Future<void> Function(String key) clear,
  })  : _read = read,
        _write = write,
        _clear = clear;

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final Future<void> Function(String key) _clear;

  @override
  Future<String?> read(String key) => _read(key);

  @override
  Future<void> write(String key, String value) => _write(key, value);

  @override
  Future<void> clear(String key) => _clear(key);
}
