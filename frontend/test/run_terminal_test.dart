import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/widgets/run_terminal.dart';

UnittestFeedbackDto result({
  bool success = true,
  String output = '',
  String error = '',
  List<bool> checks = const [true, false],
  int score = 50,
}) => UnittestFeedbackDto(
  id: 1,
  score: score,
  testedVals: const [],
  pass: checks.every((item) => item),
  unittestFeedback: [for (final _ in checks) 'Check'],
  unittestPassResults: checks,
  codeExecResult: error,
  codeOutput: output,
  execSuccess: success,
  hint: '',
);

const code =
    'import math\n'
    '\n'
    'def route(start, goal):\n'
    '    distance = math.hypot(dx)\n'
    '    return distance\n';

List<String> texts(List<TerminalLine> lines) => [for (final l in lines) l.text];

void main() {
  group('terminal lines', () {
    test('a finished run shows the command, printed output, and a summary', () {
      final lines = buildRunTerminalLines(
        data: result(output: 'Total travel distance: 11.17\nDone\n'),
        code: code,
      );
      expect(texts(lines), [
        r'$ python your_code.py',
        'Total travel distance: 11.17',
        'Done',
        'Tests finished: 1 of 2 checks passed. Score 50%.',
      ]);
      expect(lines.last.kind, TerminalLineKind.info);
    });

    test('all checks passing is shown as success', () {
      final lines = buildRunTerminalLines(
        data: result(checks: const [true, true], score: 100),
        code: code,
      );
      expect(lines[1].text, '(no printed output)');
      expect(lines.last.kind, TerminalLineKind.success);
      expect(
        lines.last.text,
        'Tests finished: 2 of 2 checks passed. Score 100%.',
      );
    });

    test('an error points to the student line and keeps earlier output', () {
      final lines = buildRunTerminalLines(
        data: result(
          success: false,
          output: 'starting\n',
          error: "NameError at line 4 of submission: name 'dx' is not defined",
        ),
        code: code,
        fileName: 'route.py',
      );
      expect(texts(lines), [
        r'$ python route.py',
        'starting',
        '  File "route.py", line 4',
        '    distance = math.hypot(dx)',
        "NameError: name 'dx' is not defined",
        'Tests did not finish: fix the error above, then run again.',
      ]);
      final location = lines.firstWhere(
        (l) => l.kind == TerminalLineKind.location,
      );
      expect(location.line, 4);
      expect(lines[4].kind, TerminalLineKind.error);
    });

    test('a line outside the code is shown but not linked', () {
      final lines = buildRunTerminalLines(
        data: result(
          success: false,
          error: 'ZeroDivisionError at line 99 of submission: division by zero',
        ),
        code: code,
      );
      final location = lines.firstWhere(
        (l) => l.kind == TerminalLineKind.location,
      );
      expect(location.line, isNull);
      expect(texts(lines), contains('ZeroDivisionError: division by zero'));
    });

    test('other errors are shown as written', () {
      final lines = buildRunTerminalLines(
        data: result(
          success: false,
          error:
              'The required function could not complete every grading '
              'scenario (KeyError).\nSecond line',
        ),
        code: code,
      );
      expect(
        lines.where((l) => l.kind == TerminalLineKind.error).map((l) => l.text),
        [
          'The required function could not complete every grading scenario (KeyError).',
          'Second line',
        ],
      );
      expect(lines.any((l) => l.kind == TerminalLineKind.location), isFalse);
      expect(
        buildRunTerminalLines(
          data: result(success: false),
          code: code,
        ).any((l) => l.text == 'The program could not be run.'),
        isTrue,
      );
    });

    test('non-Python assignments show a generic command', () {
      final lines = buildRunTerminalLines(
        data: result(),
        code: code,
        python: false,
      );
      expect(lines.first.text, r'$ run assignment tests');
    });
  });

  group('terminal panel', () {
    Widget host({
      bool expanded = true,
      bool running = false,
      List<TerminalLine> lines = const [],
      String? requestError,
      VoidCallback? onToggle,
      ValueChanged<double>? onResize,
      VoidCallback? onClear,
      ValueChanged<int>? onOpenLine,
      double width = 800,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: width,
              child: RunTerminalPanel(
                expanded: expanded,
                height: 180,
                running: running,
                lines: lines,
                requestError: requestError,
                onToggle: onToggle ?? () {},
                onResize: onResize ?? (_) {},
                onClear: onClear,
                onOpenLine: onOpenLine,
              ),
            ),
          ),
        ),
      );
    }

    final errorLines = buildRunTerminalLines(
      data: result(
        success: false,
        output: 'starting\n',
        error: "NameError at line 4 of submission: name 'dx' is not defined",
      ),
      code: code,
    );

    testWidgets('before any run it explains what will appear', (tester) async {
      await tester.pumpWidget(host());
      expect(find.text('TERMINAL'), findsOneWidget);
      expect(
        find.textContaining('Run tests to see what your program prints'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('run-terminal-copy')), findsNothing);
    });

    testWidgets('while running it says so', (tester) async {
      await tester.pumpWidget(host(running: true));
      expect(find.text('Running…'), findsOneWidget);
      expect(find.textContaining('Running your code'), findsOneWidget);
    });

    testWidgets('an error location jumps to that line in the editor', (
      tester,
    ) async {
      int? opened;
      await tester.pumpWidget(
        host(lines: errorLines, onOpenLine: (l) => opened = l),
      );
      expect(find.text('Error'), findsOneWidget);
      expect(find.text('starting'), findsOneWidget);
      expect(find.text('    distance = math.hypot(dx)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('run-terminal-line-link')));
      expect(opened, 4);
    });

    testWidgets('collapse, clear, and resize controls report back', (
      tester,
    ) async {
      var toggled = 0;
      var cleared = 0;
      double? resized;
      await tester.pumpWidget(
        host(
          lines: errorLines,
          onToggle: () => toggled += 1,
          onClear: () => cleared += 1,
          onResize: (value) => resized = value,
        ),
      );
      await tester.tap(find.byKey(const Key('run-terminal-toggle')));
      await tester.tap(find.byKey(const Key('run-terminal-clear')));
      await tester.drag(
        find.byKey(const Key('run-terminal-resize')),
        const Offset(0, -60),
      );
      expect(toggled, 1);
      expect(cleared, 1);
      expect(resized, greaterThan(180));
      expect(resized, lessThanOrEqualTo(RunTerminalPanel.maxHeight));
    });

    testWidgets('a collapsed terminal shows only its header', (tester) async {
      await tester.pumpWidget(host(expanded: false, lines: errorLines));
      expect(find.text('TERMINAL'), findsOneWidget);
      expect(find.text('starting'), findsNothing);
      expect(find.byKey(const Key('run-terminal-resize')), findsNothing);
    });

    testWidgets('a connection problem is shown in the terminal', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(requestError: 'Could not reach the code runner.'),
      );
      expect(find.text('Could not reach the code runner.'), findsOneWidget);
      expect(find.text('Not run'), findsOneWidget);
    });

    testWidgets('it fits a 360 pixel phone', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(lines: errorLines, width: 360));
      expect(tester.takeException(), isNull);
    });
  });
}
