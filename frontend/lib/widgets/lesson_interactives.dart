import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Interactive "Try it" tools that a lesson places with
/// `<div class="lesson-interactive" data-interactive="name">`. Each one only
/// evaluates a formula the lesson teaches; none stores or sends anything.
Widget? lessonInteractive(String name) => switch (name) {
      'scan-index' => const ScanIndexExplorer(),
      'twist-path' => const TwistPathViewer(),
      'wheel-speeds' => const WheelSpeedCalculator(),
      _ => null,
    };

/// Angle of reading [index]: angle_min + index * angle_increment (radians).
double scanAngle(double angleMin, double increment, int index) =>
    angleMin + index * increment;

/// The reading nearest to [angle], or null when the direction is outside the
/// sweep. A tiny tolerance at the ends absorbs float32 rounding.
int? scanIndexFor(double angle, double angleMin, double increment, int count) {
  if (increment == 0 || count < 1) return null;
  final fractional = (angle - angleMin) / increment;
  const tolerance = 1e-6;
  if (fractional < -tolerance || fractional > count - 1 + tolerance) return null;
  return fractional.round().clamp(0, count - 1);
}

/// Pose after [seconds] of a constant Twist, from the ideal unicycle model,
/// starting at the origin and facing +x.
({double x, double y, double theta}) unicyclePose(
    double linear, double angular, double seconds) {
  final theta = angular * seconds;
  if (angular.abs() < 1e-9) return (x: linear * seconds, y: 0, theta: 0);
  return (
    x: linear / angular * math.sin(theta),
    y: linear / angular * (1 - math.cos(theta)),
    theta: theta,
  );
}

/// Ground speed of each wheel of an ideal differential-drive robot.
({double right, double left}) wheelSpeeds(
        double linear, double angular, double separation) =>
    (
      right: linear + angular * separation / 2,
      left: linear - angular * separation / 2,
    );

String _fixed(double value, [int digits = 3]) {
  final text = value.toStringAsFixed(digits);
  return text.startsWith('-') && double.parse(text) == 0 ? text.substring(1) : text;
}

String _degrees(double radians) => '${_fixed(radians * 180 / math.pi, 1)}°';

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.title, required this.child, super.key});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(LucideIcons.pointer, color: AppColors.brand),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.fieldKey,
  });
  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 170,
        child: TextField(
          key: fieldKey,
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
              signed: true, decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
          ],
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => onChanged(),
        ),
      );
}

class _Readout extends StatelessWidget {
  const _Readout(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
      );
}

/// Section 4.2: from an index to a direction, and back.
class ScanIndexExplorer extends StatefulWidget {
  const ScanIndexExplorer({super.key});

  @override
  State<ScanIndexExplorer> createState() => _ScanIndexExplorerState();
}

class _ScanIndexExplorerState extends State<ScanIndexExplorer> {
  final _min = TextEditingController(text: '-0.6');
  final _step = TextEditingController(text: '0.2');
  final _count = TextEditingController(text: '7');
  final _direction = TextEditingController(text: '0.33');
  int _index = 3;

  @override
  void dispose() {
    for (final c in [_min, _step, _count, _direction]) {
      c.dispose();
    }
    super.dispose();
  }

  void _labScan() => setState(() {
        // Ten decimals keep reading [45] at 0 rad despite rounding the text.
        _min.text = _fixed(-135 * math.pi / 180, 10);
        _step.text = _fixed(3 * math.pi / 180, 10);
        _count.text = '91';
        _index = 45;
      });

