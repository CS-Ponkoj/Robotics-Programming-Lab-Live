import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iuse_demo/widgets/robot_sim_view.dart' show SimPalette;

/// The server's limits for a `ros2_2d` world (backend data_contracts.py).
const double _coordinateLimit = 20;
const double _maxDuration = 8;
const int _maxWalls = 20;

/// Problems that would make the server reject [world], in plain words.
List<String> simWorldProblems(Map<String, dynamic> world) {
  final problems = <String>[];
  bool coordinate(Object? value) =>
      value is num && value.isFinite && value.abs() <= _coordinateLimit;
  final walls = world['walls'];
  if (walls is! List || walls.isEmpty) {
    problems.add('Add at least one wall.');
  } else {
    if (walls.length > _maxWalls) problems.add('Use at most $_maxWalls walls.');
    for (final (index, wall) in walls.indexed) {
      if (wall is! List || wall.length != 4 || !wall.every(coordinate)) {
        problems.add('Wall ${index + 1} needs four numbers from -20 to 20 m.');
      }
    }
  }
  final robot = world['robot'];
  if (robot is Map) {
    if (!coordinate(robot['x']) || !coordinate(robot['y'])) {
      problems.add('Robot x and y must be from -20 to 20 m.');
    }
    final theta = robot['theta'];
    if (theta is! num || theta.abs() > 3.1416) {
      problems.add('Robot heading must be from -3.1416 to 3.1416 rad.');
    }
  }
  final duration = world['duration_seconds'];
  if (duration is! num || duration <= 0 || duration > _maxDuration) {
    problems.add('Duration must be more than 0 and at most $_maxDuration s.');
  }
  final move = world['wall_move'];
  if (move is Map) {
    final wall = move['wall'];
    if (wall is! int || wall < 0 || walls is! List || wall >= walls.length) {
      problems.add('The moving wall must be one of the walls above.');
    }
    final after = move['after_stopped_seconds'];
    if (after is! num || after <= 0 || after > 5) {
      problems.add(
          'The wall moves after the robot stops for more than 0 and at most 5 s.');
    }
    if (!coordinate(move['dx']) || !coordinate(move['dy'])) {
      problems.add('The wall move must be from -20 to 20 m.');
    }
  }
  return problems;
}

/// Opens the editor; returns the edited world, or null when cancelled.
Future<Map<String, dynamic>?> editSimWorld(
  BuildContext context,
  Map<String, dynamic> world,
) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
          child: SimWorldEditor(world: world),
        ),
      ),
    );

/// Walls, robot start, duration, and the optional wall move, with a live
/// top-down preview. Nothing is saved until the instructor saves the draft.
class SimWorldEditor extends StatefulWidget {
  const SimWorldEditor({super.key, required this.world});

  final Map<String, dynamic> world;

  @override
  State<SimWorldEditor> createState() => _SimWorldEditorState();
}

class _SimWorldEditorState extends State<SimWorldEditor> {
  late final List<List<TextEditingController>> _walls;
  late final List<TextEditingController> _robot; // x, y, theta
  late final TextEditingController _duration;
  late bool _moves;
  late final List<TextEditingController> _move; // wall, after, dx, dy

  static TextEditingController _number(Object? value, [num fallback = 0]) =>
      TextEditingController(text: '${value is num ? value : fallback}');

  @override
  void initState() {
    super.initState();
    final walls = widget.world['walls'];
    _walls = [
      if (walls is List)
        for (final wall in walls)
          if (wall is List && wall.length == 4)
            [for (final v in wall) _number(v)],
    ];
    final robot =
        widget.world['robot'] is Map ? widget.world['robot'] as Map : const {};
    _robot = [
      _number(robot['x']),
      _number(robot['y']),
      _number(robot['theta'])
    ];
    _duration = _number(widget.world['duration_seconds'], 7);
    final move = widget.world['wall_move'];
    _moves = move is Map;
    final values = move is Map ? move : const {};
    _move = [
      _number(values['wall']),
      _number(values['after_stopped_seconds'], 1),
      _number(values['dx']),
      _number(values['dy']),
    ];
  }

