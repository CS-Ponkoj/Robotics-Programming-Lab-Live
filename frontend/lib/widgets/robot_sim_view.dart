import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iuse_demo/models/simulation_trace.dart';
import 'package:iuse_demo/widgets/playground_diagram.dart' show niceDiagramStep;

/// Top-down replay of the student's node driving the robot. Visual only.
class RobotSimView extends StatefulWidget {
  const RobotSimView({super.key, required this.replay});

  final SimulationReplay replay;

  @override
  State<RobotSimView> createState() => _RobotSimViewState();
}

class _RobotSimViewState extends State<RobotSimView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _speed = 1;
  bool _started = false;

  double get _end => math.max(widget.replay.endTime, 0.1);
  double get _time => _controller.value * _end;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addListener(() => setState(() {}))
      ..addStatusListener((_) => setState(() {}));
  }

  Duration get _duration =>
      Duration(milliseconds: (_end * 1000 / _speed).round());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Respect reduced motion: show the final position and let the slider scrub.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(RobotSimView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replay != widget.replay) {
      _controller
        ..duration = _duration
        ..value = 0;
      if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
        _controller.forward();
      } else {
        _controller.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    // stop() keeps the status unchanged, so rebuild for the play/pause icon.
    setState(() {
      if (_controller.isAnimating) {
        _controller.stop();
      } else {
        if (_controller.value >= 1) _controller.value = 0;
        _controller.forward();
      }
    });
  }

  void _restart() {
    _controller.value = 0;
    _controller.forward();
  }

  void _setSpeed(double speed) {
    final playing = _controller.isAnimating;
    setState(() => _speed = speed);
    _controller.duration = _duration;
    if (playing) _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final replay = widget.replay;
    final frame = replay.frameAt(_time);
    final playing = _controller.isAnimating;
    String metres(double? value) =>
        value == null ? 'nothing in range' : '${value.toStringAsFixed(2)} m';

    // Keep the picture, controls, readout, and events as separate nodes so a
    // screen reader does not hear them as one long label.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        key: const ValueKey('robot-sim-view'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: 'Robot simulation replay. ${replay.summary}',
            image: true,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerLowest,
                  child: CustomPaint(
                    key: const ValueKey('robot-sim-canvas'),
                    painter: RobotSimPainter(
                      replay: replay,
                      time: _time,
                      gridColor: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                      wallColor: theme.colorScheme.onSurfaceVariant,
                      robotColor: theme.colorScheme.primary,
                      rayColor:
                          theme.colorScheme.primary.withValues(alpha: 0.25),
                      frontColor: theme.colorScheme.primary,
                      trailColor: theme.colorScheme.tertiary,
                      alertColor: theme.colorScheme.error,
                      textColor: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                key: const ValueKey('robot-sim-play'),
                tooltip: playing ? 'Pause replay' : 'Play replay',
                onPressed: _togglePlay,
                icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
              IconButton(
                key: const ValueKey('robot-sim-restart'),
                tooltip: 'Replay from the start',
                onPressed: _restart,
                icon: const Icon(Icons.replay_rounded),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('robot-sim-scrub'),
                  value: _controller.value.clamp(0, 1),
                  label: '${_time.toStringAsFixed(1)} s',
                  semanticFormatterCallback: (_) =>
                      '${_time.toStringAsFixed(1)} seconds',
                  onChanged: (value) {
                    _controller.stop();
                    _controller.value = value;
                  },
                ),
              ),
              PopupMenuButton<double>(
                key: const ValueKey('robot-sim-speed'),
                tooltip: 'Replay speed',
                initialValue: _speed,
                onSelected: _setSpeed,
                itemBuilder: (_) => [
                  for (final speed in const [0.5, 1.0, 2.0])
                    PopupMenuItem(
                        value: speed, child: Text('${_formatSpeed(speed)}×')),
                ],
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Text('${_formatSpeed(_speed)}×',
                      style: theme.textTheme.labelLarge),
                ),
              ),
            ],
          ),
          Wrap(
            key: const ValueKey('robot-sim-readout'),
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('t ${frame.t.toStringAsFixed(1)} s'),
              Text('linear.x ${frame.linear.toStringAsFixed(2)} m/s'),
              Text('angular.z ${frame.angular.toStringAsFixed(2)} rad/s'),
              Text('ahead ${metres(frame.front)}'),
            ]
                .map((child) => DefaultTextStyle.merge(
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                      child: child,
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          Text(replay.summary,
              key: const ValueKey('robot-sim-summary'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final event in replay.events)
            if (_eventText(event) case final text?)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${event.t.toStringAsFixed(1)} s  $text',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: event.t <= _time
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    )),
              ),
          const SizedBox(height: 8),
          Text(
            'This replay only shows what your node did. It does not change your score.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  static String _formatSpeed(double speed) => speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();

  static String? _eventText(SimulationEvent event) => switch (event.type) {
        'started' => 'Started driving',
        'stopped' => event.front == null
            ? 'Stopped'
            : 'Stopped ${event.front!.toStringAsFixed(2)} m from the wall',
        'wall_moved' => 'The wall slid away',
        'resumed' => 'Drove again',
        'collided' => 'Hit the wall',
        'finished' => 'Replay ended',
        _ => null,
      };
}