  @override
  Widget build(BuildContext context) {
    final angleMin = double.tryParse(_min.text);
    final step = double.tryParse(_step.text);
    final count = int.tryParse(_count.text);
    final valid = angleMin != null && step != null && step != 0 &&
        count != null && count >= 1 && count <= 2000;
    final index = valid ? _index.clamp(0, count - 1) : 0;
    final direction = double.tryParse(_direction.text);
    String reverse = 'Enter a direction in radians.';
    if (valid && direction != null) {
      final found = scanIndexFor(direction, angleMin, step, count);
      reverse = found == null
          ? 'Fractional index ${_fixed((direction - angleMin) / step, 2)}: '
              'outside the sweep, so this scan has no reading there.'
          : 'Fractional index ${_fixed((direction - angleMin) / step, 2)}: '
              'nearest reading [$found], at '
              '${_fixed(scanAngle(angleMin, step, found))} rad.';
    }
    return _ToolCard(
      key: const Key('try-scan-index'),
      title: 'Try it: index and direction',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          _NumberField(
              label: 'angle_min (rad)',
              controller: _min,
              onChanged: () => setState(() {})),
          _NumberField(
              label: 'angle_increment (rad)',
              controller: _step,
              onChanged: () => setState(() {})),
          _NumberField(
              label: 'number of readings',
              controller: _count,
              onChanged: () => setState(() {})),
        ]),
        TextButton(
            key: const Key('try-scan-lab'),
            onPressed: _labScan,
            child: const Text('Use the lab scan (−135° to +135° in 3° steps)')),
        if (!valid)
          const _Readout('Enter a start angle, a non-zero step and 1 to 2000 readings.')
        else ...[
          Slider(
            key: const Key('try-scan-slider'),
            value: index.toDouble(),
            min: 0,
            max: math.max(1, count - 1).toDouble(),
            divisions: count > 1 ? count - 1 : null,
            label: '[$index]',
            semanticFormatterCallback: (value) => 'reading ${value.round()}',
            onChanged: count > 1
                ? (value) => setState(() => _index = value.round())
                : null,
          ),
          _Readout(
            key: const Key('try-scan-angle'),
            'Reading [$index] points at '
            '${_fixed(scanAngle(angleMin, step, index))} rad '
            '(${_degrees(scanAngle(angleMin, step, index))}).',
          ),
          const SizedBox(height: 12),
          _NumberField(
              fieldKey: const Key('try-scan-direction'),
              label: 'direction (rad)',
              controller: _direction,
              onChanged: () => setState(() {})),
          const SizedBox(height: 8),
          _Readout(reverse, key: const Key('try-scan-reverse')),
        ],
      ]),
    );
  }
}

/// Section 5.3: where a constant Twist takes the robot.
class TwistPathViewer extends StatefulWidget {
  const TwistPathViewer({super.key});

  @override
  State<TwistPathViewer> createState() => _TwistPathViewerState();
}

class _TwistPathViewerState extends State<TwistPathViewer> {
  double _linear = 0.15;
  double _angular = 0.4;
  double _seconds = 3;

