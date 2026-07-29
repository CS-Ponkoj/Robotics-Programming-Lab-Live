abstract interface class ProgressStorage {
  Future<void> initialize();

  String? getString(String key);

  Future<void> setString(String key, String value);
}

class InMemoryProgressStorage implements ProgressStorage {
  InMemoryProgressStorage([Map<String, String>? initialValues])
      : values = {...?initialValues};

  final Map<String, String> values;

  @override
  Future<void> initialize() async {}

  @override
  String? getString(String key) => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}
