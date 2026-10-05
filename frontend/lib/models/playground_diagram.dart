import 'dart:math' as math;

import 'package:iuse_demo/models/playground_result_dto.dart';

/// Inputs beyond this magnitude cannot be drawn legibly.
const double maxDiagramCoordinate = 1e6;

/// Readings beyond this count are not drawn, to keep painting fast.
const int maxDiagramReadings = 720;

class DiagramPointData {
  const DiagramPointData(this.id, this.x, this.y);

  final String id;
  final double x;
  final double y;
}

class DiagramPathData {
  const DiagramPathData({
    required this.points,
    required this.colorIndex,
    required this.dashed,
    this.valueText,
    this.shortText,
  });

  final List<DiagramPointData> points;
  final int colorIndex;
  final bool dashed;

  /// The student's returned value exactly as Python printed it.
  final String? valueText;

  /// A rounded copy for the map label; the legend keeps [valueText].
  final String? shortText;
}

class DiagramReading {
  const DiagramReading(this.angle, this.distance);

  final double angle;
  final double distance;
}

class DiagramRayData {
  const DiagramRayData({
    required this.angle,
    required this.colorIndex,
    required this.style,
    this.halfWidth,
  });

  final double angle;
  final int colorIndex;
  final String style;
  final double? halfWidth;
}

class DiagramArcData {
  const DiagramArcData(this.from, this.to, this.colorIndex);

  final double from;
  final double to;
  final int colorIndex;
}

/// One legend row: an optional line sample plus what the student returned.
class DiagramLegendEntry {
  const DiagramLegendEntry({
    required this.label,
    this.valueText,
    this.note = '',
    this.colorIndex,
    this.style = 'solid',
  });

  final String label;
  final String? valueText;
  final String note;
  final int? colorIndex;
  final String style;
}

/// Everything needed to draw a playground diagram. It is built only from the
/// student's own inputs and returned values; it never computes an answer.
class PlaygroundDiagramData {
  const PlaygroundDiagramData({
    required this.view,
    this.caption = '',
    this.problem,
    this.points = const [],
    this.paths = const [],
    this.readings = const [],
    this.rays = const [],
    this.arcs = const [],
    this.legend = const [],
    this.hints = const [],
    this.description = '',
  });

  final String view;
  final String caption;

  /// Why the inputs cannot be drawn; the diagram is hidden when set.
  final String? problem;
  final List<DiagramPointData> points;
  final List<DiagramPathData> paths;
  final List<DiagramReading> readings;
  final List<DiagramRayData> rays;
  final List<DiagramArcData> arcs;
  final List<DiagramLegendEntry> legend;
  final List<String> hints;
  final String description;
}

class _DiagramInputError implements Exception {
  const _DiagramInputError(this.message);

  final String message;
}

double? _number(Object? value) {
  if (value is bool || value is! num) return null;
  final number = value.toDouble();
  return number.isFinite ? number : null;
}

/// A short, readable number for hints and descriptions.
String formatDiagramNumber(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toStringAsFixed(1);
  }
  var text = value.toStringAsFixed(4);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  return text.endsWith('.') ? '${text}0' : text;
}

