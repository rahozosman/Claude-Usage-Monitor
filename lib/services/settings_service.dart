import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// Persists preferences (SharedPreferences) and secrets (OS-encrypted secure
/// storage). Secrets are never written to preferences, logs or source.
class SettingsService {
  SettingsService({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ??
            const FlutterSecureStorage(wOptions: WindowsOptions());

  static const String _settingsKey = 'settings.v1';
  static const String _notificationStateKey = 'notification_state.v1';
  static const String _apiKeyId = 'anthropic_api_key';
  static const String _adminKeyId = 'anthropic_admin_key';

  final FlutterSecureStorage _secure;
  SharedPreferences? _prefs;
  bool secureStorageAvailable = true;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  AppSettings load() {
    final raw = _prefs?.getString(_settingsKey);
    if (raw == null) return const AppSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return AppSettings.fromJson(decoded);
    } catch (_) {
      // Corrupt prefs: fall back to defaults rather than crash.
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    await _prefs?.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Map<String, dynamic> loadNotificationState() {
    final raw = _prefs?.getString(_notificationStateKey);
    if (raw == null) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> saveNotificationState(Map<String, dynamic> state) async {
    await _prefs?.setString(_notificationStateKey, jsonEncode(state));
  }

  // ---- Secrets -------------------------------------------------------------

  /// Secure storage first, then the conventional environment variable.
  Future<SecretValue> readApiKey() => _readSecret(_apiKeyId, 'ANTHROPIC_API_KEY');

  Future<SecretValue> readAdminKey() => _readSecret(_adminKeyId, 'ANTHROPIC_ADMIN_KEY');

  Future<void> writeApiKey(String? value) => _writeSecret(_apiKeyId, value);

  Future<void> writeAdminKey(String? value) => _writeSecret(_adminKeyId, value);

  Future<SecretValue> _readSecret(String id, String envName) async {
    String? stored;
    try {
      stored = await _secure.read(key: id);
      secureStorageAvailable = true;
    } catch (e) {
      secureStorageAvailable = false;
      debugPrint('Secure storage read failed: ${e.runtimeType}');
    }
    if (stored != null && stored.trim().isNotEmpty) {
      return SecretValue(stored.trim(), SecretOrigin.secureStorage);
    }
    final env = Platform.environment[envName];
    if (env != null && env.trim().isNotEmpty) {
      return SecretValue(env.trim(), SecretOrigin.environment);
    }
    return const SecretValue(null, SecretOrigin.none);
  }

  Future<void> _writeSecret(String id, String? value) async {
    try {
      if (value == null || value.trim().isEmpty) {
        await _secure.delete(key: id);
      } else {
        await _secure.write(key: id, value: value.trim());
      }
      secureStorageAvailable = true;
    } catch (e) {
      secureStorageAvailable = false;
      debugPrint('Secure storage write failed: ${e.runtimeType}');
      rethrow;
    }
  }
}

enum SecretOrigin { secureStorage, environment, none }

class SecretValue {
  const SecretValue(this.value, this.origin);

  final String? value;
  final SecretOrigin origin;

  bool get isSet => value != null && value!.isNotEmpty;
}
