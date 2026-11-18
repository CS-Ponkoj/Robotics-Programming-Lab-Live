import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iuse_demo/models/simulation_trace.dart';
import 'package:iuse_demo/widgets/playground_diagram.dart' show niceDiagramStep;
import 'package:iuse_demo/widgets/robot_sim_sensors.dart';

/// How the replay is arranged in the space it gets.
enum SimViewLayout {
  /// Readings, picture, then controls, top to bottom.
  stacked,

  /// Picture on the left, readings beside it: wide, short spaces.
  sideBySide,

  /// Only the live readings: a collapsed panel.
  strip,
}

/// Top-down replay of the student's node driving the robot. Visual only.
class RobotSimView extends StatefulWidget {
  const RobotSimView({
    super.key,
    required this.replay,
    this.compact = false,
    this.canvasSide,
    this.layout = SimViewLayout.stacked,
    this.focus,
  });

  final SimulationReplay replay;

  /// Jump to one moment and view, from a failed check's "Watch it".
  final SimFocus? focus;

  /// Panel mode: a square picture, controls, and a one-line summary only.
  final bool compact;

  /// Side of the square picture in compact mode; null keeps a 4:3 picture.
  final double? canvasSide;

  final SimViewLayout layout;

  @override
  State<RobotSimView> createState() => _RobotSimViewState();
}