/// Angles read best as whole degrees when they are whole.
String formatDiagramAngle(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : formatDiagramNumber(value);

/// Build diagram data from the assignment's simulation configuration and a
/// playground result, or null when the assignment declares no diagram.
PlaygroundDiagramData? buildPlaygroundDiagram(
  Map<String, dynamic>? simulationConfig,
  PlaygroundResultDto result, {
  List<String> parameterNames = const [],
}) {
  final config = simulationConfig?['diagram'];
  if (simulationConfig?['enabled'] == false || config is! Map) return null;
  final diagram = Map<String, dynamic>.from(config);
  final view = diagram['view'];
  if (view != 'route' && view != 'polar') return null;
  final caption = diagram['caption'] is String ? diagram['caption'] as String : '';
  final values = result.success ? result.values : const <PlaygroundValueDto>[];
  final context = _DiagramContext(result.arguments, values, parameterNames);
  try {
    return view == 'route'
        ? _buildRoute(diagram, caption, context)
        : _buildPolar(diagram, caption, context);
  } on _DiagramInputError catch (error) {
    return PlaygroundDiagramData(
      view: view as String,
      caption: caption,
      problem: error.message,
    );
  }
}

class _DiagramContext {
  const _DiagramContext(this.arguments, this.values, this.parameterNames);

  final List<dynamic> arguments;
  final List<PlaygroundValueDto> values;
  final List<String> parameterNames;

  String argumentName(int index) => index < parameterNames.length
      ? parameterNames[index]
      : 'input ${index + 1}';

  Object? argument(int index) {
    if (index < 0 || index >= arguments.length) {
      throw _DiagramInputError(
        'Diagram unavailable: enter a value for ${argumentName(index)}.',
      );
    }
    return arguments[index];
  }

  PlaygroundValueDto? value(Object? index) =>
      index is int && index >= 0 && index < values.length ? values[index] : null;

  String labelFor(Object? index, String fallback) =>
      value(index)?.label ?? fallback;

  double? numberFor(Object? index) => _number(value(index)?.value);
}

List<Map<String, dynamic>> _maps(Object? items) => items is List
    ? items.whereType<Map>().map(Map<String, dynamic>.from).toList()
    : const [];

DiagramPointData _point(String id, Object? value, String name) {
  if (value is List && value.length == 2) {
    final x = _number(value[0]);
    final y = _number(value[1]);
    if (x != null &&
        y != null &&
        x.abs() <= maxDiagramCoordinate &&
        y.abs() <= maxDiagramCoordinate) {
      return DiagramPointData(id, x, y);
    }
  }
  throw _DiagramInputError(
    'Diagram unavailable: $name should be a pair of numbers, like (2, 1).',
  );
}

PlaygroundDiagramData _buildRoute(
  Map<String, dynamic> diagram,
  String caption,
  _DiagramContext context,
) {
  final groups = <String, List<DiagramPointData>>{};
  final allPoints = <DiagramPointData>[];
  for (final spec in _maps(diagram['points'])) {
    final id = spec['id']?.toString() ?? '';
    final arg = spec['arg'];
    if (id.isEmpty || arg is! int) continue;
    final value = context.argument(arg);
    final name = context.argumentName(arg);
    if (spec['each'] == true) {
      if (value is! List) {
        throw _DiagramInputError(
          'Diagram unavailable: $name should be a list of points, '
          'like [(7.5, 4.5), (8.5, 4.5)].',
        );
      }
      final expanded = [
        for (var index = 0; index < value.length; index++)
          _point('$id${index + 1}', value[index], name),
      ];
      groups[id] = expanded;
      allPoints.addAll(expanded);
    } else {
      final point = _point(id, value, name);
      groups[id] = [point];
      allPoints.add(point);
    }
  }

  final paths = <DiagramPathData>[];
  final legend = <DiagramLegendEntry>[];
  final descriptions = <String>[];
  final pathSpecs = _maps(diagram['paths']);
  for (var index = 0; index < pathSpecs.length; index++) {
    final spec = pathSpecs[index];
    final ids = spec['points'] is List ? spec['points'] as List : const [];
    final points = <DiagramPointData>[
      for (final id in ids) ...?groups[id.toString().replaceFirst('*', '')],
    ];
    final value = context.value(spec['value']);
    final dashed = spec['style'] == 'dashed';
    final note = spec['note'] is String ? spec['note'] as String : '';
    final label = context.labelFor(spec['value'], 'Path ${index + 1}');
    legend.add(
      DiagramLegendEntry(
        label: label,
        valueText: value?.text,
        note: note,
        colorIndex: index,
        style: dashed ? 'dashed' : 'solid',
      ),
    );
    if (points.length < 2) continue;
    paths.add(
      DiagramPathData(
        points: points,
        colorIndex: index,
        dashed: dashed,
        valueText: value?.text,
        shortText: _number(value?.value) == null
            ? value?.text
            : formatDiagramNumber(_number(value?.value)!),
      ),
    );
    final route = points.map((point) => point.id).join(' to ');
    descriptions.add(
      value == null ? '$label: $route' : '$label: $route, you returned ${value.text}',
    );
  }
  legend.addAll(_legendValues(diagram, context));

  final placed = allPoints
      .map((point) =>
          '${point.id} at (${formatDiagramNumber(point.x)}, '
          '${formatDiagramNumber(point.y)})')
      .join(', ');
  return PlaygroundDiagramData(
    view: 'route',
    caption: caption,
    points: allPoints,
    paths: paths,
    legend: legend,
    hints: _hints(diagram, context),
    description: 'Route diagram. Points: $placed. ${descriptions.join('. ')}.',
  );
}

List<DiagramReading> _readings(Object? value, String name) {
  final pairs = <List<Object?>>[];
  if (value is Map) {
    for (final entry in value.entries) {
      pairs.add([double.tryParse(entry.key.toString()), entry.value]);
    }
  } else if (value is List) {
    for (final item in value) {
      if (item is! List || item.length != 2) {
        pairs.add(const [null, null]);
      } else {
        pairs.add([_number(item[0]), item[1]]);
      }
    }
  }
  if (value is! Map && value is! List) {
    throw _DiagramInputError(
      'Diagram unavailable: $name should map angles to distances, '
      'like {0: 10, 90: 8}.',
    );
  }
  final readings = <DiagramReading>[];
  for (final pair in pairs) {
    final angle = pair[0] is double ? pair[0] as double : null;
    final distance = _number(pair[1]);
    if (angle == null ||
        !angle.isFinite ||
        distance == null ||
        distance <= 0 ||
        distance > maxDiagramCoordinate) {
      throw _DiagramInputError(
        'Diagram unavailable: every reading in $name needs a numeric angle '
        'and a positive distance.',
      );
    }
    readings.add(DiagramReading(angle % 360, distance));
  }
  if (readings.isEmpty) {
    throw _DiagramInputError(
      'Diagram unavailable: add at least one reading to $name.',
    );
  }
  readings.sort((a, b) => a.angle.compareTo(b.angle));
  return readings.length > maxDiagramReadings
      ? readings.sublist(0, maxDiagramReadings)
      : readings;
}

PlaygroundDiagramData _buildPolar(
  Map<String, dynamic> diagram,
  String caption,
  _DiagramContext context,
) {
  final readingsSpec = diagram['readings'];
  final readingsArg = readingsSpec is Map ? readingsSpec['arg'] : null;
  if (readingsArg is! int) return PlaygroundDiagramData(view: 'polar', caption: caption);
  final readings = _readings(
    context.argument(readingsArg),
    context.argumentName(readingsArg),
  );

  final legend = <DiagramLegendEntry>[];
  final descriptions = <String>[
    'Polar diagram with ${readings.length} supplied '
        '${readings.length == 1 ? 'reading' : 'readings'}',
  ];
  var colorIndex = 0;

  final arcs = <DiagramArcData>[];
  for (final spec in _maps(diagram['arcs'])) {
    final label = spec['label']?.toString() ?? 'Arc';
    final from = spec['from_arg'] is int
        ? _number(context.argument(spec['from_arg'] as int))
        : null;
    final to = spec['to_arg'] is int
        ? _number(context.argument(spec['to_arg'] as int))
        : null;
    final color = colorIndex++;
    if (from == null || to == null) continue;
    arcs.add(DiagramArcData(from, to, color));
    legend.add(
      DiagramLegendEntry(
        label: label,
        note: '${formatDiagramAngle(from)} to ${formatDiagramAngle(to)} degrees',
        colorIndex: color,
      ),
    );
    descriptions.add(
      '$label from ${formatDiagramAngle(from)} to ${formatDiagramAngle(to)} degrees',
    );
  }

  final rays = <DiagramRayData>[];
  for (final spec in _maps(diagram['rays'])) {
    final label = spec['label']?.toString() ?? 'Direction';
    final style = spec['style'] is String ? spec['style'] as String : 'solid';
    final color = colorIndex++;
    final fromStudent = spec['value'] is int;
    final angle = fromStudent
        ? context.numberFor(spec['value'])
        : spec['arg'] is int
            ? _number(context.argument(spec['arg'] as int))
            : null;
    final halfWidth = spec['half_width_arg'] is int
        ? _number(context.argument(spec['half_width_arg'] as int))
        : null;
    final studentText = fromStudent ? context.value(spec['value'])?.text : null;
    if (angle == null) {
      legend.add(
        DiagramLegendEntry(
          label: label,
          valueText: studentText,
          note: fromStudent
              ? (studentText == null ? 'not returned' : 'not a number, so not drawn')
              : 'not a number, so not drawn',
          colorIndex: color,
          style: style,
        ),
      );
      continue;
    }
    final usableHalfWidth =
        halfWidth != null && halfWidth >= 0 && halfWidth <= 180 ? halfWidth : null;
    rays.add(
      DiagramRayData(
        angle: angle % 360,
        colorIndex: color,
        style: style,
        halfWidth: usableHalfWidth,
      ),
    );
    final where = usableHalfWidth == null
        ? '${formatDiagramAngle(angle)} degrees'
        : '${formatDiagramAngle(angle)} degrees, plus or minus '
            '${formatDiagramAngle(usableHalfWidth)}';
    legend.add(
      DiagramLegendEntry(
        label: label,
        valueText: studentText,
        note: fromStudent ? '' : where,
        colorIndex: color,
        style: style,
      ),
    );
    descriptions.add(
      fromStudent ? '$label: you returned $studentText degrees' : '$label at $where',
    );
  }
  legend.addAll(_legendValues(diagram, context));

  return PlaygroundDiagramData(
    view: 'polar',
    caption: caption,
    readings: readings,
    rays: rays,
    arcs: arcs,
    legend: legend,
    hints: _hints(diagram, context),
    description: '${descriptions.join('. ')}.',
  );
}

List<DiagramLegendEntry> _legendValues(
  Map<String, dynamic> diagram,
  _DiagramContext context,
) {
  final indices = diagram['legend_values'] is List
      ? (diagram['legend_values'] as List).whereType<int>()
      : const <int>[];
  return [
    for (final index in indices)
      if (context.value(index) != null)
        DiagramLegendEntry(
          label: context.value(index)!.label,
          valueText: context.value(index)!.text,
        ),
  ];
}

bool _sameNumber(double a, double b) =>
    (a - b).abs() <= 1e-6 * math.max(1, math.max(a.abs(), b.abs()));

/// Consistency hints that compare the student's returned values with each
/// other. They never use expected answers.
List<String> _hints(Map<String, dynamic> diagram, _DiagramContext context) {
  final hints = <String>[];
  for (final check in _maps(diagram['checks'])) {
    if (check['type'] == 'sum') {
      final parts = check['parts'] is List
          ? (check['parts'] as List).whereType<int>().toList()
          : const <int>[];
      final total = context.numberFor(check['total']);
      final numbers = parts.map(context.numberFor).toList();
      if (parts.length < 2 || total == null || numbers.contains(null)) continue;
      final sum = numbers.fold<double>(0, (value, item) => value + item!);
      if (!_sameNumber(sum, total)) {
        final names = parts
            .map((index) => context.labelFor(index, 'part').toLowerCase())
            .join(' + ');
        hints.add(
          'Your ${context.labelFor(check['total'], 'total').toLowerCase()} '
          '(${context.value(check['total'])!.text}) is not $names '
          '(${formatDiagramNumber(sum)}).',
        );
      }
    } else if (check['type'] == 'min_label') {
      final candidates = check['candidates'] is List
          ? (check['candidates'] as List).whereType<int>().toList()
          : const <int>[];
      final labels = check['labels'] is List
          ? (check['labels'] as List).map((item) => item.toString()).toList()
          : const <String>[];
      final numbers = candidates.map(context.numberFor).toList();
      if (candidates.length < 2 ||
          labels.length != candidates.length ||
          numbers.contains(null)) {
        continue;
      }
      final smallest = numbers.map((item) => item!).reduce(math.min);
      final tied = [
        for (var index = 0; index < numbers.length; index++)
          if (_sameNumber(numbers[index]!, smallest)) index,
      ];
      final tieIndex = check['tie_index'];
      final int? expected = tied.length == 1
          ? tied.single
          : tieIndex is int && tied.contains(tieIndex)
              ? tieIndex
              : null;
      if (expected == null) continue;
      final returnedLabel = context.value(check['label'])?.value;
      if (returnedLabel is String && returnedLabel != labels[expected]) {
        hints.add(
          tied.length > 1
              ? 'Your times are equal, so the tie-break rule picks '
                  '"${labels[expected]}", but your label says "$returnedLabel".'
              : 'Your label says "$returnedLabel", but your smaller complete '
                  'time belongs to "${labels[expected]}".',
        );
      }
      final best = context.numberFor(check['best']);
      if (best != null && !_sameNumber(best, smallest)) {
        hints.add(
          'Your ${context.labelFor(check['best'], 'best time').toLowerCase()} '
          '(${context.value(check['best'])!.text}) does not match your smaller '
          'complete time (${formatDiagramNumber(smallest)}).',
        );
      }
    }
  }
  return hints;
}
