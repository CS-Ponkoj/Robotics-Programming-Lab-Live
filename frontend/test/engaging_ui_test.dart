import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/main.dart' as app;
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/screens/course_content_page.dart';
import 'package:iuse_demo/state/learning_progress_store.dart';
import 'package:iuse_demo/state/progress_storage_base.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/app_blocks.dart';
import 'package:iuse_demo/widgets/lesson_reader.dart';
import 'package:iuse_demo/widgets/quick_check.dart';
import 'package:iuse_demo/widgets/run_terminal.dart';
import 'package:iuse_demo/screens/assignment_list.dart';
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

  group('mockup parity', () {
    testWidgets('a quick check marks the right answer and explains it',
        (tester) async {
      final check = QuickCheck.fromAttribute(
          '{"prompt":"Which index?","options":["0","45","90"],"answer":1,'
          '"explanation":"The middle reading is straight ahead."}')!;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: check)));
      await tester.tap(find.byKey(const Key('quick-check-option-0')));
      await tester.pump();
      expect(find.text('Not quite. Try another answer.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quick-check-option-1')));
      await tester.pump();
      expect(find.text('Correct. The middle reading is straight ahead.'),
          findsOneWidget);
      expect(QuickCheck.fromAttribute('{"prompt":"x","options":["a"],"answer":3}'),
          isNull);
    });

    testWidgets('lesson sections show their place, time and a next button',
        (tester) async {
      final html = [
        for (final title in ['One', 'Two', 'Three'])
          '<h2>$title</h2>${[for (var i = 0; i < 30; i++) '<p>Words $i here.</p>'].join()}',
        '<h2>References</h2><p>[1] A source.</p>',
      ].join();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: LessonReader(html: html))),
      ));
      await tester.pumpAndSettle();
      // References is not counted as a section.
      expect(find.textContaining('Section 1 of 3 · about 1 min', findRichText: true), findsOneWidget);
      expect(find.textContaining('Section 3 of 3', findRichText: true), findsOneWidget);
      expect(find.text('Next: Two'), findsOneWidget);
      expect(find.text('Next: Three'), findsOneWidget);
      expect(find.text('Next: References'), findsNothing);
    });

    test('the terminal names the first check to fix', () {
      final lines = buildRunTerminalLines(
          data: _run(results: [true, false, false]), code: 'x = 1');
      expect(lines.last.text, 'First to fix: Check label 1');
      expect(lines.last.kind, TerminalLineKind.todo);
      final summary = lines.firstWhere((line) => line.failing != null);
      expect(summary.failing, 2);
      final traditional = buildRunTerminalLines(
          data: _run(results: [true, false], mode: 'traditional'),
          code: 'x = 1');
      expect(traditional.any((line) => line.text.startsWith('First to fix')),
          isFalse);
    });

    testWidgets('the terminal header counts the checks to fix', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RunTerminalPanel(
            expanded: true,
            height: 200,
            running: false,
            lines: buildRunTerminalLines(
                data: _run(results: [true, false, false]), code: 'x = 1'),
            onToggle: () {},
            onResize: (_) {},
          ),
        ),
      ));
      expect(find.text('2 checks to fix'), findsOneWidget);
    });

    testWidgets('results compare with the run before and fold long lists',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: app.Feedback(
            data: _run(results: [true, false, false, false, false]),
            previousScore: 30,
            previousPassed: 0,
            runNumber: 4,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Up from 30% on run 3 · 1 more check passes'),
          findsOneWidget);
      // Four failed checks start as one-line rows that open on a tap.
      expect(find.byKey(const Key('test-result-row-2')), findsOneWidget);
      expect(find.byKey(const Key('test-result-points-2')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('test-result-row-2')));
      await tester.tap(find.byKey(const Key('test-result-row-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('test-result-points-2')), findsOneWidget);
    });

    test('time since the last run reads naturally', () {
      final now = DateTime(2026, 11, 22, 12);
      int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
      expect(timeAgo(ago(const Duration(seconds: 20)), now: now), 'just now');
      expect(timeAgo(ago(const Duration(minutes: 5)), now: now), '5 min ago');
      expect(timeAgo(ago(const Duration(hours: 2)), now: now), '2 hours ago');
      expect(timeAgo(ago(const Duration(days: 1, hours: 2)), now: now),
          'yesterday');
    });

    testWidgets('the course path lists topics and assignments in order',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      app.learningProgress.startEphemeralSession();
      addTearDown(app.learningProgress.startEphemeralSession);
      await app.learningProgress.updateTopicProgress('ros2',
          title: 'ROS 2', lessonPercent: 60);
      const a1 = AssignmentDto(
          id: 7, title: 'Assignment 7: Wall', description: '', htmlDesc: '',
          code: '', vals: {});
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: ProgressSummary(
            totalAssignments: 1,
            pathAssignments: [a1],
            topics: [(id: 'ros2', title: 'ROS 2')],
          ),
        ),
      ));
      expect(find.bySemanticsLabel('ROS 2, Lesson 60% read'), findsOneWidget);
      expect(find.bySemanticsLabel('Assignment 7, Not started'), findsOneWidget);
    });
  });
}
