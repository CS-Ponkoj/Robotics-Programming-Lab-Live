import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/languages/python.dart';
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/screens/assignment_workspace.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/run_terminal.dart';

void main() {
  testWidgets('line numbers scroll with the code', (tester) async {
    final controller = CodeController(
      language: python,
      text: [for (var i = 1; i <= 80; i++) 'value_$i = $i'].join('\n'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: AssignmentProjectWorkspace(
            files: const [],
            selectedPath: null,
            selectedFileEditable: true,
            controller: controller,
            onFileSelected: (_) {},
            onChanged: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('assignment-code-field'));
    await tester.drag(field, const Offset(0, -600));
    await tester.pumpAndSettle();

    final vertical = tester
        .stateList<ScrollableState>(
          find.descendant(of: field, matching: find.byType(Scrollable)),
        )
        .where((state) => state.position.axis == Axis.vertical)
        .map((state) => state.position.pixels)
        .toList();
    // The code and its gutter each scroll, and always by the same amount.
    expect(vertical.length, greaterThanOrEqualTo(2));
    expect(vertical.first, greaterThan(0));
    expect(vertical.toSet(), hasLength(1));
  });

  testWidgets('phones choose project files from a one-line picker',
      (tester) async {
    final controller = CodeController(language: python, text: 'pass');
    addTearDown(controller.dispose);
    const files = [
      AssignmentProjectFile(path: 'src/pkg/package.xml', content: '<p/>'),
      AssignmentProjectFile(path: 'src/pkg/pkg/controller.py', editable: true),
    ];
    AssignmentProjectFile? chosen;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 390,
          height: 700,
          child: AssignmentProjectWorkspace(
            files: files,
            selectedPath: files.last.path,
            selectedFileEditable: true,
            controller: controller,
            onFileSelected: (file) => chosen = file,
            onChanged: () {},
          ),
        ),
      ),
    ));

    expect(find.byKey(const Key('project-file-picker')), findsOneWidget);
    expect(find.byKey(const Key('assignment-project-file-tree')), findsNothing);
    await tester.tap(find.byKey(const Key('project-file-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('src/pkg/package.xml').last);
    await tester.pumpAndSettle();
    expect(chosen?.path, 'src/pkg/package.xml');
  });

  testWidgets('terminal says when the code changed after the shown run',
      (tester) async {
    Widget terminal({required bool codeChanged}) => MaterialApp(
          home: Scaffold(
            body: RunTerminalPanel(
              expanded: true,
              height: 200,
              running: false,
              lines: const [
                TerminalLine('All 4 checks passed.', TerminalLineKind.success),
              ],
              codeChanged: codeChanged,
              onToggle: () {},
              onResize: (_) {},
            ),
          ),
        );
    await tester.pumpWidget(terminal(codeChanged: false));
    expect(find.text('All checks passed'), findsOneWidget);
    await tester.pumpWidget(terminal(codeChanged: true));
    expect(find.text('All checks passed · code changed since'), findsOneWidget);
  });
}
