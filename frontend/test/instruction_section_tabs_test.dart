import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:iuse_demo/screens/assignment_workspace.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  testWidgets('the Instructions header tabs follow the scroll and jump',
      (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final nav = InstructionSectionNav();
    addTearDown(nav.dispose);
    final html = [
      '<p><strong>Scenario</strong></p>${'<p>Scenario text.</p>' * 30}',
      '<p><strong>Task</strong></p>${'<p>Task text.</p>' * 30}',
      '<p><strong>Rules</strong></p>${'<p>Rule text.</p>' * 30}',
    ].join();

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(children: [
          AssignmentPanelHeader(
            icon: LucideIcons.bookOpen,
            title: 'Instructions',
            subtitle: 'Review the scenario and task',
            sectionNav: nav,
          ),
          Expanded(
            child: SingleChildScrollView(
              key: const Key('scroll'),
              child: AssignmentInstructions(html: html, sectionNav: nav),
            ),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    // The tabs replace the subtitle and the old buttons above the sections.
    expect(find.text('Review the scenario and task'), findsNothing);
    expect(find.byKey(const Key('instruction-section-tabs')), findsOneWidget);
    expect(nav.sections.map((s) => s.label),
        ['Scenario', 'Your task', 'Rules & scoring']);
    expect(nav.current, 0);

    // A tab jumps to its section and is marked as the current one.
    await tester.tap(find.byKey(const Key('instruction-tab-2')));
    await tester.pumpAndSettle();
    expect(nav.current, 2);

    // Scrolling back to the top marks Scenario again.
    await tester.drag(find.byKey(const Key('scroll')), const Offset(0, 5000));
    await tester.pumpAndSettle();
    expect(nav.current, 0);
    // The tabs stay in the header, outside the scrolled content.
    expect(find.byKey(const Key('instruction-tab-0')), findsOneWidget);
  });

  test('bold-only paragraphs and h3 headings get the heading colour', () {
    final doc = html_parser.parseFragment(
        '<p><strong>Rules</strong></p><p>Use <strong>one</strong> scan.</p>'
        '<h3>Approach</h3>');
    final strongs = doc.querySelectorAll('strong');
    expect(instructionHeadingStyles(strongs[0])?['color'], isNotNull);
    // Bold words inside a sentence stay body text.
    expect(instructionHeadingStyles(strongs[1]), isNull);
    expect(instructionHeadingStyles(doc.querySelector('h3')!), isNotNull);
    expect(instructionHeadingStyles(doc.querySelector('p')!), isNull);
  });

  testWidgets('the workspace header shows status cards, score card and AI',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var ai = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          appBar: AssignmentPageHeader(
            title: 'Assignment 7: Stop Before the Wall',
            assignmentId: 7,
            status: 'Attempted',
            lastScore: 60,
            solutionViewed: true,
            feedbackEnabled: ai,
            onBack: () {},
            onHome: () {},
            onResultsOpen: () {},
            onFeedbackChanged: (value) => setState(() => ai = value),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('header-status-chip')), findsOneWidget);
    expect(find.byKey(const Key('header-solution-viewed')), findsOneWidget);
    expect(find.byKey(const Key('header-score-card')), findsOneWidget);
    expect(find.textContaining('60%', findRichText: true), findsOneWidget);
    // The AI button turns on, animates briefly, and settles.
    await tester.tap(find.byType(AiToggle));
    await tester.pumpAndSettle();
    expect(ai, isTrue);
    expect(tester.widget<AiToggle>(find.byType(AiToggle)).value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
