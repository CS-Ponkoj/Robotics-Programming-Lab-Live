import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/screens/assignment_workspace.dart';
import 'package:iuse_demo/theme/app_theme.dart';

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
            icon: Icons.menu_book_rounded,
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
}
