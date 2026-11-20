import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/main.dart' as app;
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/screens/student_accounts_page.dart';
import 'package:iuse_demo/state/feedback_mode.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/run_terminal.dart';

UnittestFeedbackDto result(String mode) => UnittestFeedbackDto(
      id: 7,
      submissionId: 'mode-$mode',
      testedVals: const [],
      pass: false,
      // A traditional reply has blank messages; counts still come through.
      unittestFeedback:
          mode == 'traditional' ? const ['', ''] : const ['Stops', 'Drives'],
      unittestPassResults: const [true, false],
      codeExecResult: '',
      codeOutput: '',
      execSuccess: true,
      // Only TDD + AI replies carry a hint; the server blanks it otherwise.
      hint: mode == 'tdd_ai' ? 'Check the stop distance.' : '',
      tutorSource: mode == 'tdd_ai' ? 'fallback' : '',
      feedbackMode: mode,
    );

void main() {
  tearDown(() {
    currentFeedbackMode.value = FeedbackMode.tddAi;
    AppColors.usePalette(BrandPalettes.instructor);
  });

  test('wire values map to modes and unknown values fall back to TDD', () {
    expect(FeedbackMode.fromWire('traditional'), FeedbackMode.traditional);
    expect(FeedbackMode.fromWire('tdd_ai'), FeedbackMode.tddAi);
    expect(FeedbackMode.fromWire('bogus'), FeedbackMode.tdd);
    expect(FeedbackMode.traditional.allowsSimulation, isTrue);
    expect(FeedbackMode.tdd.allowsAi, isFalse);
    expect(FeedbackMode.tddAi.allowsAi, isTrue);
    expect(
      AuthenticatedUser.fromJson(const {
        'id': 'u',
        'login_id': 'ai',
        'role': 'student',
        'feedback_mode': 'tdd_ai',
      }).feedbackMode,
      'tdd_ai',
    );
  });

  test('each mode has its own colour and instructors keep the teal', () {
    final colours = {
      for (final mode in FeedbackMode.values)
        BrandPalettes.forAccount(signedInStudent: true, mode: mode).brand,
    };
    expect(colours, hasLength(3));
    expect(colours, isNot(contains(BrandPalettes.instructor.brand)));
    expect(colours, isNot(contains(AppColors.ai)));
    expect(
      BrandPalettes.forAccount(
        signedInStudent: false,
        mode: FeedbackMode.traditional,
      ),
      BrandPalettes.instructor,
    );
    AppColors.usePalette(BrandPalettes.tdd);
    expect(buildAppTheme().colorScheme.primary, BrandPalettes.tdd.brand);
  });

  test('white text stays readable on every gradient stop (4.5:1)', () {
    double contrast(Color colour) =>
        1.05 / (colour.computeLuminance() + 0.05);
    for (final palette in [
      BrandPalettes.instructor,
      BrandPalettes.traditional,
      BrandPalettes.tdd,
      BrandPalettes.tddAi,
    ]) {
      expect(contrast(palette.gradientStart), greaterThanOrEqualTo(4.5));
      expect(contrast(palette.gradientEnd), greaterThanOrEqualTo(4.5));
      expect(contrast(palette.brand), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('traditional results show the score and counts only', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: app.Feedback(data: result('traditional'))),
    ));
    expect(find.byKey(const Key('result-summary')), findsOneWidget);
    expect(find.textContaining('Test details'), findsNothing);
    expect(find.byKey(const Key('guided-hint')), findsNothing);
    expect(find.textContaining('compare your code with the task'),
        findsOneWidget);
    // Output was left out by the server, so no "nothing printed" panel.
    expect(find.byKey(const Key('terminal-output')), findsNothing);
  });

  test('the traditional terminal says output is not shown, not missing', () {
    final lines = buildRunTerminalLines(data: result('traditional'), code: '');
    final texts = lines.map((line) => line.text).toList();
    expect(texts.join(' '), contains('not part of this account'));
    expect(texts, isNot(contains('(no printed output)')));
  });

  testWidgets('TDD results keep test details without a hint', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: app.Feedback(data: result('tdd'))),
    ));
    expect(find.textContaining('Test details'), findsOneWidget);
    expect(find.byKey(const Key('guided-hint')), findsNothing);
    expect(FeedbackMode.tdd.allowsHints, isFalse);
  });

  testWidgets('TDD + AI results show the hint', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: app.Feedback(data: result('tdd_ai'))),
    ));
    expect(find.byKey(const Key('guided-hint')), findsOneWidget);
  });

  testWidgets('the instructor picks a mode and sees its pill', (tester) async {
    var chosen = FeedbackMode.tdd;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(children: [
            FeedbackModeField(
              value: chosen,
              onChanged: (mode) => setState(() => chosen = mode),
            ),
            FeedbackModePill(mode: chosen),
          ]),
        ),
      ),
    ));
    expect(find.byKey(const Key('feedback-mode-pill-tdd')), findsOneWidget);
    await tester.tap(find.byKey(const Key('feedback-mode-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Traditional').last);
    await tester.pumpAndSettle();
    expect(chosen, FeedbackMode.traditional);
    expect(
      find.byKey(const Key('feedback-mode-pill-traditional')),
      findsOneWidget,
    );
  });
}