class _RobotSimViewState extends State<RobotSimView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _speed = 1;
  bool _started = false;
  SimSensorView _view = SimSensorView.arena;

  double get _end => math.max(widget.replay.endTime, 0.1);

  /// Drawn beams the node stopped for in the grader's beam probe.
  Set<int> get _readBeams => {...?widget.replay.sensitivity?.beams};
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
    if (_takeFocus()) return;
    // Respect reduced motion: show the final position and let the slider scrub.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  int? _focusToken;

  /// Shows the requested moment, paused, in the requested view. Returns
  /// false when there is no new request.
  bool _takeFocus() {
    final focus = widget.focus;
    if (focus == null || focus.token == _focusToken) return false;
    _focusToken = focus.token;
    final at = widget.replay.firstEventTime(focus.events);
    _controller.stop();
    // Just before the moment, so the student sees what leads to it.
    _controller.value =
        at == null ? 0 : (math.max(0.0, at - 0.4) / _end).clamp(0.0, 1.0);
    _view = switch (focus.view) {
      'lidar' => SimSensorView.lidar,
      'charts' => SimSensorView.charts,
      'ranges' => SimSensorView.ranges,
      'arena' => SimSensorView.arena,
      _ => _view,
    };
    return true;
  }

  @override
  void didUpdateWidget(RobotSimView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replay != widget.replay) {
      _controller
        ..duration = _duration
        ..value = 0;
      if (_takeFocus()) return;
      if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
        _controller.forward();
      } else {
        _controller.value = 1;
      }
    } else if (widget.focus?.token != _focusToken) {
      setState(_takeFocus);
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

    final play = IconButton(
      key: const ValueKey('robot-sim-play'),
      tooltip: playing ? 'Pause replay' : 'Play replay',
      onPressed: _togglePlay,
      icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
    );

    // Collapsed panel: live readings only.
    if (widget.layout == SimViewLayout.strip) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        child: Row(
          key: const ValueKey('robot-sim-strip'),
          children: [
            play,
            const SizedBox(width: 4),
            Expanded(child: _TelemetryCards(frame: frame)),
          ],
        ),
      );
    }

    final controls = Row(
      children: [
        play,
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Text('${_formatSpeed(_speed)}×',
                style: theme.textTheme.labelLarge),
          ),
        ),
      ],
    );
    final summary = Text(replay.summary,
        key: const ValueKey('robot-sim-summary'),
        maxLines: widget.compact ? 3 : null,
        overflow: widget.compact ? TextOverflow.ellipsis : null,
        style:
            theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600));

    // Docked in a wide, short space: picture on the left, readings beside it.
    if (widget.layout == SimViewLayout.sideBySide) {
      final side = widget.canvasSide ?? 300;
      return Semantics(
        container: true,
        explicitChildNodes: true,
        child: Column(
          key: const ValueKey('robot-sim-view'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(dimension: side, child: _visual(replay, frame)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _viewSwitch(),
                      const SizedBox(height: 8),
                      _TelemetryCards(frame: frame),
                      const SizedBox(height: 8),
                      summary,
                    ],
                  ),
                ),
              ],
            ),
            controls,
          ],
        ),
      );
    }

    // Keep the picture, controls, readout, and events as separate nodes so a
    // screen reader does not hear them as one long label.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        key: const ValueKey('robot-sim-view'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TelemetryCards(frame: frame),
          const SizedBox(height: 8),
          _viewSwitch(),
          const SizedBox(height: 8),
          _canvasFrame(child: _visual(replay, frame)),
          const SizedBox(height: 8),
          controls,
          SizedBox(height: widget.compact ? 2 : 8),
          summary,
          if (!widget.compact) ...[
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
        ],
      ),
    );
  }

  /// Arena, LiDAR bars, charts, or the ranges table, on the arena floor.
  Widget _visual(SimulationReplay replay, SimulationFrame frame) {
    final (String label, Widget child) = switch (_view) {
      SimSensorView.arena => (
          'Robot simulation replay. ${replay.summary}',
          CustomPaint(
            key: const ValueKey('robot-sim-canvas'),
            size: Size.infinite,
            painter: RobotSimPainter(
              replay: replay,
              time: _time,
              gridColor: SimPalette.grid,
              wallColor: SimPalette.wall,
              robotColor: SimPalette.robot,
              rayColor: SimPalette.ray,
              frontColor: SimPalette.front,
              trailColor: SimPalette.trail,
              alertColor: SimPalette.alert,
              textColor: SimPalette.label,
              readBeams: _readBeams,
            ),
          ),
        ),
      SimSensorView.lidar => (
          'LiDAR scan at ${frame.t.toStringAsFixed(1)} seconds. '
              '${ScanSummary.of(replay, frame).spoken}',
          LidarBarsView(replay: replay, frame: frame, readBeams: _readBeams),
        ),
      SimSensorView.charts => (
          'Charts of the distance ahead, linear.x, and angular.z over the run.',
          SensorChartsView(replay: replay, time: _time),
        ),
      SimSensorView.ranges => (
          'Table of scan.ranges readings.',
          RangesTableView(replay: replay, frame: frame, readBeams: _readBeams),
        ),
    };
    return Semantics(
      label: label,
      image: _view != SimSensorView.ranges,
      container: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(color: SimPalette.floor, child: child),
      ),
    );
  }

  Widget _viewSwitch() => LayoutBuilder(
        builder: (context, constraints) {
          final icons = constraints.maxWidth >= 420;
          return SegmentedButton<SimSensorView>(
            key: const ValueKey('robot-sim-view-switch'),
            showSelectedIcon: false,
            // Narrow columns: tighter padding and text so labels stay on
            // one line.
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll(EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth < 340 ? 2 : 12)),
              textStyle: WidgetStatePropertyAll(TextStyle(
                  fontSize: constraints.maxWidth < 340 ? 12 : 14,
                  fontWeight: FontWeight.w600)),
            ),
            segments: [
              for (final (view, name, icon) in const [
                (SimSensorView.arena, 'Arena', Icons.map_outlined),
                (SimSensorView.lidar, 'LiDAR', Icons.radar_rounded),
                (SimSensorView.charts, 'Charts', Icons.show_chart_rounded),
                (SimSensorView.ranges, 'Ranges', Icons.table_rows_outlined),
              ])
                ButtonSegment(
                  value: view,
                  label: Text(name, maxLines: 1, softWrap: false),
                  icon: icons ? Icon(icon, size: 16) : null,
                ),
            ],
            selected: {_view},
            onSelectionChanged: (selection) =>
                setState(() => _view = selection.first),
          );
        },
      );

  /// A square of [RobotSimView.canvasSide] in panels, otherwise 4:3.
  Widget _canvasFrame({required Widget child}) {
    final side = widget.canvasSide;
    if (side == null) return AspectRatio(aspectRatio: 4 / 3, child: child);
    return Center(child: SizedBox.square(dimension: side, child: child));
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

/// Sensor and command telemetry at the current replay moment: what the node
/// read from /scan and what it published on /cmd_vel.
class _TelemetryCards extends StatelessWidget {
  const _TelemetryCards({required this.frame});

  final SimulationFrame frame;

  @override
  Widget build(BuildContext context) {
    final front = frame.front;
    final cards = [
      _TelemetryCard(
        topic: '/scan',
        name: 'Ahead',
        value: front == null ? 'clear' : front.toStringAsFixed(2),
        unit: front == null ? '' : 'm',
        accent: SimPalette.front,
        spoken: front == null
            ? 'Ahead: nothing in range'
            : 'Ahead ${front.toStringAsFixed(2)} metres',
      ),
      _TelemetryCard(
        topic: '/cmd_vel',
        name: 'linear.x',
        value: frame.linear.toStringAsFixed(2),
        unit: 'm/s',
        accent: SimPalette.robot,
        spoken: 'linear.x ${frame.linear.toStringAsFixed(2)} m/s',
      ),
      _TelemetryCard(
        topic: '/cmd_vel',
        name: 'angular.z',
        value: frame.angular.toStringAsFixed(2),
        unit: 'rad/s',
        accent: SimPalette.robot,
        spoken: 'angular.z ${frame.angular.toStringAsFixed(2)} rad/s',
      ),
      _TelemetryCard(
        topic: 'replay',
        name: 'Time',
        value: frame.t.toStringAsFixed(1),
        unit: 's',
        accent: SimPalette.trail,
        spoken: 'Time ${frame.t.toStringAsFixed(1)} seconds',
      ),
    ];
    return LayoutBuilder(
      key: const ValueKey('robot-sim-telemetry'),
      builder: (context, constraints) {
        const gap = 6.0;
        // Four in a row when there is room, otherwise two by two.
        final perRow = constraints.maxWidth >= 340 ? 4 : 2;
        final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard({
    required this.topic,
    required this.name,
    required this.value,
    required this.unit,
    required this.accent,
    required this.spoken,
  });

  final String topic;
  final String name;
  final String value;
  final String unit;
  final Color accent;
  final String spoken;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
        decoration: BoxDecoration(
          color: SimPalette.floor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SimPalette.grid),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 44,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                      color: accent,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style:
                        const TextStyle(color: SimPalette.label, fontSize: 11),
                  ),
              ]),
              maxLines: 1,
            ),
          ),
          Text(
            topic,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: SimPalette.label, fontSize: 10),
          ),
        ],
      );
}

