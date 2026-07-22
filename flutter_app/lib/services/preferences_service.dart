import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const _keyAutoStartRuntime = 'auto_start_gateway';
  static const _keySetupComplete = 'setup_complete';
  static const _keyFirstRun = 'first_run';
  static const _keyPendingSetupCompletionChoice =
      'pending_setup_completion_choice';
  static const _keyLocaleCode = 'locale_code';
  static const _keyBonjourEnabled = 'bonjour_enabled';
  static const _keyLastAppVersion = 'last_app_version';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  bool get autoStartRuntime => _prefs.getBool(_keyAutoStartRuntime) ?? false;
  set autoStartRuntime(bool value) =>
      _prefs.setBool(_keyAutoStartRuntime, value);

  bool get setupComplete => _prefs.getBool(_keySetupComplete) ?? false;
  set setupComplete(bool value) => _prefs.setBool(_keySetupComplete, value);

  bool get isFirstRun => _prefs.getBool(_keyFirstRun) ?? true;
  set isFirstRun(bool value) => _prefs.setBool(_keyFirstRun, value);

  bool get pendingSetupCompletionChoice =>
      _prefs.getBool(_keyPendingSetupCompletionChoice) ?? false;
  set pendingSetupCompletionChoice(bool value) =>
      _prefs.setBool(_keyPendingSetupCompletionChoice, value);

  String? get localeCode => _prefs.getString(_keyLocaleCode);
  set localeCode(String? value) {
    if (value != null && value.isNotEmpty) {
      _prefs.setString(_keyLocaleCode, value);
    } else {
      _prefs.remove(_keyLocaleCode);
    }
  }

  bool get bonjourEnabled => _prefs.getBool(_keyBonjourEnabled) ?? false;
  set bonjourEnabled(bool value) => _prefs.setBool(_keyBonjourEnabled, value);

  String? get lastAppVersion => _prefs.getString(_keyLastAppVersion);
  set lastAppVersion(String? value) {
    if (value != null) {
      _prefs.setString(_keyLastAppVersion, value);
    } else {
      _prefs.remove(_keyLastAppVersion);
    }
  }

}