/// Draws the world, scan rays, trail, and robot at one moment of the replay.
class RobotSimPainter extends CustomPainter {
  RobotSimPainter({
    required this.replay,
    required this.time,
    required this.gridColor,
    required this.wallColor,
    required this.robotColor,
    required this.rayColor,
    required this.frontColor,
    required this.trailColor,
    required this.alertColor,
    required this.textColor,
  });

  final SimulationReplay replay;
  final double time;
  final Color gridColor;
  final Color wallColor;
  final Color robotColor;
  final Color rayColor;
  final Color frontColor;
  final Color trailColor;
  final Color alertColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || replay.frames.isEmpty) return;
    canvas.clipRect(Offset.zero & size);

    // A square window around the robot's path and the walls in front of it.
    final xs = [
      for (final frame in replay.frames) frame.x,
      for (final wall in replay.walls) ...[wall[0], wall[2]],
      for (final event in replay.events)
        if (event.walls != null)
          for (final wall in event.walls!) ...[wall[0], wall[2]],
    ];
    final ys = [for (final frame in replay.frames) frame.y];
    final minX = xs.reduce(math.min) - 0.6;
    final maxX = xs.reduce(math.max) + 0.4;
    final spanX = maxX - minX;
    final spanY = spanX * size.height / size.width;
    final centerY = (ys.reduce(math.min) + ys.reduce(math.max)) / 2;
    final minY = centerY - spanY / 2;
    final maxY = centerY + spanY / 2;
    final scale = size.width / spanX;
    Offset toScreen(double x, double y) =>
        Offset((x - minX) * scale, (maxY - y) * scale);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final step = niceDiagramStep(spanX / 5);
    for (var x = (minX / step).ceil() * step; x <= maxX; x += step) {
      canvas.drawLine(toScreen(x, maxY), toScreen(x, minY), gridPaint);
      _label(canvas, '${_trim(x)} m', toScreen(x, minY) + const Offset(3, -14));
    }
    for (var y = (minY / step).ceil() * step; y <= maxY; y += step) {
      canvas.drawLine(toScreen(minX, y), toScreen(maxX, y), gridPaint);
    }

    final frame = replay.frameAt(time);
    final robot = toScreen(frame.x, frame.y);

    // Scan rays from the robot; null readings fade out at the window edge.
    final rangeLimit = spanX * 1.5;
    final middle = frame.ranges.length ~/ 2;
    for (var index = 0; index < frame.ranges.length; index++) {
      final reading = frame.ranges[index];
      final angle = frame.theta +
          (replay.angleMinDeg + index * replay.angleIncrementDeg) *
              math.pi /
              180;
      final length = reading ?? rangeLimit;
      final end = toScreen(frame.x + length * math.cos(angle),
          frame.y + length * math.sin(angle));
      final isFront = index == middle;
      canvas.drawLine(
        robot,
        end,
        Paint()
          ..color = isFront
              ? frontColor
              : rayColor.withValues(alpha: reading == null ? 0.08 : 0.25)
          ..strokeWidth = isFront ? 2.5 : 1,
      );
      if (reading != null) {
        canvas.drawCircle(end, isFront ? 3.5 : 2,
            Paint()..color = isFront ? frontColor : rayColor);
      }
    }

    final wallPaint = Paint()
      ..color = wallColor
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (final wall in replay.wallsAt(time)) {
      canvas.drawLine(
          toScreen(wall[0], wall[1]), toScreen(wall[2], wall[3]), wallPaint);
    }

    // The path driven so far.
    final trail = Path();
    var first = true;
    for (final item in replay.frames) {
      if (item.t > time) break;
      final at = toScreen(item.x, item.y);
      first ? trail.moveTo(at.dx, at.dy) : trail.lineTo(at.dx, at.dy);
      first = false;
    }
    canvas.drawPath(
      trail,
      Paint()
        ..color = trailColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (final event in replay.events) {
      if (event.t > time ||
          (event.type != 'stopped' && event.type != 'collided')) {
        continue;
      }
      final at = replay.frameAt(event.t);
      final point = toScreen(at.x, at.y);
      if (event.type == 'collided') {
        final paint = Paint()
          ..color = alertColor
          ..strokeWidth = 3;
        canvas.drawLine(
            point - const Offset(7, 7), point + const Offset(7, 7), paint);
        canvas.drawLine(
            point - const Offset(7, -7), point + const Offset(7, -7), paint);
      } else {
        canvas.drawRect(Rect.fromCenter(center: point, width: 8, height: 8),
            Paint()..color = alertColor);
      }
    }

    // The robot: a disc with a heading line.
    final radius = math.max(replay.robotRadius * scale, 6.0);
    canvas.drawCircle(robot, radius, Paint()..color = robotColor);
    final nose =
        robot + Offset(math.cos(frame.theta), -math.sin(frame.theta)) * radius;
    canvas.drawLine(
      robot,
      nose,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  void _label(Canvas canvas, String text, Offset at) {
    final painter = TextPainter(
      text: TextSpan(
          text: text, style: TextStyle(color: textColor, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  static String _trim(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  @override
  bool shouldRepaint(RobotSimPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.replay != replay ||
      oldDelegate.robotColor != robotColor ||
      oldDelegate.wallColor != wallColor;
}
