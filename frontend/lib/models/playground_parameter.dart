/// One function input described by the assignment's playground settings.
class PlaygroundParameterSpec {
  const PlaygroundParameterSpec({
    required this.name,
    required this.kind,
    required this.label,
    required this.example,
    this.meaning = '',
    this.unit = '',
    this.group = '',
  });

  final String name;
  final String kind;
  final String label;
  final String example;
  final String meaning;
  final String unit;
  final String group;

  static PlaygroundParameterSpec? fromJson(Object? json) {
    if (json is! Map) return null;
    String text(String key) => json[key] is String ? json[key] as String : '';
    final name = text('name');
    final example = text('example');
    if (name.isEmpty || example.isEmpty) return null;
    return PlaygroundParameterSpec(
      name: name,
      kind: text('kind'),
      label: text('label').isEmpty ? name : text('label'),
      example: example,
      meaning: text('meaning'),
      unit: text('unit'),
      group: text('group'),
    );
  }

  /// The helper line under the field, for example
  /// "point (x, y) in m · Where the robot begins".
  String get helper {
    final kindText = parameterKindLabel(kind);
    final shape = unit.isEmpty ? kindText : '$kindText in $unit';
    return meaning.isEmpty ? shape : '$shape · $meaning';
  }
}

String parameterKindLabel(String kind) => switch (kind) {
  'point' => 'point (x, y)',
  'number' => 'number',
  'integer' => 'whole number',
  'list_of_points' => 'list of points [(x, y), ...]',
  'angle_map' => 'angle-to-distance map {angle: distance}',
  'text' => 'text in quotes',
  _ => 'value',
};

Map<String, dynamic> _playground(Map<String, dynamic>? simulationConfig) {
  final playground = simulationConfig?['playground'];
  return playground is Map ? Map<String, dynamic>.from(playground) : const {};
}

/// The described inputs, or an empty list when the assignment has none.
List<PlaygroundParameterSpec> playgroundParameters(
  Map<String, dynamic>? simulationConfig,
) {
  final items = _playground(simulationConfig)['parameters'];
  if (items is! List) return const [];
  return items
      .map(PlaygroundParameterSpec.fromJson)
      .whereType<PlaygroundParameterSpec>()
      .toList();
}

/// Example inputs as one line: built from the parameter examples, or a v6.3
/// stored sample when an older configuration has no parameters.
String playgroundSampleArguments(Map<String, dynamic>? simulationConfig) {
  final parameters = playgroundParameters(simulationConfig);
  if (parameters.isNotEmpty) {
    return joinPlaygroundArguments(parameters.map((item) => item.example));
  }
  final legacy = _playground(simulationConfig)['sample_arguments'];
  return legacy is String ? legacy : '';
}

/// Instructors can turn consistency hints off; they are on by default.
bool playgroundHintsEnabled(Map<String, dynamic>? simulationConfig) =>
    _playground(simulationConfig)['hints_enabled'] != false;

String joinPlaygroundArguments(Iterable<String> values) =>
    values.map((value) => value.trim()).join(', ');

/// Split one line of inputs at top-level commas, keeping commas inside
/// brackets and quotes. Returns null when brackets or quotes are unbalanced.
List<String>? splitPlaygroundArguments(String text) {
  final parts = <String>[];
  final current = StringBuffer();
  var depth = 0;
  String? quote;
  var escaped = false;
  for (final char in text.split('')) {
    if (quote != null) {
      current.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
    } else if ('([{'.contains(char)) {
      depth += 1;
    } else if (')]}'.contains(char)) {
      depth -= 1;
      if (depth < 0) return null;
    } else if (char == ',' && depth == 0) {
      parts.add(current.toString().trim());
      current.clear();
      continue;
    }
    current.write(char);
  }
  if (quote != null || depth != 0) return null;
  final last = current.toString().trim();
  // A trailing comma (Python allows one) does not add an empty input.
  if (last.isNotEmpty || parts.isEmpty) parts.add(last);
  return parts.length == 1 && parts.single.isEmpty ? <String>[] : parts;
}
