import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:iuse_demo/models/playground_diagram.dart';
import 'package:iuse_demo/theme/app_theme.dart';

/// Okabe-Ito colours: distinguishable with common colour-vision deficiencies.
const diagramPalette = <Color>[
  Color(0xFF0072B2),
  Color(0xFFD55E00),
  Color(0xFF009E73),
  Color(0xFFCC79A7),
  Color(0xFFE69F00),
  Color(0xFF56B4E9),
];

Color diagramColor(int index) => diagramPalette[index % diagramPalette.length];

/// A "nice" grid step (1, 2, or 5 times a power of ten) near [rough].
double niceDiagramStep(double rough) {
  if (!rough.isFinite || rough <= 0) return 1;
  final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final fraction = rough / magnitude;
  final nice = fraction <= 1
      ? 1
      : fraction <= 2
          ? 2
          : fraction <= 5
              ? 5
              : 10;
  return nice * magnitude;
}

String _tickLabel(double value, double step) {
  final decimals = step >= 1 ? 0 : (-math.log(step) / math.ln10).ceil().clamp(0, 6);
  final text = value.toStringAsFixed(decimals);
  return text == '-0' ? '0' : text;
}

/// Draws the playground diagram for the student's own inputs and results.
class PlaygroundDiagram extends StatelessWidget {
  const PlaygroundDiagram({super.key, required this.data});

