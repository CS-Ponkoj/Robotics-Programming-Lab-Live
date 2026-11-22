import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iuse_demo/models/simulation_trace.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum TerminalLineKind {
  command,
  output,
  error,
  location,
  source,
  info,
  success,
}

/// One line in the run terminal. [line] is set on clickable error locations.
class TerminalLine {
  const TerminalLine(this.text, this.kind, {this.line});

  final String text;
  final TerminalLineKind kind;
  final int? line;
}

final _errorPattern = RegExp(
  r'^([A-Za-z_][\w.]*) at line (\d+) of submission: (.*)$',
  dotAll: true,
);
final _scenarioPattern = RegExp(
  r'^The required function could not complete every grading scenario '
  r'\(([A-Za-z_]\w*)(?:: (.*))?\)\.$',
);
// A frame as the ROS grader reports it: "controller.py, line 12, in tick".
final _textFramePattern = RegExp(
  r'^\s*(?:File ")?([\w.-]+\.py)"?, line (\d+), in (.+)$',
);

/// Lines a VS Code style terminal shows after a run: the command, everything
/// the program printed, the error with the student's own line of code, and a
/// one-line test summary. Built only from the run result and the student's
/// code; nothing here comes from protected tests.
List<TerminalLine> buildRunTerminalLines({
  required UnittestFeedbackDto data,
  required String code,
  String fileName = 'your_code.py',
  bool python = true,
  // The command a ROS 2 node really runs with, such as
  // 'ros2 run open_side controller'; null for a plain Python file.
  String? command,
}) {
  final lines = <TerminalLine>[
    TerminalLine(
      command != null
          ? '\$ $command'
          : python
              ? '\$ python $fileName'
              : '\$ run assignment tests',
      TerminalLineKind.command,
    ),
  ];
  final printed = data.codeOutput.trimRight();
  if (printed.isNotEmpty) {
    for (final text in printed.split('\n')) {
      lines.add(TerminalLine(text, TerminalLineKind.output));
    }
  } else if (data.feedbackMode == 'traditional') {
    // The server leaves printed output out of this feedback mode.
    lines.add(const TerminalLine(
        "(printed output is not part of this account's feedback)",
        TerminalLineKind.info));
  } else if (data.execSuccess) {
    lines.add(const TerminalLine('(no printed output)', TerminalLineKind.info));
  }

  if (!data.execSuccess) {
    final error = data.codeExecResult.trim();
    final codeLines = code.split('\n');

    void addFrame(int line, String? name, {String? file}) {
      // A frame in another project file is shown but cannot open here.
      final known = (file == null || file == fileName) &&
          line >= 1 &&
          line <= codeLines.length;
      lines.add(
        TerminalLine(
          '  File "${file ?? fileName}", line $line'
          '${name == null ? '' : ', in $name'}',
          TerminalLineKind.location,
          line: known ? line : null,
        ),
      );
      if (known && codeLines[line - 1].trim().isNotEmpty) {
        lines.add(
          TerminalLine(
            '    ${codeLines[line - 1].trim()}',
            TerminalLineKind.source,
          ),
        );
      }
    }

    void addTraceback(String exception) {
      lines.add(
        const TerminalLine(
          'Traceback (most recent call last):',
          TerminalLineKind.error,
        ),
      );
      for (final frame in data.errorFrames) {
        addFrame(frame.line, frame.name);
      }
      lines.add(TerminalLine(exception, TerminalLineKind.error));
    }

    final match = _errorPattern.firstMatch(error);
    final scenario = _scenarioPattern.firstMatch(error);
    final lineNumber = match == null ? null : int.tryParse(match.group(2)!);
    if (match != null && data.errorFrames.isNotEmpty) {
      // A full Python traceback of the student's own calls.
      addTraceback('${match.group(1)}: ${match.group(3)}');
    } else if (scenario != null && data.errorFrames.isNotEmpty) {
      // A grading test called the student's function; the test input
      // itself stays hidden, the student's own lines do not.
      lines.add(
        const TerminalLine(
          'A grading test called your function (its input is hidden):',
          TerminalLineKind.info,
        ),
      );
      addTraceback(
        scenario.group(2) == null
            ? scenario.group(1)!
            : '${scenario.group(1)}: ${scenario.group(2)}',
      );
    } else if (match != null && lineNumber != null && lineNumber >= 1) {
      addFrame(lineNumber, null);
      lines.add(
        TerminalLine(
          '${match.group(1)}: ${match.group(3)}',
          TerminalLineKind.error,
        ),
      );
    } else {
      // Errors reported as text, such as a ROS node's traceback, where
      // "controller.py, line 12, in tick" frames become clickable lines.
      final text = error.isEmpty ? 'The program could not be run.' : error;
      var tracebackShown = false;
      for (final raw in text.split('\n')) {
        final frame = _textFramePattern.firstMatch(raw);
        if (frame == null) {
          lines.add(
            TerminalLine(
              raw.startsWith('    ') ? raw : raw.trimRight(),
              raw.startsWith('    ')
                  ? TerminalLineKind.source
                  : TerminalLineKind.error,
            ),
          );
          continue;
        }
        if (!tracebackShown) {
          tracebackShown = true;
          lines.add(
            const TerminalLine(
              'Traceback (most recent call last):',
              TerminalLineKind.error,
            ),
          );
        }
        lines.add(
          TerminalLine(
            '  File "${frame.group(1)}", line ${frame.group(2)}, '
            'in ${frame.group(3)}',
            TerminalLineKind.location,
            line: frame.group(1) == fileName
                ? int.tryParse(frame.group(2)!)
                : null,
          ),
        );
      }
    }
    lines.add(
      const TerminalLine(
        'Tests did not finish: fix the error above, then run again.',
        TerminalLineKind.info,
      ),
    );
    return lines;
  }

  final total = data.unittestPassResults.length;
  final passed = data.unittestPassResults.where((item) => item).length;
  final score = data.score.clamp(0, 100);
  lines.add(
    TerminalLine(
      total == 0
          ? 'Tests finished. Score $score%.'
          : 'Tests finished: $passed of $total checks passed. Score $score%.',
      total > 0 && passed == total
          ? TerminalLineKind.success
          : TerminalLineKind.info,
    ),
  );
  return lines;
}