  @override
  void dispose() {
    for (final controller in [
      ..._walls.expand((row) => row),
      ..._robot,
      _duration,
      ..._move
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  static num? _read(TextEditingController controller) =>
      num.tryParse(controller.text.trim());

  /// The world as the fields describe it now; unreadable numbers stay null so
  /// the problem list names them.
  Map<String, dynamic> get _current {
    final robot = Map<String, dynamic>.from(
        widget.world['robot'] is Map ? widget.world['robot'] as Map : const {});
    robot['x'] = _read(_robot[0]);
    robot['y'] = _read(_robot[1]);
    robot['theta'] = _read(_robot[2]);
    return {
      ...widget.world,
      'walls': [
        for (final row in _walls) [for (final v in row) _read(v)]
      ],
      'robot': robot,
      'duration_seconds': _read(_duration),
      if (_moves)
        'wall_move': {
          'wall': _read(_move[0])?.toInt(),
          'after_stopped_seconds': _read(_move[1]),
          'dx': _read(_move[2]),
          'dy': _read(_move[3]),
        },
    }..removeWhere((key, _) => key == 'wall_move' && !_moves);
  }

  Widget _field(TextEditingController controller, String label,
          {double width = 92}) =>
      SizedBox(
        width: width,
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          decoration: InputDecoration(labelText: label, isDense: true),
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final world = _current;
    final problems = simWorldProblems(world);
    final form = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Simulation world', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
            'Metres, top-down; the robot drives along its heading (0 rad points right).',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        Text('Walls (x1, y1) to (x2, y2)', style: theme.textTheme.titleSmall),
        for (final (index, row) in _walls.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${index + 1}'),
                _field(row[0], 'x1'),
                _field(row[1], 'y1'),
                _field(row[2], 'x2'),
                _field(row[3], 'y2'),
                IconButton(
                  tooltip: 'Remove wall ${index + 1}',
                  onPressed: () => setState(() => _walls.removeAt(index)),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('sim-world-add-wall'),
            onPressed: _walls.length >= _maxWalls
                ? null
                : () => setState(() => _walls.add([
                      for (final v in [1.0, -1.0, 1.0, 1.0]) _number(v)
                    ])),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add wall'),
          ),
        ),
        const SizedBox(height: 8),
        Text('Robot start', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _field(_robot[0], 'x'),
          _field(_robot[1], 'y'),
          _field(_robot[2], 'heading (rad)', width: 120),
          _field(_duration, 'duration (s)', width: 120),
        ]),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('sim-world-moves'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Move a wall after the robot stops'),
          value: _moves,
          onChanged: (value) => setState(() => _moves = value),
        ),
        if (_moves)
          Wrap(spacing: 8, runSpacing: 8, children: [
            _field(_move[0], 'wall index'),
            _field(_move[1], 'after stop (s)', width: 120),
            _field(_move[2], 'dx'),
            _field(_move[3], 'dy'),
          ]),
        const SizedBox(height: 12),
        for (final problem in problems)
          Text('• $problem',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
      ],
    );
    final preview = Padding(
      padding: const EdgeInsets.all(20),
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: SimPalette.floor,
            child: CustomPaint(
              key: const Key('sim-world-preview'),
              painter: SimWorldPreviewPainter(world),
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 760
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: form),
                      SizedBox(width: 380, child: preview),
                    ],
                  )
                : ListView(children: [
                    SizedBox(height: 360, child: preview),
                    SizedBox(height: 520, child: form),
                  ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('sim-world-apply'),
                onPressed: problems.isEmpty
                    ? () => Navigator.pop(context, world)
                    : null,
                child: const Text('Use this world'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Walls, the robot's start and heading, and where a moving wall ends up.
class SimWorldPreviewPainter extends CustomPainter {
  SimWorldPreviewPainter(this.world);

  final Map<String, dynamic> world;

  static List<double>? _wall(Object? value) =>
      value is List && value.length == 4 && value.every((v) => v is num)
          ? [for (final v in value) (v as num).toDouble()]
          : null;

  @override
  void paint(Canvas canvas, Size size) {
    final walls = [
      for (final item in (world['walls'] as List? ?? const []))
        if (_wall(item) case final wall?) wall,
    ];
    final robot = world['robot'] is Map ? world['robot'] as Map : const {};
    final rx = (robot['x'] as num?)?.toDouble() ?? 0;
    final ry = (robot['y'] as num?)?.toDouble() ?? 0;
    final theta = (robot['theta'] as num?)?.toDouble() ?? 0;
    final move = world['wall_move'] is Map ? world['wall_move'] as Map : null;
    List<double>? moved;
    if (move != null &&
        move['wall'] is int &&
        (move['wall'] as int) < walls.length) {
      final wall = walls[move['wall'] as int];
      final dx = (move['dx'] as num?)?.toDouble() ?? 0;
      final dy = (move['dy'] as num?)?.toDouble() ?? 0;
      moved = [wall[0] + dx, wall[1] + dy, wall[2] + dx, wall[3] + dy];
    }
    final shown = [...walls, if (moved != null) moved];
    final xs = [
      rx,
      for (final w in shown) ...[w[0], w[2]]
    ];
    final ys = [
      ry,
      for (final w in shown) ...[w[1], w[3]]
    ];
    final minX = xs.reduce(math.min) - 0.5, maxX = xs.reduce(math.max) + 0.5;
    final minY = ys.reduce(math.min) - 0.5, maxY = ys.reduce(math.max) + 0.5;
    final span = math.max(maxX - minX, maxY - minY);
    final scale = size.shortestSide / span;
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    Offset at(double x, double y) => Offset(
        size.width / 2 + (x - cx) * scale, size.height / 2 - (y - cy) * scale);

    final grid = Paint()..color = SimPalette.grid;
    for (var x = minX.floorToDouble(); x <= maxX; x += 1) {
      canvas.drawLine(at(x, minY - span), at(x, maxY + span), grid);
    }
    for (var y = minY.floorToDouble(); y <= maxY; y += 1) {
      canvas.drawLine(at(minX - span, y), at(maxX + span, y), grid);
    }
    final wallPaint = Paint()
      ..color = SimPalette.wall
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final wall in walls) {
      canvas.drawLine(at(wall[0], wall[1]), at(wall[2], wall[3]), wallPaint);
    }
    if (moved != null) {
      canvas.drawLine(
        at(moved[0], moved[1]),
        at(moved[2], moved[3]),
        Paint()
          ..color = SimPalette.wall.withValues(alpha: 0.35)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
    final radius = math.max(0.15 * scale, 8.0);
    final centre = at(rx, ry);
    Offset corner(double angle, double length) =>
        centre +
        Offset(math.cos(theta + angle), -math.sin(theta + angle)) * length;
    canvas.drawPath(
      Path()
        ..addPolygon([
          corner(0, radius * 1.5),
          corner(math.pi * 0.78, radius * 1.1),
          corner(-math.pi * 0.78, radius * 1.1),
        ], true),
      Paint()..color = SimPalette.robot,
    );
  }

  @override
  bool shouldRepaint(SimWorldPreviewPainter oldDelegate) =>
      oldDelegate.world != world;
}
