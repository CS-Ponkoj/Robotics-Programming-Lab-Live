import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iuse_demo/models/simulation_trace.dart';
import 'package:iuse_demo/widgets/robot_sim_view.dart' show SimPalette;

/// Which picture the replay square shows. Every view follows the same
/// playhead, so scrubbing moves all of them together.
enum SimSensorView { arena, lidar, charts, ranges }

/// The grader's scan has one beam every 3 degrees (91 beams). The replay keeps
/// fewer beams, so displayed beam i is `scan.ranges[sourceIndex(i)]`.
const double _sourceIncrementDeg = 3;

/// Distances above this are drawn as a full bar in the LiDAR and chart views.
const double _shownRange = 3;

int sourceIndex(SimulationReplay replay, int displayed) =>
    (displayed * replay.angleIncrementDeg / _sourceIncrementDeg).round();

double beamAngleDeg(SimulationReplay replay, int displayed) =>
    replay.angleMinDeg + displayed * replay.angleIncrementDeg;

/// Near readings are red, middle ones yellow, far ones green; nothing in
/// range is grey.
Color rangeColor(double? range) => range == null
    ? SimPalette.label
    : range < 0.5
        ? SimPalette.alert
        : range < 1.0
            ? SimPalette.front
            : SimPalette.trail;

String _metres(double? value) =>
    value == null ? 'clear' : '${value.toStringAsFixed(2)} m';

String _degrees(double value) {
  final rounded = value.round();
  return rounded > 0 ? '+$rounded°' : '$rounded°';
}

/// "[39]-[51], -18° to +18°": the scan indices and angles of the drawn beams
/// the node reacts to, or null when there are none.
String? readBeamsText(SimulationReplay replay, Set<int> beams) {
  if (beams.isEmpty) return null;
  final sorted = beams.toList()..sort();
  final step = (replay.angleIncrementDeg / _sourceIncrementDeg).round();
  final half = step ~/ 2;
  final runs = <List<int>>[];
  for (final beam in sorted) {
    if (runs.isNotEmpty && runs.last.last == beam - 1) {
      runs.last.add(beam);
    } else {
      runs.add([beam]);
    }
  }
  final last = sourceIndex(replay, replay.frames.first.ranges.length - 1);
  return runs.map((run) {
    final first = math.max(0, sourceIndex(replay, run.first) - half);
    final end = math.min(last, sourceIndex(replay, run.last) + half);
    final from = _degrees(beamAngleDeg(replay, run.first));
    final to = _degrees(beamAngleDeg(replay, run.last));
    return from == to
        ? '[$first]-[$end] at $from'
        : '[$first]-[$end], $from to $to';
  }).join('; ');
}

/// The nearest reading, and the nearest one to the right, ahead, and left.
class ScanSummary {
  const ScanSummary({
    this.right,
    this.ahead,
    this.left,
    this.closest,
    this.closestAngle,
    this.closestIndex,
  });

  final double? right;
  final double? ahead;
  final double? left;
  final double? closest;
  final double? closestAngle;
  final int? closestIndex;

  /// Right is below -30°, ahead within ±30°, left above +30°.
  factory ScanSummary.of(SimulationReplay replay, SimulationFrame frame) {
    double? right, ahead, left, closest, closestAngle;
    int? closestIndex;
    double? nearer(double? current, double value) =>
        current == null || value < current ? value : current;
    for (var index = 0; index < frame.ranges.length; index++) {
      final value = frame.ranges[index];
      if (value == null) continue;
      final angle = beamAngleDeg(replay, index);
      if (angle < -30) {
        right = nearer(right, value);
      } else if (angle > 30) {
        left = nearer(left, value);
      } else {
        ahead = nearer(ahead, value);
      }
      if (closest == null || value < closest) {
        closest = value;
        closestAngle = angle;
        closestIndex = sourceIndex(replay, index);
      }
    }
    return ScanSummary(
      right: right,
      ahead: ahead,
      left: left,
      closest: closest,
      closestAngle: closestAngle,
      closestIndex: closestIndex,
    );
  }