/// Fixed colors of the simulated arena, the same in light and dark themes:
/// a dark floor with a bright robot, so the robot and walls stand out.
abstract final class SimPalette {
  static const floor = Color(0xFF0F1B2D);
  static const grid = Color(0xFF22344D);
  static const wall = Color(0xFFC084FC);
  static const robot = Color(0xFFFF7A1A);
  static const ray = Color(0xFF38BDF8);
  static const front = Color(0xFFFACC15);
  static const trail = Color(0xFF4ADE80);
  static const alert = Color(0xFFF87171);
  static const label = Color(0xFF94A3B8);

  /// Beams the student's node reacts to (beam probe).
  static const read = Color(0xFFF472B6);
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
    this.readBeams = const {},
  });

  final SimulationReplay replay;
  final double time;

  /// Beams the node reacts to; drawn in [SimPalette.read].
  final Set<int> readBeams;
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
      final isRead = readBeams.contains(index);
      canvas.drawLine(
        robot,
        end,
        Paint()
          ..color = isRead
              ? SimPalette.read.withValues(alpha: 0.9)
              : isFront
                  ? frontColor
                  : rayColor.withValues(alpha: reading == null ? 0.10 : 0.35)
          ..strokeWidth = isRead ? 2.5 : (isFront ? 2.5 : 1),
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

    // The robot: a triangle whose tip points where it is heading.
    final radius = math.max(replay.robotRadius * scale, 8.0);
    Offset corner(double angle, double length) =>
        robot +
        Offset(math.cos(frame.theta + angle), -math.sin(frame.theta + angle)) *
            length;
    final body = Path()
      ..addPolygon([
        corner(0, radius * 1.5),
        corner(math.pi * 0.78, radius * 1.1),
        corner(-math.pi * 0.78, radius * 1.1),
      ], true);
    canvas.drawPath(body, Paint()..color = robotColor);
    canvas.drawPath(
      body,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
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
      oldDelegate.readBeams.length != readBeams.length ||
      oldDelegate.robotColor != robotColor ||
      oldDelegate.wallColor != wallColor;
}
