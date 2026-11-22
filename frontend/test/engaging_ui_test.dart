import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/main.dart' as app;
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/screens/course_content_page.dart';
import 'package:iuse_demo/state/learning_progress_store.dart';
import 'package:iuse_demo/state/progress_storage_base.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/app_blocks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

UnittestFeedbackDto _run({
  required List<bool> results,
  int score = 40,
  String mode = 'tdd',
}) =>
    UnittestFeedbackDto(
      id: 7,
      score: score,
      testedVals: const [],
      pass: false,
      unittestFeedback: [
        for (var i = 0; i < results.length; i++) 'Message $i',
      ],
      unittestPassResults: results,
      codeExecResult: '',
      codeOutput: '',
      execSuccess: true,
      hint: 'Look at the stop distance.',
      tutorSource: 'fallback',
      feedbackMode: mode,
      evidence: [
        for (var i = 0; i < results.length; i++)
          TestEvidenceDto(
              testId: 't$i', label: 'Check label $i', passed: results[i]),
      ],
    );

void main() {
  group('progress store', () {
    test('keeps the latest checks and reads them back', () async {
      final storage = InMemoryProgressStorage();
      final store = LearningProgressStore();
      await store.loadForUser('s1', storage: storage);
      await store.recordCheckSummary(
          7, const CheckSummary(passed: 9, total: 20, nextFailing: 'Stops'));
      final reloaded = LearningProgressStore();
      await reloaded.loadForUser('s1', storage: storage);
      final summary = reloaded.checkSummaries[7]!;
      expect((summary.passed, summary.total, summary.nextFailing),
          (9, 20, 'Stops'));
    });

    test('lesson progress only moves forward and finishes at 100', () async {
      final store = LearningProgressStore()..startEphemeralSession();
      await store.updateTopicProgress('ros2',
          title: 'ROS 2', lessonPercent: 40, nextHeading: '4. Scans');
      await store.updateTopicProgress('ros2', title: 'ROS 2', lessonPercent: 20);
      expect(store.topicProgress['ros2']!.lessonPercent, 40);
      expect(store.lessonToResume?.key, 'ros2');
      await store.updateTopicProgress('ros2',
          title: 'ROS 2', lessonPercent: 100);
      expect(store.topicProgress['ros2']!.doneKinds, contains('lesson'));
      // A finished lesson is no longer offered under Keep reading.
      expect(store.lessonToResume, isNull);
    });
  });

  group('checks summary', () {
    test('names the first failing check', () {
      final summary = app.summarizeChecks(_run(results: [true, false, false]))!;
      expect((summary.passed, summary.total, summary.nextFailing),
          (1, 3, 'Check label 1'));
    });

    test('keeps no check name for Traditional accounts', () {
      final summary = app.summarizeChecks(
          _run(results: [true, false], mode: 'traditional'))!;
      expect(summary.nextFailing, isEmpty);
    });
  });

  group('results', () {
    testWidgets('compare with the last run and lead with the first failure',
        (tester) async {
      int? openedLine;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: app.Feedback(
            data: _run(results: [true, false, false], score: 40),
            previousScore: 30,
            errorLine: 27,
            onGoToLine: (line) => openedLine = line,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Up from 30% on your last run'), findsOneWidget);
      final card = find.byKey(const Key('fix-first-card'));
      expect(find.descendant(of: card, matching: find.text('Check label 1')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('fix-first-line')));
      expect(openedLine, 27);
      // The built-in hint is offered from the card.
      expect(find.byKey(const Key('fix-first-hint')), findsOneWidget);
    });

    testWidgets('Traditional accounts get no Fix this first card',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: app.Feedback(
              data: _run(results: [true, false], mode: 'traditional')),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fix-first-card')), findsNothing);
      expect(find.byKey(const Key('result-next-step')), findsOneWidget);
    });
  });

  testWidgets('checks meter reads passed of total', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ChecksMeter(passed: 9, total: 20)),
    ));
    expect(find.text('9 / 20 checks'), findsOneWidget);
    expect(find.bySemanticsLabel('9 of 20 checks passing'), findsOneWidget);
  });

  testWidgets('topic steps tick finished steps and show lesson progress',
      (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: TopicStepBar(steps: [
          TopicStep(
            key: const Key('step-pretest'),
            number: 1,
            label: 'Pre-test',
            icon: LucideIcons.clipboardList,
            selected: false,
            done: true,
            onTap: () => tapped = 'pretest',
          ),
          TopicStep(
            key: const Key('step-lesson'),
            number: 2,
            label: 'Lesson',
            icon: LucideIcons.bookOpen,
            selected: true,
            done: false,
            progress: 60,
            onTap: () => tapped = 'lesson',
          ),
        ]),
      ),
    ));
    expect(find.bySemanticsLabel('Step 1: Pre-test, done'), findsOneWidget);
    expect(find.bySemanticsLabel('Step 2: Lesson, 60 percent read'),
        findsOneWidget);
    await tester.tap(find.text('Pre-test'));
    expect(tapped, 'pretest');
  });
}
