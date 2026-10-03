import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/main.dart' as app;
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/models/playground_result_dto.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/services/assignment_api.dart';
import 'package:iuse_demo/widgets/playground_dialog.dart';

const _code = '''
import math

def calculate_bug_route(start, hit, corner_a, corner_b, leave, goal):
    return 0.0, 0.0, 0.0, 0.0
''';

Widget _dialogApp(PlaygroundRunner runner, {ValueChanged<String>? onChanged}) {
  return MaterialApp(
    home: Scaffold(
      body: PlaygroundDialog(
        assignmentId: 2,
        functionName: 'calculate_bug_route',
        code: _code,
        initialArguments: '(0, 0), (4, 0)',
        onArgumentsChanged: onChanged,
        runner: runner,
      ),
    ),
  );
}

void main() {
  group('failure view', () {
    test('parses structured evidence and tolerates older results', () {
      final current = UnittestFeedbackDto.fromJson({
        'id': 2,
        'tested_vals': [],
        'pass': false,
        'ex_success': true,
        'unittest_results': ['Recheck the approach.'],
        'unittest_pass_results': [false],
        'code_exec_result': '',
        'code_output': '',
        'hint': '',
        'evidence': [
          {
            'test_id': 'approach',
            'label': 'Approach distance',
            'passed': false,
            'message': 'Recheck the approach.',
            'visibility': 'hidden',
            'reason': 'wrong_some_inputs',
            'weight': 25,
          },
        ],
      });
      expect(current.evidence.single.label, 'Approach distance');
      expect(current.evidence.single.reason, 'wrong_some_inputs');
      expect(current.evidence.single.weight, 25.0);

      final older = UnittestFeedbackDto.fromJson({
        'id': 2,
        'tested_vals': [],
        'pass': false,
        'ex_success': true,
        'unittest_results': ['Recheck.'],
        'unittest_pass_results': [false],
        'code_exec_result': '',
        'code_output': '',
        'hint': '',
        'evidence': [
          {'test_id': 'a', 'label': 'A', 'passed': false, 'message': 'Recheck.'},
        ],
      });
      expect(older.evidence.single.reason, isNull);
      expect(older.evidence.single.weight, isNull);
    });

    test('every grader reason has student guidance', () {
      for (final reason in [
        'wrong_all_inputs',
        'wrong_some_inputs',
        'error_on_some_inputs',
        'unsupported_type',
        'not_checked',
      ]) {
        expect(app.failureReasonExplanation(reason), isNotEmpty);
      }
      expect(app.failureReasonExplanation('passed'), isNull);
      expect(app.failureReasonExplanation(null), isNull);
    });

    testWidgets('cards show the check name, points, and failure guidance', (
      WidgetTester tester,
    ) async {
      const feedback = UnittestFeedbackDto(
        id: 2,
        score: 25,
        testedVals: [],
        pass: false,
        unittestFeedback: ['Approach is correct.', 'Recheck the boundary.'],
        unittestPassResults: [true, false],
        codeExecResult: '',
        codeOutput: '',
        execSuccess: true,
        hint: '',
        evidence: [
          TestEvidenceDto(
            testId: 'approach',
            label: 'Approach distance',
            passed: true,
            reason: 'passed',
            weight: 25,
          ),
          TestEvidenceDto(
            testId: 'boundary',
            label: 'Boundary-following distance',
            passed: false,
            reason: 'wrong_some_inputs',
            weight: 12.5,
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: app.Feedback(data: feedback))),
      );

      expect(find.text('Approach distance'), findsOneWidget);
      expect(find.text('Boundary-following distance'), findsOneWidget);
      expect(find.text('Check 1 · 25 of 25 points'), findsOneWidget);
      expect(find.text('Check 2 · 0 of 12.5 points'), findsOneWidget);
      expect(find.byKey(const Key('test-result-reason-2')), findsOneWidget);
      expect(find.byKey(const Key('test-result-reason-1')), findsNothing);
      expect(find.textContaining('Right for some scenarios'), findsOneWidget);
    });
  });

  group('input playground', () {
    test('reads parameter names from the student function', () {
      expect(
        playgroundParameterNames(_code, 'calculate_bug_route'),
        ['start', 'hit', 'corner_a', 'corner_b', 'leave', 'goal'],
      );
      expect(
        playgroundParameterNames(
          'def analyze(readings: dict, window=3):\n    pass',
          'analyze',
        ),
        ['readings', 'window'],
      );
      expect(playgroundParameterNames('x = 1', 'missing'), isEmpty);
    });

    test('assignment exposes the playground function only when provided', () {
      final base = {
        'id': 2,
        'title': 'A2',
        'description': '',
        'assignment_html': '',
        'starter_code': '',
        'vals': {},
      };
      expect(
        AssignmentDto.fromJson({...base, 'playground_function': 'route'})
            .playgroundFunction,
        'route',
      );
      expect(AssignmentDto.fromJson(base).playgroundFunction, isNull);
      expect(
        AssignmentDto.fromJson({...base, 'playground_function': null})
            .playgroundFunction,
        isNull,
      );
    });

    testWidgets('shows labelled return values and blocks double runs', (
      WidgetTester tester,
    ) async {
      final pending = Completer<PlaygroundResultDto>();
      final calls = <String>[];
      await tester.pumpWidget(
        _dialogApp((id, code, arguments) {
          calls.add(arguments);
          return pending.future;
        }),
      );

      expect(find.textContaining('not graded, not saved'), findsOneWidget);
      expect(
        find.text(
          'calculate_bug_route(start, hit, corner_a, corner_b, leave, goal)',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('playground-run-button')));
      await tester.pump();
      expect(find.text('Running…'), findsOneWidget);
      await tester.tap(find.byKey(const Key('playground-run-button')));
      await tester.pump();
      expect(calls, ['(0, 0), (4, 0)']);

      pending.complete(
        const PlaygroundResultDto(
          success: true,
          call: 'calculate_bug_route((0, 0), (4, 0))',
          returned: '(4.0, 4.0, 4.0, 12.0)',
          returnCount: 4,
          expectedReturnCount: 4,
          values: [
            PlaygroundValueDto(
              label: 'Approach distance',
              value: 0,
              display: '0.0',
            ),
            PlaygroundValueDto(label: 'Best option', value: 'Main Elevator'),
          ],
          output: 'Total: 12.0\n',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playground-values')), findsOneWidget);
      expect(find.text('Approach distance'), findsOneWidget);
      expect(find.text('0.0'), findsOneWidget);
      expect(find.text("'Main Elevator'"), findsOneWidget);
      expect(find.text('Total: 12.0'), findsOneWidget);
      expect(find.byKey(const Key('playground-return-count-warning')), findsNothing);
      expect(find.text('Run my function'), findsOneWidget);
    });

    testWidgets('explains a wrong return count and runtime errors', (
      WidgetTester tester,
    ) async {
      var response = const PlaygroundResultDto(
        success: true,
        call: 'calculate_bug_route()',
        returned: '(1, 2, 3)',
        returnCount: 3,
        expectedReturnCount: 4,
        values: [PlaygroundValueDto(label: 'Approach distance', value: 1)],
      );
      await tester.pumpWidget(_dialogApp((_, __, ___) async => response));

      await tester.tap(find.byKey(const Key('playground-run-button')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('returned 3 values, but the assignment expects 4'),
        findsOneWidget,
      );

      response = const PlaygroundResultDto(
        success: false,
        call: 'calculate_bug_route()',
        expectedReturnCount: 4,
        error: 'ZeroDivisionError at line 4 of submission: division by zero',
      );
      await tester.tap(find.byKey(const Key('playground-run-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ZeroDivisionError'), findsOneWidget);
      expect(find.byKey(const Key('playground-values')), findsNothing);
    });

    testWidgets('shows server input errors and connection failures', (
      WidgetTester tester,
    ) async {
      Object failure = const ApiRequestException(
        'Enter Python values separated by commas.',
      );
      await tester.pumpWidget(
        _dialogApp((_, __, ___) async => throw failure),
      );

      await tester.tap(find.byKey(const Key('playground-run-button')));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter Python values separated by commas.'),
        findsOneWidget,
      );

      failure = TimeoutException('slow');
      await tester.tap(find.byKey(const Key('playground-run-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('took too long'), findsOneWidget);
      expect(find.text('Run my function'), findsOneWidget);
    });

    testWidgets('reports edited inputs so they survive reopening', (
      WidgetTester tester,
    ) async {
      String? latest;
      await tester.pumpWidget(
        _dialogApp(
          (_, __, ___) async => const PlaygroundResultDto(
            success: true,
            call: '',
          ),
          onChanged: (value) => latest = value,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('playground-arguments')),
        '(1, 2), 3',
      );
      expect(latest, '(1, 2), 3');
    });

    testWidgets('toolbar offers Try inputs only when a playground exists', (
      WidgetTester tester,
    ) async {
      var opened = 0;
      Widget toolbar({VoidCallback? onTryInputs, bool isRunning = false}) {
        return MaterialApp(
          home: Scaffold(
            body: app.AssignmentEditorToolbar(
              isRunning: isRunning,
              onRun: () {},
              onTryInputs: onTryInputs,
            ),
          ),
        );
      }

      await tester.pumpWidget(toolbar());
      expect(find.byKey(const Key('try-inputs-button')), findsNothing);

      await tester.pumpWidget(toolbar(onTryInputs: () => opened += 1));
      await tester.tap(find.byKey(const Key('try-inputs-button')));
      expect(opened, 1);

      await tester.pumpWidget(
        toolbar(onTryInputs: () => opened += 1, isRunning: true),
      );
      final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('try-inputs-button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('phone toolbar uses a compact Try inputs button', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var opened = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: app.AssignmentEditorToolbar(
              isRunning: false,
              onRun: () {},
              onTryInputs: () => opened += 1,
            ),
          ),
        ),
      );

      final compact = find.byKey(const Key('try-inputs-button'));
      expect(tester.widget(compact), isA<IconButton>());
      expect(find.text('Try inputs'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(compact);
      expect(opened, 1);
    });
  });
}