  final PlaygroundDiagramData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      key: const Key('playground-diagram'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Diagram', style: theme.textTheme.labelLarge),
        if (data.caption.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(data.caption, style: muted),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (data.problem != null)
          Row(
            key: const Key('playground-diagram-problem'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(data.problem!, style: theme.textTheme.bodySmall)),
            ],
          )
        else ...[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: AspectRatio(
                aspectRatio: 1,
                child: Semantics(
                  key: const Key('playground-diagram-canvas'),
                  container: true,
                  image: true,
                  label: data.description,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      child: CustomPaint(
                        painter: data.view == 'polar'
                            ? PolarDiagramPainter(
                                data: data,
                                gridColor: theme.colorScheme.outlineVariant,
                                textColor: theme.colorScheme.onSurfaceVariant,
                                inkColor: theme.colorScheme.onSurface,
                              )
                            : RouteDiagramPainter(
                                data: data,
                                gridColor: theme.colorScheme.outlineVariant,
                                textColor: theme.colorScheme.onSurfaceVariant,
                                inkColor: theme.colorScheme.onSurface,
                                labelBackground: theme.colorScheme.surface,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (data.legend.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final entry in data.legend) _LegendRow(entry: entry),
          ],
          for (final hint in data.hints)
            Padding(
              key: const Key('playground-diagram-hint'),
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.tips_and_updates_outlined,
                      size: 18, color: AppColors.performanceMid),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(hint, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.entry});

  final DiagramLegendEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      if (entry.valueText != null) 'you returned ${entry.valueText}',
      if (entry.note.isNotEmpty) entry.note,
    ].join('; ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            height: 16,
            child: entry.colorIndex == null
                ? null
                : CustomPaint(
                    painter: _LineSamplePainter(
                      color: diagramColor(entry.colorIndex!),
                      style: entry.style,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: entry.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (details.isNotEmpty) TextSpan(text: ': $details'),
                ],
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineSamplePainter extends CustomPainter {
  const _LineSamplePainter({required this.color, required this.style});

  final Color color;
  final String style;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = style == 'bold' ? 4 : 2.5
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    drawDiagramLine(
      canvas,
      Offset(2, y),
      Offset(size.width - 2, y),
      paint,
      dashed: style == 'dashed',
    );
  }

  @override
  bool shouldRepaint(_LineSamplePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.style != style;
}

void drawDiagramLine(
  Canvas canvas,
  Offset start,
  Offset end,
  Paint paint, {
  bool dashed = false,
}) {
  if (!dashed) {
    canvas.drawLine(start, end, paint);
    return;
  }
  final length = (end - start).distance;
  if (length == 0) return;
  final direction = (end - start) / length;
  const dash = 7.0;
  const gap = 5.0;
  for (var travelled = 0.0; travelled < length; travelled += dash + gap) {
    final from = start + direction * travelled;
    final to = start + direction * math.min(travelled + dash, length);
    canvas.drawLine(from, to, paint);
  }
}

void _drawText(
  Canvas canvas,
  String text,
  Offset anchor,
  Color color, {
  double fontSize = 10,
  FontWeight weight = FontWeight.w500,
  Alignment align = Alignment.center,
  Color? background,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: fontSize, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final offset = Offset(
    anchor.dx - painter.width * (align.x + 1) / 2,
    anchor.dy - painter.height * (align.y + 1) / 2,
  );
  if (background != null) {
    final rect = (offset & painter.size).inflate(2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = background.withValues(alpha: 0.9),
    );
  }
  painter.paint(canvas, offset);
}

/// Top-down route map drawn to scale with a grid and axis ticks.
class RouteDiagramPainter extends CustomPainter {
  RouteDiagramPainter({
    required this.data,
    required this.gridColor,
    required this.textColor,
    required this.inkColor,
    required this.labelBackground,
  });

  final PlaygroundDiagramData data;
  final Color gridColor;
  final Color textColor;
  final Color inkColor;
  final Color labelBackground;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.points.isEmpty || size.isEmpty) return;
    const left = 34.0;
    const bottom = 20.0;
    const pad = 12.0;
    final plot = Rect.fromLTRB(left, pad, size.width - pad, size.height - bottom);
    if (plot.width <= 0 || plot.height <= 0) return;

    var minX = data.points.map((p) => p.x).reduce(math.min);
    var maxX = data.points.map((p) => p.x).reduce(math.max);
    var minY = data.points.map((p) => p.y).reduce(math.min);
    var maxY = data.points.map((p) => p.y).reduce(math.max);
    // Keep a square world window so distances look the same in x and y;
    // coincident points get a one-unit frame.
    final extent = math.max(maxX - minX, maxY - minY);
    final span = extent <= 0 ? 1.0 : extent * 1.2;
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    minX = centerX - span / 2;
    maxX = centerX + span / 2;
    minY = centerY - span / 2;
    maxY = centerY + span / 2;
    final scale = math.min(plot.width, plot.height) / span;
    final origin = Offset(
      plot.left + (plot.width - span * scale) / 2,
      plot.top + (plot.height - span * scale) / 2,
    );
    Offset toScreen(double x, double y) => Offset(
          origin.dx + (x - minX) * scale,
          origin.dy + (maxY - y) * scale,
        );

    final step = niceDiagramStep(span / 5);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var x = (minX / step).ceil() * step; x <= maxX + 1e-9; x += step) {
      final top = toScreen(x, maxY);
      final base = toScreen(x, minY);
      canvas.drawLine(top, base, gridPaint);
      _drawText(canvas, _tickLabel(x, step), base + const Offset(0, 9), textColor);
    }
    for (var y = (minY / step).ceil() * step; y <= maxY + 1e-9; y += step) {
      final start = toScreen(minX, y);
      canvas.drawLine(start, toScreen(maxX, y), gridPaint);
      _drawText(
        canvas,
        _tickLabel(y, step),
        start - const Offset(4, 0),
        textColor,
        align: Alignment.centerRight,
      );
    }

    for (final path in data.paths) {
      final color = diagramColor(path.colorIndex);
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final screen = path.points.map((p) => toScreen(p.x, p.y)).toList();
      for (var index = 0; index < screen.length - 1; index++) {
        drawDiagramLine(canvas, screen[index], screen[index + 1], paint,
            dashed: path.dashed);
      }
      _drawArrowHead(canvas, screen[screen.length - 2], screen.last, color);
      if (path.shortText != null) {
        // The middle of the middle segment keeps labels off the points.
        final segment = (screen.length - 1) ~/ 2;
        final anchor = Offset.lerp(screen[segment], screen[segment + 1], 0.5)!;
        _drawText(
          canvas,
          path.shortText!,
          anchor + const Offset(0, -10),
          color,
          fontSize: 11,
          weight: FontWeight.w700,
          background: labelBackground,
        );
      }
    }

    final dotPaint = Paint()..color = inkColor;
    for (final point in data.points) {
      final at = toScreen(point.x, point.y);
      canvas.drawCircle(at, 4, dotPaint);
      _drawText(
        canvas,
        point.id,
        at + const Offset(6, -7),
        inkColor,
        fontSize: 11,
        weight: FontWeight.w800,
        align: Alignment.centerLeft,
      );
    }
  }

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Color color) {
    final vector = to - from;
    if (vector.distance < 12) return;
    final unit = vector / vector.distance;
    final tip = to - unit * 6;
    final normal = Offset(-unit.dy, unit.dx);
    final path = ui.Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((tip - unit * 9 + normal * 5).dx, (tip - unit * 9 + normal * 5).dy)
      ..lineTo((tip - unit * 9 - normal * 5).dx, (tip - unit * 9 - normal * 5).dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(RouteDiagramPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.textColor != textColor;
}

/// Polar view: robot at the centre, 0 degrees at the top, angles clockwise.
class PolarDiagramPainter extends CustomPainter {
  PolarDiagramPainter({
    required this.data,
    required this.gridColor,
    required this.textColor,
    required this.inkColor,
  });

  final PlaygroundDiagramData data;
  final Color gridColor;
  final Color textColor;
  final Color inkColor;

  static double _radians(double degrees) => degrees * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.readings.isEmpty || size.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 30;
    if (radius <= 0) return;
    Offset at(double angle, double distance) => center +
        Offset(
          distance * math.sin(_radians(angle)),
          -distance * math.cos(_radians(angle)),
        );

    final farthest = data.readings.map((r) => r.distance).reduce(math.max);
    final step = niceDiagramStep(farthest / 4);
    final outer = (farthest / step).ceil() * step;
    final scale = radius / outer;

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var ring = step; ring <= outer + 1e-9; ring += step) {
      canvas.drawCircle(center, ring * scale, gridPaint);
      // Ring labels sit on the 45-degree diagonal, away from the 0-degree line.
      _drawText(canvas, _tickLabel(ring, step), at(45, ring * scale), textColor,
          fontSize: 9, background: gridColor.withValues(alpha: 0.35));
    }
    for (var angle = 0; angle < 360; angle += 30) {
      canvas.drawLine(center, at(angle.toDouble(), radius), gridPaint);
      _drawText(canvas, '$angle°', at(angle.toDouble(), radius + 15), textColor);
    }

    for (final ray in data.rays.where((ray) => ray.halfWidth != null)) {
      final sweep = _radians(ray.halfWidth! * 2);
      final start = _radians(ray.angle - ray.halfWidth! - 90);
      final wedge = ui.Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(Rect.fromCircle(center: center, radius: radius), start, sweep, false)
        ..close();
      canvas.drawPath(
        wedge,
        Paint()..color = diagramColor(ray.colorIndex).withValues(alpha: 0.14),
      );
    }

    for (final arc in data.arcs) {
      var sweepDegrees = (arc.to - arc.from) % 360;
      if (sweepDegrees == 0 && arc.to != arc.from) sweepDegrees = 360;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius + 5),
        _radians(arc.from - 90),
        _radians(math.max(sweepDegrees, 1)),
        false,
        Paint()
          ..color = diagramColor(arc.colorIndex)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    final readingLine = Paint()
      ..color = inkColor.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    final readingDot = Paint()..color = inkColor;
    for (final reading in data.readings) {
      final point = at(reading.angle, reading.distance * scale);
      canvas.drawLine(center, point, readingLine);
      canvas.drawCircle(point, 3, readingDot);
    }

    for (final ray in data.rays) {
      final color = diagramColor(ray.colorIndex);
      final paint = Paint()
        ..color = color
        ..strokeWidth = ray.style == 'bold' ? 4 : 2
        ..strokeCap = StrokeCap.round;
      final end = at(ray.angle, radius);
      drawDiagramLine(canvas, center, end, paint, dashed: ray.style == 'dashed');
      if (ray.style == 'bold') {
        canvas.drawCircle(end, 5, Paint()..color = color);
      }
    }

    canvas.drawCircle(center, 6, Paint()..color = inkColor);
  }

  @override
  bool shouldRepaint(PolarDiagramPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.textColor != textColor;
}