const _background = Color(0xFF263238);
const _headerBackground = Color(0xFF1F2B31);
const _border = Color(0xFF37474F);

Color _lineColor(TerminalLineKind kind) => switch (kind) {
      TerminalLineKind.command => const Color(0xFF9CDCFE),
      TerminalLineKind.output => const Color(0xFFEEFFFF),
      TerminalLineKind.error => const Color(0xFFF48771),
      TerminalLineKind.location => const Color(0xFF4FC1FF),
      TerminalLineKind.source => const Color(0xFFCE9178),
      TerminalLineKind.info => const Color(0xFFA6B5BD),
      TerminalLineKind.success => const Color(0xFF89D185),
    };

/// A terminal panel under the code editor, like the one in VS Code. It opens
/// on each run and can be resized, collapsed, cleared, and copied.
class RunTerminalPanel extends StatelessWidget {
  const RunTerminalPanel({
    super.key,
    required this.expanded,
    required this.height,
    required this.running,
    required this.lines,
    required this.onToggle,
    required this.onResize,
    this.onClear,
    this.onOpenLine,
    this.requestError,
    this.codeChanged = false,
  });

  final bool expanded;

  /// The code was edited or replaced after the shown run.
  final bool codeChanged;
  final double height;
  final bool running;

  /// Lines of the latest finished run, or empty before any run or after a
  /// clear.
  final List<TerminalLine> lines;

  /// Set when the run could not reach the grader.
  final String? requestError;
  final VoidCallback onToggle;
  final ValueChanged<double> onResize;
  final VoidCallback? onClear;
  final ValueChanged<int>? onOpenLine;

  static const minHeight = 96.0;
  static const maxHeight = 480.0;

  String get _status {
    if (running) return 'Running…';
    if (requestError != null) return 'Not run';
    if (lines.isEmpty) return '';
    if (codeChanged) return '${_runStatus()} · code changed since';
    return _runStatus();
  }

  String _runStatus() {
    if (lines.any((line) => line.kind == TerminalLineKind.error)) {
      return 'Error';
    }
    if (lines.last.kind == TerminalLineKind.success) return 'All checks passed';
    return 'Finished';
  }

  String get _plainText => [
        ...lines.map((line) => line.text),
        if (requestError != null) requestError!,
      ].join('\n');