  Widget _slider(String label, double value, double min, double max,
          int divisions, String unit, ValueChanged<double> onChanged, Key key) =>
      Row(children: [
        SizedBox(
            width: 150,
            child: Text('$label = ${_fixed(value, 2)} $unit')),
        Expanded(
          child: Slider(
            key: key,
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            semanticFormatterCallback: (v) => '$label ${_fixed(v, 2)} $unit',
            onChanged: onChanged,
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final pose = unicyclePose(_linear, _angular, _seconds);
    final turn = _angular == 0
        ? 'straight'
        : _angular > 0
            ? 'left (counterclockwise)'
            : 'right (clockwise)';
    return _ToolCard(
      key: const Key('try-twist-path'),
      title: 'Try it: where does this Twist go?',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _slider('linear.x', _linear, -0.3, 0.3, 60, 'm/s',
            (v) => setState(() => _linear = v), const Key('try-twist-linear')),
        _slider('angular.z', _angular, -1, 1, 40, 'rad/s',
            (v) => setState(() => _angular = v), const Key('try-twist-angular')),
        _slider('time', _seconds, 0, 5, 50, 's',
            (v) => setState(() => _seconds = v), const Key('try-twist-time')),
        const SizedBox(height: 8),
        Center(
          child: Semantics(
            label: 'Top view of the robot path. The robot starts at the '
                'centre facing right.',
            child: SizedBox(
              width: 280,
              height: 280,
              child: CustomPaint(
                painter: _PathPainter(_linear, _angular, _seconds),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _Readout(
          key: const Key('try-twist-pose'),
          'After ${_fixed(_seconds, 1)} s: x = ${_fixed(pose.x)} m, '
          'y = ${_fixed(pose.y)} m, heading turned ${_fixed(pose.theta)} rad '
          '(${_degrees(pose.theta)}), turning $turn.',
        ),
        Text('Ideal unicycle model: no wheel slip, no acceleration limits.',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

class _PathPainter extends CustomPainter {
  _PathPainter(this.linear, this.angular, this.seconds);
  final double linear, angular, seconds;

  @override
  void paint(Canvas canvas, Size size) {
    const metres = 1.6; // width shown, in metres
    final scale = size.width / metres;
    final centre = Offset(size.width / 2, size.height / 2);
    Offset at(double x, double y) => centre + Offset(x * scale, -y * scale);
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var m = -0.8; m <= 0.8001; m += 0.2) {
      canvas.drawLine(at(m, -0.8), at(m, 0.8), grid);
      canvas.drawLine(at(-0.8, m), at(0.8, m), grid);
    }
    final path = Path()..moveTo(centre.dx, centre.dy);
    for (var i = 1; i <= 100; i++) {
      final p = unicyclePose(linear, angular, seconds * i / 100);
      final o = at(p.x, p.y);
      path.lineTo(o.dx, o.dy);
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.inkMuted
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    void robot(Offset o, double theta, Color color) {
      canvas.drawCircle(o, 9, Paint()..color = color);
      canvas.drawLine(
          o,
          o + Offset(math.cos(theta), -math.sin(theta)) * 16,
          Paint()
            ..color = color
            ..strokeWidth = 3);
    }

    robot(centre, 0, AppColors.inkMuted);
    final end = unicyclePose(linear, angular, seconds);
    robot(at(end.x, end.y), end.theta, AppColors.brand);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PathPainter old) =>
      old.linear != linear || old.angular != angular || old.seconds != seconds;
}

/// Section 5.4: wheel speeds of a differential-drive robot.
class WheelSpeedCalculator extends StatefulWidget {
  const WheelSpeedCalculator({super.key});

  @override
  State<WheelSpeedCalculator> createState() => _WheelSpeedCalculatorState();
}

class _WheelSpeedCalculatorState extends State<WheelSpeedCalculator> {
  final _v = TextEditingController(text: '0.15');
  final _w = TextEditingController(text: '0.4');
  final _l = TextEditingController(text: '0.30');

  @override
  void dispose() {
    for (final c in [_v, _w, _l]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = double.tryParse(_v.text);
    final w = double.tryParse(_w.text);
    final l = double.tryParse(_l.text);
    String result = 'Enter all three values; L must be positive.';
    if (v != null && w != null && l != null && l > 0) {
      final s = wheelSpeeds(v, w, l);
      final motion = w == 0
          ? 'The wheels match, so the robot drives straight.'
          : v == 0
              ? 'The wheels turn in opposite directions, so the robot turns on the spot.'
              : 'The ${w > 0 ? 'right' : 'left'} wheel is faster, so the robot '
                  'curves to the ${w > 0 ? 'left' : 'right'}.';
      result = 'v_right = ${_fixed(s.right)} m/s, v_left = ${_fixed(s.left)} m/s. '
          '$motion';
    }
    return _ToolCard(
      key: const Key('try-wheel-speeds'),
      title: 'Try it: wheel speeds',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          _NumberField(
              fieldKey: const Key('try-wheel-v'),
              label: 'linear.x v (m/s)',
              controller: _v,
              onChanged: () => setState(() {})),
          _NumberField(
              fieldKey: const Key('try-wheel-w'),
              label: 'angular.z ω (rad/s)',
              controller: _w,
              onChanged: () => setState(() {})),
          _NumberField(
              fieldKey: const Key('try-wheel-l'),
              label: 'wheel separation L (m)',
              controller: _l,
              onChanged: () => setState(() {})),
        ]),
        const SizedBox(height: 12),
        _Readout(result, key: const Key('try-wheel-result')),
        Text('v_right = v + ω·L/2 and v_left = v − ω·L/2 (ideal, no slip).',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
