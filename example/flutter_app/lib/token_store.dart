import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistence for a visitor's chat session, in three callbacks.
///
/// The SDK deliberately depends on no storage plugin — forcing `shared_preferences` on a Dart
/// backend, or `flutter_secure_storage` on a kiosk build, is a decision that belongs to the app.
/// This is the whole of what wiring one costs.
///
/// The token is a thirty-day bearer secret scoped to a single conversation. `shared_preferences` is
/// the right home for it in most apps; if yours already carries a keychain dependency, swap the three
/// lines below for it and nothing else changes.
Future<CnctTokenStore> sharedPreferencesTokenStore() async {
  final preferences = await SharedPreferences.getInstance();
  return CnctTokenStore.delegate(
    read: (key) async => preferences.getString(key),
    write: (key, value) async => preferences.setString(key, value),
    clear: (key) async => preferences.remove(key),
  );
}