  @override
  Widget build(BuildContext context) {
    final mono = const TextStyle(
      // The bundled code font of the lesson code cards; monospaced, so
      // indentation lines up.
      fontFamily: 'Lotion',
      fontFamilyFallback: ['Courier-New', 'monospace'],
      fontSize: 13,
      height: 1.55,
    );
    final statusColor = running
        ? const Color(0xFF82AAFF)
        : requestError != null ||
                lines.any((line) => line.kind == TerminalLineKind.error)
            ? const Color(0xFFF07178)
            : lines.isNotEmpty && lines.last.kind == TerminalLineKind.success
                ? const Color(0xFFC3E88D)
                : const Color(0xFFA6B5BD);
    final header = Container(
      height: 38,
      color: _headerBackground,
      padding: const EdgeInsets.only(left: 12, right: 6),
      child: Row(
        children: [
          const Icon(
            LucideIcons.squareTerminal,
            size: 16,
            color: Color(0xFF89DDFF),
          ),
          const SizedBox(width: 8),
          const Text(
            'Terminal',
            style: TextStyle(
              color: Color(0xFFEEFFFF),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 10),
          if (running)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF9CDCFE),
              ),
            ),
          if (_status.isNotEmpty) ...[
            const SizedBox(width: 6),
            // A small status pill, coloured by the outcome.
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _status,
                  key: const Key('run-terminal-status'),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          const Spacer(),
          if (expanded && (lines.isNotEmpty || requestError != null)) ...[
            _HeaderButton(
              key: const Key('run-terminal-copy'),
              tooltip: 'Copy terminal text',
              icon: LucideIcons.copy,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _plainText));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('Terminal text copied.')),
                );
              },
            ),
            _HeaderButton(
              key: const Key('run-terminal-clear'),
              tooltip: 'Clear terminal',
              icon: LucideIcons.ban,
              onPressed: onClear,
            ),
          ],
          _HeaderButton(
            key: const Key('run-terminal-toggle'),
            tooltip: expanded ? 'Collapse terminal' : 'Open terminal',
            icon: expanded
                ? LucideIcons.chevronDown
                : LucideIcons.chevronUp,
            onPressed: onToggle,
          ),
        ],
      ),
    );

    Widget body() {
      if (running) {
        return Text(
          'Running your code and the assignment tests…',
          style: mono.copyWith(color: _lineColor(TerminalLineKind.info)),
        );
      }
      if (requestError != null) {
        return Text(
          requestError!,
          style: mono.copyWith(color: _lineColor(TerminalLineKind.error)),
        );
      }
      if (lines.isEmpty) {
        return Text.rich(
          TextSpan(children: [
            TextSpan(
              text: '\$ ',
              style: mono.copyWith(color: _lineColor(TerminalLineKind.command)),
            ),
            TextSpan(
              text:
                  'Run tests to see what your program prints and any error here.',
              style: mono.copyWith(color: _lineColor(TerminalLineKind.info)),
            ),
          ]),
        );
      }
      // Plain lines sit in selection blocks that screen readers read as
      // text; a clickable error location stays outside them so it remains
      // its own control instead of being merged into the text.
      final children = <Widget>[];
      var block = <Widget>[];
      void closeBlock() {
        if (block.isEmpty) return;
        children.add(
          SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: block,
            ),
          ),
        );
        block = <Widget>[];
      }

      for (final line in lines) {
        if (line.line != null && onOpenLine != null) {
          closeBlock();
          children.add(
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: const Key('run-terminal-line-link'),
                onTap: () => onOpenLine!(line.line!),
                child: Semantics(
                  container: true,
                  button: true,
                  label: 'Go to line ${line.line} in the editor',
                  onTap: () => onOpenLine!(line.line!),
                  child: Text(
                    line.text,
                    style: mono.copyWith(
                      color: _lineColor(line.kind),
                      decoration: TextDecoration.underline,
                      decorationColor: _lineColor(line.kind),
                    ),
                  ),
                ),
              ),
            ),
          );
        } else {
          block.add(
            Text(line.text, style: mono.copyWith(color: _lineColor(line.kind))),
          );
        }
      }
      closeBlock();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    return Semantics(
      key: const Key('run-terminal'),
      container: true,
      label: 'Terminal',
      liveRegion: !running && lines.isNotEmpty,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: _background,
          border: Border(top: BorderSide(color: _border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (expanded)
              // Drag the top edge to resize, as in VS Code.
              MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                child: GestureDetector(
                  key: const Key('run-terminal-resize'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) => onResize(
                    (height - details.delta.dy).clamp(minHeight, maxHeight),
                  ),
                  child: const SizedBox(height: 5),
                ),
              ),
            header,
            if (expanded)
              SizedBox(
                height: height,
                child: Scrollbar(
                  child: SingleChildScrollView(
                    key: const Key('run-terminal-scroll'),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    child: body(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      color: const Color(0xFFA6B5BD),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
    );
  }
}

/// Terminal lines for a robot replay: what the node printed, any error with
/// the student's own line, and a one-line account of what the robot did.
/// Built only from the simulation result; it is never graded.
List<TerminalLine> buildSimulationTerminalLines(
  SimulationResultDto result,
  String fileName,
) {
  final lines = <TerminalLine>[
    const TerminalLine(
      '\$ simulate  (2D replay, not graded)',
      TerminalLineKind.command,
    ),
  ];
  for (final text in result.output.trimRight().split('\n')) {
    if (text.trim().isEmpty || text.startsWith('Simulated ')) continue;
    lines.add(TerminalLine(text, TerminalLineKind.output));
  }
  if (result.error.trim().isNotEmpty) {
    for (final text in result.error.trim().split('\n')) {
      final frame = _textFramePattern.firstMatch(text);
      if (frame != null && frame.group(1) == fileName) {
        lines.add(TerminalLine(
          '  File "$fileName", line ${frame.group(2)}, in ${frame.group(3)}',
          TerminalLineKind.location,
          line: int.tryParse(frame.group(2)!),
        ));
      } else {
        lines.add(TerminalLine(text, TerminalLineKind.error));
      }
    }
  }
  final replay = result.replay;
  if (replay != null) {
    lines.add(TerminalLine(
      replay.summary,
      // Info, not success: a replay is never a passed check.
      TerminalLineKind.info,
    ));
  }
  return lines;
}
