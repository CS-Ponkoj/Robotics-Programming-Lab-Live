import 'package:shared_preferences/shared_preferences.dart';

import 'progress_storage_base.dart';

class SharedPreferencesProgressStorage implements ProgressStorage {
  SharedPreferences? _preferences;

  @override
  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
  }

  @override
  String? getString(String key) => _preferences?.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _preferences?.setString(key, value);
  }
}

ProgressStorage createPlatformProgressStorage() =>
    SharedPreferencesProgressStorage();
