import 'package:flutter/foundation.dart';

import '../../core/utils/format_utils.dart';
import '../../models/app_settings.dart';
import '../../services/settings_service.dart';
import '../../services/startup_service.dart';

/// Holds [AppSettings] plus derived secret metadata (masked, never the value).
class SettingsController extends ChangeNotifier {
  SettingsController(this._service, this._startup);

  final SettingsService _service;
  final StartupService _startup;

  AppSettings _settings = const AppSettings();
  bool _startWithWindows = false;
  String _apiKeyMasked = 'Not set';
  String _adminKeyMasked = 'Not set';
  SecretOrigin _apiKeyOrigin = SecretOrigin.none;
  SecretOrigin _adminKeyOrigin = SecretOrigin.none;

  AppSettings get settings => _settings;
  bool get startWithWindows => _startWithWindows;
  String get apiKeyMasked => _apiKeyMasked;
  String get adminKeyMasked => _adminKeyMasked;
  SecretOrigin get apiKeyOrigin => _apiKeyOrigin;
  SecretOrigin get adminKeyOrigin => _adminKeyOrigin;
  bool get apiKeySet => _apiKeyOrigin != SecretOrigin.none;
  bool get adminKeySet => _adminKeyOrigin != SecretOrigin.none;
  bool get secureStorageAvailable => _service.secureStorageAvailable;

  Future<void> init() async {
    _settings = _service.load();
    _startWithWindows = await _startup.isEnabled();
    await reloadSecrets();
  }

  Future<void> update(AppSettings Function(AppSettings current) mutate) async {
    _settings = mutate(_settings);
    notifyListeners();
    await _service.save(_settings);
  }

  Future<void> setStartWithWindows(bool enabled) async {
    final ok = await _startup.setEnabled(enabled);
    _startWithWindows = ok ? enabled : await _startup.isEnabled();
    notifyListeners();
  }

  Future<void> setApiKey(String? value) async {
    await _service.writeApiKey(value);
    await reloadSecrets();
  }

  Future<void> setAdminKey(String? value) async {
    await _service.writeAdminKey(value);
    await reloadSecrets();
  }

  Future<void> reloadSecrets() async {
    final api = await _service.readApiKey();
    final admin = await _service.readAdminKey();
    _apiKeyMasked = FormatUtils.maskSecret(api.value);
    _adminKeyMasked = FormatUtils.maskSecret(admin.value);
    _apiKeyOrigin = api.origin;
    _adminKeyOrigin = admin.origin;
    notifyListeners();
  }
}
