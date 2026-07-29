import 'package:web/web.dart' as web;

import 'progress_storage_base.dart';

class BrowserProgressStorage implements ProgressStorage {
  @override
  Future<void> initialize() async {}

  @override
  String? getString(String key) => web.window.localStorage.getItem(key);

  @override
  Future<void> setString(String key, String value) async {
    web.window.localStorage.setItem(key, value);
  }
}

ProgressStorage createPlatformProgressStorage() => BrowserProgressStorage();
