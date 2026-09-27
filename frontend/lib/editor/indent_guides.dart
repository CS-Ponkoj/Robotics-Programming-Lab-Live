import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

/// Paints editor-only Python indentation guides without modifying source text.
class EditorIndentGuides extends StatefulWidget {
  const EditorIndentGuides({
    super.key,
    required this.controller,
    required this.fontSize,
    required this.color,
    required this.child,
  });

  final CodeController controller;
  final double fontSize;
  final Color color;
  final Widget child;

  @override
  State<EditorIndentGuides> createState() => _EditorIndentGuidesState();
}

class _EditorIndentGuidesState extends State<EditorIndentGuides> {
  final ValueNotifier<double> _verticalOffset = ValueNotifier(0);
  final ValueNotifier<double> _horizontalOffset = ValueNotifier(0);

  @override
  void dispose() {
    _verticalOffset.dispose();
    _horizontalOffset.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    final offset = notification.metrics.pixels;
    if (notification.metrics.axis == Axis.vertical) {
      _verticalOffset.value = offset;
    } else if (notification.metrics.axis == Axis.horizontal) {
      _horizontalOffset.value = offset;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  widget.controller,
                  _verticalOffset,
                  _horizontalOffset,
                ]),
                builder: (context, _) => CustomPaint(
                  key: const Key('editor-indent-guides'),
                  painter: IndentGuidePainter(
                    code: widget.controller.text,
                    fontSize: widget.fontSize,
                    color: widget.color,
                    verticalOffset: _verticalOffset.value,
                    horizontalOffset: _horizontalOffset.value,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class IndentGuidePainter extends CustomPainter {
  const IndentGuidePainter({
    required this.code,
    required this.fontSize,
    required this.color,
    required this.verticalOffset,
    required this.horizontalOffset,
  });

  final String code;
  final double fontSize;
  final Color color;
  final double verticalOffset;
  final double horizontalOffset;

  static const double editorTextStart = 72; // CodeField: 8px + 64px gutter.
  static const double editorTopPadding = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final style = TextStyle(fontFamily: 'Courier-New', fontSize: fontSize);
    final metrics = TextPainter(
      text: TextSpan(text: 'M', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final spaceWidth = metrics.width;
    final lineHeight = metrics.preferredLineHeight;
    metrics.dispose();
    final lines = code.split('\n');
    final first =
        math.max(0, ((verticalOffset - editorTopPadding) / lineHeight).floor());
    final last = math.min(
        lines.length, ((verticalOffset + size.height) / lineHeight).ceil() + 1);
    final guidePaint = Paint()
      ..color = color.withValues(alpha: 0.38)
      ..strokeWidth = 1;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(editorTextStart, 0,
        math.max(0, size.width - editorTextStart), size.height));
    for (var lineIndex = first; lineIndex < last; lineIndex++) {
      final depth = indentationDepth(lines[lineIndex]);
      final top = editorTopPadding + lineIndex * lineHeight - verticalOffset;
      for (var level = 1; level <= depth; level++) {
        final x =
            editorTextStart + (level * 4 - 0.5) * spaceWidth - horizontalOffset;
        canvas.drawLine(
          Offset(x, top),
          Offset(x, top + lineHeight),
          guidePaint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(IndentGuidePainter oldDelegate) =>
      code != oldDelegate.code ||
      fontSize != oldDelegate.fontSize ||
      color != oldDelegate.color ||
      verticalOffset != oldDelegate.verticalOffset ||
      horizontalOffset != oldDelegate.horizontalOffset;
}

int indentationDepth(String line) {
  var columns = 0;
  for (final character in line.split('')) {
    if (character == ' ') {
      columns++;
    } else if (character == '\t') {
      columns += 4;
    } else {
      break;
    }
  }
  return columns ~/ 4;
}
