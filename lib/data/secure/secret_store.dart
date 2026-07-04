import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps the OS keystore (Android Keystore / iOS Keychain).
///
/// Holds two kinds of secrets, and nothing else ever leaves the device:
///  * per-provider API keys, keyed by the provider id;
///  * the randomly generated SQLCipher key that encrypts the local database.
class SecretStore {
  SecretStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _dbKeyName = 'owen_db_key_v1';
  String _apiKeyName(String providerId) => 'apikey_$providerId';

  /// Returns the database encryption key, generating a strong random one on
  /// first launch. 256 bits of CSPRNG entropy, stored only in the keystore.
  Future<String> databaseKey() async {
    final existing = await _storage.read(key: _dbKeyName);
    if (existing != null && existing.isNotEmpty) return existing;

    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    final key = base64Url.encode(bytes);
    await _storage.write(key: _dbKeyName, value: key);
    return key;
  }

  Future<String?> apiKey(String providerId) =>
      _storage.read(key: _apiKeyName(providerId));

  Future<void> setApiKey(String providerId, String key) =>
      _storage.write(key: _apiKeyName(providerId), value: key);

  Future<void> deleteApiKey(String providerId) =>
      _storage.delete(key: _apiKeyName(providerId));

  /// Wipes every stored secret (used by "erase all data").
  Future<void> wipe() => _storage.deleteAll();
}