  String get spoken => closest == null
      ? 'Nothing in range.'
      : 'Closest reading ${_metres(closest)} at ${_degrees(closestAngle!)}. '
          'Right ${_metres(right)}, ahead ${_metres(ahead)}, left ${_metres(left)}.';
}

const _caption = TextStyle(color: SimPalette.label, fontSize: 10);
const _value = TextStyle(
  color: Color(0xFFE2E8F0),
  fontSize: 12,
  fontWeight: FontWeight.w600,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// The scan as one bar per beam, in list order: the robot's right first.
class LidarBarsView extends StatelessWidget {
  const LidarBarsView({
    super.key,
    required this.replay,
    required this.frame,
    this.readBeams = const {},
  });

  final SimulationReplay replay;
  final SimulationFrame frame;

  /// Drawn beams the node reacts to, from the beam probe.
  final Set<int> readBeams;

  @override
  Widget build(BuildContext context) {
    final summary = ScanSummary.of(replay, frame);
    final middle = frame.ranges.length ~/ 2;
    return Padding(
      key: const ValueKey('robot-sim-lidar'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'scan.ranges: ${frame.ranges.length} of '
            '${sourceIndex(replay, frame.ranges.length - 1) + 1} beams',
            style: _caption,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: CustomPaint(
              painter: _LidarBarsPainter(
                  replay: replay, frame: frame, readBeams: readBeams),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Row(
              children: [
                Text('[0] right ${_degrees(replay.angleMinDeg)}',
                    style: _caption),
                const Spacer(),
                Text(
                  '[${sourceIndex(replay, middle)}] ahead',
                  style: _caption.copyWith(color: SimPalette.front),
                ),
                const Spacer(),
                Text(
                  '[${sourceIndex(replay, frame.ranges.length - 1)}] left '
                  '${_degrees(beamAngleDeg(replay, frame.ranges.length - 1))}',
                  style: _caption,
                ),
              ],
            ),
          ),
          if (readBeamsText(replay, readBeams) case final read?) ...[
            const SizedBox(height: 6),
            Text.rich(
              key: const ValueKey('robot-sim-read-beams'),
              TextSpan(children: [
                const TextSpan(text: 'Your node stops for ', style: _caption),
                TextSpan(
                    text: read, style: _value.copyWith(color: SimPalette.read)),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _Reading(
                'Closest',
                summary.closest == null
                    ? 'clear'
                    : '${_metres(summary.closest)} at '
                        '${_degrees(summary.closestAngle!)}',
                color: rangeColor(summary.closest),
              ),
              _Reading('Right', _metres(summary.right),
                  color: rangeColor(summary.right)),
              _Reading('Ahead', _metres(summary.ahead),
                  color: rangeColor(summary.ahead)),
              _Reading('Left', _metres(summary.left),
                  color: rangeColor(summary.left)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading(this.name, this.value, {required this.color});

  final String name;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: [
        TextSpan(text: '$name ', style: _caption),
        TextSpan(text: value, style: _value.copyWith(color: color)),
      ]));
}

class _LidarBarsPainter extends CustomPainter {
  _LidarBarsPainter({
    required this.replay,
    required this.frame,
    this.readBeams = const {},
  });

  final SimulationReplay replay;
  final SimulationFrame frame;
  final Set<int> readBeams;

  @override
  void paint(Canvas canvas, Size size) {
    final ranges = frame.ranges;
    if (ranges.isEmpty || size.isEmpty) return;
    const gutter = 26.0;
    final plot = Rect.fromLTRB(gutter, 4, size.width, size.height);
    double yFor(double metres) =>
        plot.bottom -
        plot.height * (metres.clamp(0, _shownRange) / _shownRange);

    final guide = Paint()
      ..color = SimPalette.grid
      ..strokeWidth = 1;
    for (final metres in const [0.5, 1.0, 2.0, 3.0]) {
      final y = yFor(metres);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), guide);
      _text(
          canvas,
          '${metres == metres.roundToDouble() ? metres.round() : metres} m',
          Offset(0, y - 6));
    }

    final slot = plot.width / ranges.length;
    final middle = ranges.length ~/ 2;
    for (var index = 0; index < ranges.length; index++) {
      final value = ranges[index];
      final left = plot.left + index * slot + slot * 0.15;
      final bar = Rect.fromLTRB(
        left,
        value == null ? plot.top : yFor(value),
        left + slot * 0.7,
        plot.bottom,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(2)),
        Paint()
          ..color =
              rangeColor(value).withValues(alpha: value == null ? 0.18 : 0.9),
      );
      if (index == middle || readBeams.contains(index)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(bar.inflate(2), const Radius.circular(3)),
          Paint()
            ..color =
                readBeams.contains(index) ? SimPalette.read : SimPalette.front
            ..style = PaintingStyle.stroke
            ..strokeWidth = readBeams.contains(index) ? 2 : 1.5,
        );
      }
    }
  }

  void _text(Canvas canvas, String text, Offset at) {
    (TextPainter(
      text: TextSpan(text: text, style: _caption),
      textDirection: TextDirection.ltr,
    )..layout())
        .paint(canvas, at);
  }

  @override
  bool shouldRepaint(_LidarBarsPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.replay != replay ||
      oldDelegate.readBeams.length != readBeams.length;
}

/// Distance ahead and the commanded speeds over the whole run, with the
/// playhead and the stop, wall, and resume moments marked.
class SensorChartsView extends StatelessWidget {
  const SensorChartsView({super.key, required this.replay, required this.time});

  final SimulationReplay replay;
  final double time;

  @override
  Widget build(BuildContext context) => Padding(
        key: const ValueKey('robot-sim-charts'),
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 6),
        child: CustomPaint(
          painter: _ChartsPainter(replay: replay, time: time),
          size: Size.infinite,
        ),
      );
}

class _ChartsPainter extends CustomPainter {
  _ChartsPainter({required this.replay, required this.time});

  final SimulationReplay replay;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    if (replay.frames.isEmpty || size.height < 80) return;
    const gutter = 30.0;
    const axis = 14.0;
    final half = (size.height - axis - 8) / 2;
    final top = Rect.fromLTWH(gutter, 14, size.width - gutter, half - 16);
    final bottom =
        Rect.fromLTWH(gutter, half + 22, size.width - gutter, half - 16);
    final end = math.max(replay.endTime, 0.1);
    double xFor(double t) => top.left + top.width * (t / end).clamp(0, 1);

    // Distance ahead, clipped at the shown range.
    _frame(canvas, top, 'Distance ahead (m)', 0, _shownRange);
    _line(canvas, top, 0, _shownRange, SimPalette.front,
        [for (final f in replay.frames) (f.t, f.front)], xFor);

    // Commanded speeds.
    final speeds = [
      for (final f in replay.frames) ...[f.linear, f.angular]
    ];
    final low = math.min(0.0, speeds.reduce(math.min));
    final high = math.max(0.25, speeds.reduce(math.max)) * 1.15;
    _frame(canvas, bottom, 'linear.x (m/s)   angular.z (rad/s)', low, high);
    if (low < 0) {
      final zero = bottom.bottom - bottom.height * ((0 - low) / (high - low));
      canvas.drawLine(Offset(bottom.left, zero), Offset(bottom.right, zero),
          Paint()..color = SimPalette.label.withValues(alpha: 0.5));
    }
    _line(canvas, bottom, low, high, SimPalette.robot,
        [for (final f in replay.frames) (f.t, f.linear)], xFor);
    _line(canvas, bottom, low, high, SimPalette.ray,
        [for (final f in replay.frames) (f.t, f.angular)], xFor);

    // Event markers across both charts.
    for (final event in replay.events) {
      final color = switch (event.type) {
        'stopped' => SimPalette.alert,
        'collided' => SimPalette.alert,
        'wall_moved' => SimPalette.wall,
        'resumed' => SimPalette.trail,
        _ => null,
      };
      if (color == null) continue;
      final x = xFor(event.t);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      for (var y = top.top; y < bottom.bottom; y += 6) {
        canvas.drawLine(
            Offset(x, y), Offset(x, math.min(y + 3, bottom.bottom)), paint);
      }
    }

    // Time axis and playhead.
    for (var t = 0.0; t <= end + 0.001; t += end > 6 ? 2 : 1) {
      _text(canvas, '${t.round()} s', Offset(xFor(t) - 6, bottom.bottom + 2));
    }
    final x = xFor(time);
    canvas.drawLine(
      Offset(x, top.top - 4),
      Offset(x, bottom.bottom),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5,
    );
  }

  void _frame(Canvas canvas, Rect area, String title, double low, double high) {
    canvas.drawRect(
      area,
      Paint()
        ..color = SimPalette.grid
        ..style = PaintingStyle.stroke,
    );
    _text(canvas, title, Offset(area.left, area.top - 13));
    _text(canvas, _short(high), Offset(0, area.top - 5));
    _text(canvas, _short(low), Offset(0, area.bottom - 7));
  }

  void _line(
    Canvas canvas,
    Rect area,
    double low,
    double high,
    Color color,
    List<(double, double?)> points,
    double Function(double) xFor,
  ) {
    final path = Path();
    var drawing = false;
    for (final (t, value) in points) {
      if (value == null) {
        drawing = false;
        continue;
      }
      final y = area.bottom -
          area.height * ((value.clamp(low, high) - low) / (high - low));
      drawing ? path.lineTo(xFor(t), y) : path.moveTo(xFor(t), y);
      drawing = true;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  static String _short(double value) =>
      value.abs() >= 1 ? value.toStringAsFixed(1) : value.toStringAsFixed(2);

  void _text(Canvas canvas, String text, Offset at) {
    (TextPainter(
      text: TextSpan(text: text, style: _caption),
      textDirection: TextDirection.ltr,
    )..layout())
        .paint(canvas, at);
  }

  @override
  bool shouldRepaint(_ChartsPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.replay != replay;
}

/// Every kept beam as `scan.ranges[i]`, its angle, and its reading.
class RangesTableView extends StatelessWidget {
  const RangesTableView({
    super.key,
    required this.replay,
    required this.frame,
    this.readBeams = const {},
  });

  final SimulationReplay replay;
  final SimulationFrame frame;

  /// Drawn beams the node reacts to; marked in the table.
  final Set<int> readBeams;

  @override
  Widget build(BuildContext context) {
    final middle = frame.ranges.length ~/ 2;
    return Column(
      key: const ValueKey('robot-sim-ranges'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              SizedBox(width: 92, child: Text('Index', style: _caption)),
              SizedBox(width: 56, child: Text('Angle', style: _caption)),
              Expanded(child: Text('Reading', style: _caption)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: frame.ranges.length,
            itemExtent: 24,
            padding: const EdgeInsets.only(bottom: 6),
            itemBuilder: (context, index) {
              final value = frame.ranges[index];
              final highlight = index == middle;
              final read = readBeams.contains(index);
              return Container(
                color:
                    highlight ? SimPalette.front.withValues(alpha: 0.12) : null,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        '${read ? '● ' : ''}ranges[${sourceIndex(replay, index)}]',
                        style: _value.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: read
                              ? SimPalette.read
                              : highlight
                                  ? SimPalette.front
                                  : null,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(_degrees(beamAngleDeg(replay, index)),
                          style: _caption.copyWith(fontSize: 11)),
                    ),
                    SizedBox(
                      width: 62,
                      child: Text(
                          value == null ? 'inf' : value.toStringAsFixed(2),
                          style: _value.copyWith(color: rangeColor(value))),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: value == null
                              ? 1
                              : (value / _shownRange).clamp(0.02, 1),
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: rangeColor(value)
                                  .withValues(alpha: value == null ? 0.2 : 0.8),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
