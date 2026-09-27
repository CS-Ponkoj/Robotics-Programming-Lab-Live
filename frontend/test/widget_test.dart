import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:highlight/languages/python.dart';
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/main.dart' as app;
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/navigation/app_entry_policy.dart';
import 'package:iuse_demo/screens/assignment_list.dart';
import 'package:iuse_demo/screens/login_page.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/theme/editor_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

const testAuthenticatedUser = AuthenticatedUser(
  id: 'test-user-id',
  loginId: 'student',
  role: 'student',
);

Future<void> testLogout() async {}

void main() {
  test('performance color moves from red through amber to green', () {
    expect(performanceColor(0), AppColors.performanceLow);
    expect(performanceColor(50), AppColors.performanceMid);
    expect(performanceColor(100), AppColors.success);
    expect(performanceColor(-10), AppColors.performanceLow);
    expect(performanceColor(110), AppColors.success);
  });

  test('feedback DTO preserves structured tutor guidance', () {
    final feedback = UnittestFeedbackDto.fromJson({
      'id': 1,
      'submission_id': 'submission-1',
      'assignment_version': 1,
      'tested_vals': <dynamic>[],
      'pass': false,
      'ex_success': true,
      'unittest_results': <dynamic>[],
      'unittest_pass_results': <dynamic>[],
      'code_exec_result': '',
      'code_output': '',
      'execution_status': 'runtime_error',
      'hint': 'Trace the first calculation.',
      'tutor_feedback': {
        'source': 'openai',
        'diagnosis': 'The first calculation is incomplete.',
        'debugging_steps': ['Trace both inputs.'],
      },
    });

    expect(feedback.tutorSource, 'openai');
    expect(
      feedback.tutorFeedback['diagnosis'],
      'The first calculation is incomplete.',
    );
    expect(feedback.tutorFeedback['debugging_steps'], ['Trace both inputs.']);
    expect(feedback.executionStatus, 'runtime_error');
  });

  test('assignment DTO parses the ROS project file permissions', () {
    final assignment = AssignmentDto.fromJson({
      'id': 5,
      'stable_id': 'ros2-drive-forward',
      'version': 1,
      'title': 'Drive Forward and Stop',
      'description': 'ROS 2 assignment',
      'assignment_html': '<p>Instructions</p>',
      'starter_code': 'pass',
      'language': 'python-ros2',
      'project_files': [
        {
          'path': 'src/robot_motion/package.xml',
          'content': '<package/>',
          'editable': false,
        },
        {
          'path': 'src/robot_motion/robot_motion/controller.py',
          'content': '',
          'editable': true,
        },
      ],
      'editable_file_path': 'src/robot_motion/robot_motion/controller.py',
      'vals': <String, dynamic>{},
    });

    expect(assignment.projectFiles, hasLength(2));
    expect(
      assignment.projectFiles.singleWhere((file) => file.editable).path,
      endsWith('controller.py'),
    );
    expect(assignment.editableFilePath, endsWith('controller.py'));
  });

  testWidgets('ROS project explorer identifies editable and locked files', (
    WidgetTester tester,
  ) async {
    const files = [
      AssignmentProjectFile(
        path: 'src/robot_motion/package.xml',
        content: '<package/>',
      ),
      AssignmentProjectFile(
        path: 'src/robot_motion/robot_motion/controller.py',
        editable: true,
      ),
    ];
    AssignmentProjectFile? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: app.AssignmentProjectExplorer(
            files: files,
            selectedPath: files.last.path,
            onFileSelected: (file) => selected = file,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('assignment-project-file-tree')),
      findsOneWidget,
    );
    expect(find.text('package.xml'), findsOneWidget);
    expect(find.text('controller.py'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    await tester.tap(find.text('package.xml'));
    expect(selected?.path, endsWith('package.xml'));
    expect(selected?.editable, isFalse);
  });

  testWidgets('locked ROS project file makes the code viewer read only', (
    WidgetTester tester,
  ) async {
    final controller = CodeController(language: python, text: '<package/>');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: app.AssignmentProjectWorkspace(
              files: const [
                AssignmentProjectFile(
                  path: 'src/robot_motion/package.xml',
                  content: '<package/>',
                ),
              ],
              selectedPath: 'src/robot_motion/package.xml',
              selectedFileEditable: false,
              controller: controller,
              diagnosticLine: 3,
              onFileSelected: (_) {},
              onChanged: () {},
            ),
          ),
        ),
      ),
    );

    final codeField = tester.widget<CodeField>(
      find.byKey(const Key('assignment-code-field')),
    );
    expect(codeField.readOnly, isTrue);
    expect(find.text('Read only'), findsOneWidget);
    expect(find.text('Check line 3'), findsOneWidget);
  });

  test('switching project files replaces the complete code model', () {
    final controller =
        CodeController(language: python, text: 'controller code');
    addTearDown(controller.dispose);

    app.setAssignmentEditorContent(controller, '<package/>');
    expect(controller.fullText, '<package/>');
    expect(controller.text, '<package/>');

    app.setAssignmentEditorContent(controller, 'editable controller');
    expect(controller.fullText, 'editable controller');
    expect(controller.text, 'editable controller');
  });

  test('only the authenticated app URL restores a browser session', () {
    expect(
      isAuthenticatedAppEntry(
        Uri.parse('https://robotics-programming-lab.vercel.app/'),
      ),
      isFalse,
    );
    expect(
      isAuthenticatedAppEntry(
        Uri.parse('https://robotics-programming-lab.vercel.app/#/app'),
      ),
      isTrue,
    );
    expect(
      isAuthenticatedAppEntry(
        Uri.parse('https://robotics-programming-lab.vercel.app/app'),
      ),
      isTrue,
    );
  });

  testWidgets('the public root clears a saved session and shows login', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_session_token': 'previous-demo-session',
    });

    await tester.pumpWidget(const app.MyApp(forceFreshLoginOnStart: true));
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .debugShowCheckedModeBanner,
      isFalse,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('auth_session_token'), isNull);
  });

  testWidgets('shared app theme defines the visual system', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: FilledButton(onPressed: null, child: Text('Themed action')),
        ),
      ),
    );

    final context = tester.element(find.text('Themed action'));
    final theme = Theme.of(context);
    expect(theme.colorScheme.primary, AppColors.brand);
    expect(theme.scaffoldBackgroundColor, AppColors.pageBackground);
    expect(theme.textTheme.bodySmall?.fontSize, 14);
    expect(theme.textTheme.labelSmall?.fontSize, 13);
    expect(theme.cardTheme.elevation, 0);
    expect(theme.progressIndicatorTheme.linearMinHeight, 8);
  });

  testWidgets(
    'assignment workspace adapts from desktop panels to mobile tabs',
    (WidgetTester tester) async {
      Widget workspaceApp(Size size) {
        return MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: const app.MyHomePage(
              title: 'Assignment 1: Navigation',
              id: 1,
            ),
          ),
        );
      }

      await tester.pumpWidget(workspaceApp(const Size(1200, 900)));

      expect(
        find.byKey(const Key('assignment-workspace-navigation')),
        findsNothing,
      );
      expect(find.byKey(const Key('assignment-editor-panel')), findsOneWidget);
      expect(
        find.byKey(const Key('assignment-instructions-panel')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('assignment-results-panel')), findsNothing);
      expect(find.byKey(const Key('workspace-resize-handle')), findsOneWidget);
      expect(find.byKey(const Key('open-results-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('open-results-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assignment-results-panel')), findsOneWidget);
      expect(find.text('Ready when you are'), findsOneWidget);
      expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const Key('results-ai-toggle')),
              )
              .value,
          isFalse);
      await tester.tap(find.byKey(const Key('minimize-results-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assignment-results-panel')), findsNothing);
      expect(find.byKey(const Key('assignment-editor-panel')), findsOneWidget);
      expect(
        find.byKey(const Key('assignment-instructions-panel')),
        findsOneWidget,
      );

      final initialEditorWidth = tester
          .getSize(find.byKey(const Key('assignment-editor-panel')))
          .width;
      await tester.drag(
        find.byKey(const Key('workspace-resize-handle')),
        const Offset(120, 0),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const Key('assignment-editor-panel'))).width,
        greaterThan(initialEditorWidth),
      );

      await tester.tap(find.byKey(const Key('focus-editor-button')));
      await tester.pump();
      expect(find.byKey(const Key('assignment-editor-panel')), findsOneWidget);
      expect(
        find.byKey(const Key('assignment-instructions-panel')),
        findsNothing,
      );
      expect(find.byKey(const Key('assignment-results-panel')), findsNothing);
      expect(
        find.byTooltip('Restore workspace (Ctrl+Alt+E)'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('focus-editor-button')));
      await tester.pump();
      expect(
        find.byKey(const Key('assignment-instructions-panel')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('assignment-results-panel')), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(
        find.byKey(const Key('assignment-instructions-panel')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('assignment-editor-panel')), findsNothing);
      expect(find.byKey(const Key('assignment-results-panel')), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const Key('assignment-editor-panel')), findsOneWidget);
      expect(find.byKey(const Key('assignment-results-panel')), findsNothing);

      await tester.pumpWidget(workspaceApp(const Size(390, 844)));

      expect(
        find.byKey(const Key('assignment-workspace-navigation')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('assignment-editor-panel')), findsOneWidget);
      expect(
        find.byKey(const Key('assignment-instructions-panel')),
        findsNothing,
      );
      expect(find.byKey(const Key('assignment-results-panel')), findsNothing);

      await tester.tap(find.text('Instructions'));
      await tester.pump();

      expect(find.byKey(const Key('assignment-editor-panel')), findsNothing);
      expect(
        find.byKey(const Key('assignment-instructions-panel')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('open-results-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('assignment-instructions-panel')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('assignment-results-panel')), findsOneWidget);
    },
  );

  testWidgets('assignment header preserves back and feedback controls', (
    WidgetTester tester,
  ) async {
    var backCount = 0;
    var homeCount = 0;
    var resultsCount = 0;
    var feedbackEnabled = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          appBar: app.AssignmentPageHeader(
            title: 'Assignment 1: Obstacle Avoidance',
            assignmentId: 1,
            status: 'Not submitted',
            feedbackEnabled: feedbackEnabled,
            onBack: () => backCount += 1,
            onHome: () => homeCount += 1,
            onResultsOpen: () => resultsCount += 1,
            onFeedbackChanged: (value) => feedbackEnabled = value,
          ),
        ),
      ),
    );

    expect(find.text('01'), findsOneWidget);
    expect(find.text('Obstacle Avoidance'), findsOneWidget);
    expect(find.text('Not submitted'), findsOneWidget);
    expect(find.text('AI tutoring'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to assignments'));
    expect(backCount, 1);

    await tester.tap(find.byKey(const Key('assignment-home-button')));
    expect(homeCount, 1);

    await tester.tap(find.byKey(const Key('open-results-button')));
    expect(resultsCount, 1);

    await tester.tap(find.byType(Switch));
    expect(feedbackEnabled, isTrue);
  });

  testWidgets('control enter runs assignment tests from the keyboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const MediaQuery(
          data: MediaQueryData(size: Size(1200, 900)),
          child: app.MyHomePage(title: 'Assignment 1: Navigation', id: 1),
        ),
      ),
    );
    addTearDown(() {
      app.learningProgress.latestScores.clear();
      app.learningProgress.bestScores.clear();
      app.learningProgress.attemptCounts.clear();
    });

    expect(find.byKey(const Key('assignment-results-panel')), findsNothing);
    expect(find.text('Ready when you are'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assignment-results-panel')), findsOneWidget);
    expect(find.text('Ready when you are'), findsNothing);
  });

  testWidgets('editor keyboard actions open tools and change appearance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const MediaQuery(
          data: MediaQueryData(size: Size(1200, 900)),
          child: app.MyHomePage(title: 'Assignment 1: Navigation', id: 1),
        ),
      ),
    );

    final bindings = tester
        .widget<CallbackShortcuts>(
          find.byType(CallbackShortcuts),
        )
        .bindings;
    for (final shortcut in [
      const SingleActivator(LogicalKeyboardKey.keyF, control: true),
      const SingleActivator(LogicalKeyboardKey.keyQ, control: true, alt: true),
      const SingleActivator(LogicalKeyboardKey.keyH, control: true),
      const SingleActivator(LogicalKeyboardKey.keyW, control: true, alt: true),
      const SingleActivator(LogicalKeyboardKey.keyD, control: true, alt: true),
      const SingleActivator(LogicalKeyboardKey.keyF, shift: true, alt: true),
      const SingleActivator(LogicalKeyboardKey.keyI,
          control: true, shift: true),
      const SingleActivator(LogicalKeyboardKey.keyR, control: true, alt: true),
      const SingleActivator(LogicalKeyboardKey.minus, control: true),
      const SingleActivator(LogicalKeyboardKey.digit1,
          control: true, alt: true),
      const SingleActivator(LogicalKeyboardKey.equal, control: true),
      const SingleActivator(LogicalKeyboardKey.digit2,
          control: true, alt: true),
      const SingleActivator(LogicalKeyboardKey.keyA, control: true, alt: true),
      const SingleActivator(LogicalKeyboardKey.f1),
      const SingleActivator(LogicalKeyboardKey.keyK, control: true, alt: true),
      const SingleActivator(LogicalKeyboardKey.keyT, control: true, alt: true),
      const SingleActivator(LogicalKeyboardKey.keyE, control: true, alt: true),
    ]) {
      expect(bindings.containsKey(shortcut), isTrue);
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Find in code'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(find.text('Editor shortcuts'), findsOneWidget);
  });

  testWidgets('editor toolbar runs tests once and exposes running state', (
    WidgetTester tester,
  ) async {
    var runCount = 0;
    final semantics = tester.ensureSemantics();

    Widget toolbarApp({required bool isRunning}) {
      return MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: app.AssignmentEditorToolbar(
            isRunning: isRunning,
            onRun: () => runCount += 1,
          ),
        ),
      );
    }

    await tester.pumpWidget(toolbarApp(isRunning: false));

    expect(find.text('Python editor'), findsOneWidget);
    expect(find.text('Run tests'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Run assignment tests')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('run-tests-button')));
    expect(runCount, 1);
    semantics.dispose();

    await tester.pumpWidget(toolbarApp(isRunning: true));

    expect(find.text('Running…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const Key('run-tests-button')));
    expect(runCount, 1);
  });

  testWidgets('editor toolbar exposes save state and essential tools', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var formatted = false;
    var saved = false;
    var themeToggled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: app.AssignmentEditorToolbar(
            isRunning: false,
            onRun: () {},
            onSave: () => saved = true,
            saveState: app.DraftSaveState.saved,
            onToggleEditorTheme: () => themeToggled = true,
            onSearch: () {},
            onReplace: () {},
            onFormat: () => formatted = true,
            onReset: () {},
            onShowShortcuts: () {},
            onShowApiReference: () {},
            onDecreaseFont: () {},
            onIncreaseFont: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('draft-save-state-icon')), findsOneWidget);
    expect(find.byKey(const Key('editor-tools-menu')), findsNothing);
    expect(find.byKey(const Key('run-tests-button')), findsOneWidget);
    for (final action in [
      ('save', 'Save draft (Ctrl+S / Ctrl+Alt+D)'),
      ('find', 'Find (Ctrl+F / Ctrl+Alt+Q)'),
      ('replace', 'Replace (Ctrl+H / Ctrl+Alt+W)'),
      ('format', 'Format Python (Shift+Alt+F / Ctrl+Shift+I)'),
      ('restore', 'Restore starter code (Ctrl+Alt+R)'),
      ('font-down', 'Decrease editor font (Ctrl+- / Ctrl+Alt+1)'),
      ('font-up', 'Increase editor font (Ctrl+= / Ctrl+Alt+2)'),
      ('reference', 'Python names and APIs (Ctrl+Alt+A)'),
      ('shortcuts', 'Keyboard shortcuts (F1 / Ctrl+Alt+K)'),
      ('theme', 'Switch editor to light mode (Ctrl+Alt+T)'),
    ]) {
      expect(find.byKey(Key('editor-${action.$1}-button')), findsOneWidget);
      expect(find.byTooltip(action.$2), findsOneWidget);
    }
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse
        .moveTo(tester.getCenter(find.byKey(const Key('editor-save-button'))));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Save draft (Ctrl+S / Ctrl+Alt+D)'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('editor-format-button')));
    await tester.tap(find.byKey(const Key('editor-format-button')));
    expect(formatted, isTrue);

    await tester.ensureVisible(find.byKey(const Key('editor-save-button')));
    await tester.tap(find.byKey(const Key('editor-save-button')));
    expect(saved, isTrue);

    await tester.ensureVisible(find.byKey(const Key('editor-theme-button')));
    await tester.tap(find.byKey(const Key('editor-theme-button')));
    expect(themeToggled, isTrue);
  });

  testWidgets('light and dark editor themes preserve code and selection', (
    WidgetTester tester,
  ) async {
    final controller = CodeController(language: python, text: 'print("robot")');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);

    Widget editorWithTheme(bool dark) => MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 600,
              child: app.AssignmentProjectWorkspace(
                files: const [],
                selectedPath: null,
                selectedFileEditable: true,
                controller: controller,
                editorDarkMode: dark,
                onFileSelected: (_) {},
                onChanged: () {},
              ),
            ),
          ),
        );

    await tester.pumpWidget(editorWithTheme(true));
    final darkBackground = tester
        .widget<CodeTheme>(find.byType(CodeTheme))
        .data!
        .styles['root']!
        .backgroundColor;
    final darkField = tester.widget<CodeField>(find.byType(CodeField));
    expect(darkField.textStyle?.fontSize, 16);
    expect(
        darkField.gutterStyle.textStyle?.color, EditorPalette.dark.lineNumber);
    expect(darkField.cursorColor, EditorPalette.dark.foreground);
    await tester.pumpWidget(editorWithTheme(false));
    final lightBackground = tester
        .widget<CodeTheme>(find.byType(CodeTheme))
        .data!
        .styles['root']!
        .backgroundColor;
    final lightField = tester.widget<CodeField>(find.byType(CodeField));
    expect(lightField.gutterStyle.textStyle?.color,
        EditorPalette.light.lineNumber);
    expect(lightField.cursorColor, EditorPalette.light.foreground);

    expect(darkBackground, isNot(lightBackground));
    expect(controller.fullText, 'print("robot")');
    expect(controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5));
  });

  testWidgets('workspace panel header presents consistent panel identity', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: app.AssignmentPanelHeader(
            icon: Icons.fact_check_rounded,
            title: 'Results',
            subtitle: 'Review test outcomes and feedback',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.fact_check_rounded), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Review test outcomes and feedback'), findsOneWidget);
    expect(tester.getSize(find.byType(app.AssignmentPanelHeader)).height, 64);
  });

  testWidgets('assignment instructions organize content without losing it', (
    WidgetTester tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var solutionRevealed = false;
    const html = '''
      <p><strong>Scenario</strong></p><p>A robot approaches an obstacle.</p>
      <p><strong>Question:</strong></p><p>Calculate the safe path.</p>
      <p><strong>Hints:</strong></p><p>Use the distance formula.</p>
      <p><strong>Solution</strong></p><p>The path is 16 units.</p>
    ''';

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SingleChildScrollView(
              child: app.AssignmentInstructions(
                assignmentId: 99,
                html: html,
                solutionRevealed: solutionRevealed,
                onSolutionRevealed: () {
                  setState(() => solutionRevealed = true);
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('instruction-scenario-section')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('instruction-task-section')), findsOneWidget);
    expect(
      find.byKey(const Key('instruction-support-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('instruction-solution-section')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Scenario instruction section')),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<HtmlWidget>(find.byType(HtmlWidget))
          .every((widget) => widget.baseUrl == apiBaseUri),
      isTrue,
    );
    expect(
      find.textContaining(
        'A robot approaches an obstacle.',
        findRichText: true,
      ),
      findsOne,
    );
    expect(
      find.textContaining('Calculate the safe path.', findRichText: true),
      findsOne,
    );
    expect(
      find.textContaining('Use the distance formula.', findRichText: true),
      findsOne,
    );
    expect(
      find.textContaining('The path is 16 units.', findRichText: true),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('reveal-solution-button')));
    await tester.pumpAndSettle();

    expect(find.text('Reveal worked solution?'), findsOneWidget);
    expect(solutionRevealed, isFalse);

    await tester.tap(find.byKey(const Key('confirm-solution-reveal-button')));
    await tester.pumpAndSettle();

    expect(solutionRevealed, isTrue);
    expect(find.text('Solution viewed'), findsOneWidget);
    expect(
      find.textContaining('The path is 16 units.', findRichText: true),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('worked solution stays locked until a test run is completed', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: app.AssignmentInstructions(
              html: '<p>Scenario details</p>',
              assignmentId: 2,
              solutionHtml: '<p>The total path is 14 units.</p>',
              canRevealSolution: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Complete one test run first'), findsOneWidget);
    expect(
      find.text('Run the tests once to unlock the solution'),
      findsOneWidget,
    );

    final revealButton = tester.widget<FilledButton>(
      find.byKey(const Key('reveal-solution-button')),
    );
    expect(revealButton.onPressed, isNull);
  });

  test('editor reports indentation depth without changing code', () {
    expect(app.editorIndentLevel('def move():'), 0);
    expect(app.editorIndentLevel('    if clear:'), 1);
    expect(app.editorIndentLevel('        return True'), 2);
    expect(app.editorIndentLevel('\treturn True'), 1);
  });

  testWidgets('assignment task steps are scannable without duplicate list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: app.AssignmentInstructions(
            html: '<p><strong>Task</strong></p><p>Complete the route.</p>'
                '<ol><li>Find the hit point.</li><li>Calculate the distance.</li></ol>',
          ),
        ),
      ),
    ));

    expect(find.text('What to complete'), findsOneWidget);
    expect(find.textContaining('Find the hit point.', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('Calculate the distance.', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('Complete the route.', findRichText: true),
        findsOneWidget);
    expect(
      tester
          .getTopLeft(
              find.textContaining('Complete the route.', findRichText: true))
          .dy,
      lessThan(tester.getTopLeft(find.text('What to complete')).dy),
    );
  });

  testWidgets('instruction diagram opens an enlarged view', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: app.AssignmentInstructions(
            html: '<p><img src="/images/1" alt="Robot path"></p>',
          ),
        ),
      ),
    ));
    final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget).first);
    html.onTapImage!(ImageMetadata(
      alt: 'Robot path',
      sources: const [ImageSource('/images/1')],
    ));
    await tester.pump();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Robot path'), findsOneWidget);
    expect(find.byTooltip('Close enlarged diagram'), findsOneWidget);
  });

  test('assignment DTO parses its maintained worked solution', () {
    final assignment = AssignmentDto.fromJson({
      'id': 1,
      'title': 'Assignment 1',
      'description': 'Description',
      'assignment_html': '<p>Scenario</p>',
      'solution_html': '<p>Total: 16.82842712474619 units</p>',
      'starter_code': 'answer = 0',
      'vals': <String, dynamic>{'answer': 16.82842712474619},
    });

    expect(assignment.solutionHtml, contains('16.82842712474619 units'));
  });

  testWidgets('landing page header presents the robotics lab identity', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: LandingPageHeader(
            user: testAuthenticatedUser,
            onLogout: testLogout,
          ),
        ),
      ),
    );

    expect(find.text('Robotics Programming Lab'), findsOneWidget);
    expect(
      find.text(
        'Practice autonomous navigation through hands-on coding challenges',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.memory_rounded), findsOneWidget);
    expect(find.byIcon(Icons.admin_panel_settings_outlined), findsNothing);
  });

  testWidgets('account menu waits for logout without leaving a popup route', (
    WidgetTester tester,
  ) async {
    var logoutCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: LandingPageHeader(
            user: testAuthenticatedUser,
            onLogout: () async {
              logoutCalls += 1;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Account menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(logoutCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('persistent student header exposes saved study progress', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: LandingPageHeader(
            user: testAuthenticatedUser,
            onLogout: testLogout,
          ),
        ),
      ),
    );

    expect(find.textContaining('Demo mode:'), findsNothing);
    expect(find.text('student'), findsOneWidget);
    expect(find.byKey(const Key('account-name-label')), findsOneWidget);
    await tester.tap(find.byTooltip('Account menu'));
    await tester.pumpAndSettle();
    expect(find.text('student (student)'), findsOneWidget);
    expect(find.text('My study progress'), findsOneWidget);
  });

  testWidgets('instructor header exposes role-authorized management', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: LandingPageHeader(
            user: AuthenticatedUser(
              id: 'instructor-id',
              loginId: 'instructor',
              role: 'instructor',
            ),
            onLogout: testLogout,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.admin_panel_settings_outlined), findsOneWidget);
    expect(find.text('instructor'), findsOneWidget);
  });

  testWidgets('long account names fit the narrow header', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: LandingPageHeader(
            user: AuthenticatedUser(
              id: 'long-name-id',
              loginId: 'a-very-long-student-account-name',
              role: 'student',
            ),
            onLogout: testLogout,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('account-name-label')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Account menu'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('login page asks for study credentials', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: LoginPage(onAuthenticated: (_) async {})),
    );

    expect(find.byKey(const Key('login-id-field')), findsOneWidget);
    expect(find.byKey(const Key('login-password-field')), findsOneWidget);
    expect(find.byKey(const Key('login-submit-button')), findsOneWidget);
    expect(find.byKey(const Key('student-demo-button')), findsOneWidget);
    expect(find.text('Try the student demo'), findsOneWidget);
    expect(find.textContaining('resets when you refresh'), findsOneWidget);
    expect(find.textContaining('student / student'), findsNothing);
    expect(find.textContaining('instructor / instructor'), findsNothing);
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('demo header is labeled temporary and hides saved study data', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: LandingPageHeader(
            user: AuthenticatedUser(
              id: 'demo-student-id',
              loginId: 'student',
              role: 'student',
              isDemo: true,
            ),
            onLogout: testLogout,
          ),
        ),
      ),
    );

    expect(
      find.text('Demo mode: all work resets when you refresh'),
      findsOneWidget,
    );
    expect(find.text('Demo'), findsOneWidget);
    await tester.tap(find.byTooltip('Account menu'));
    await tester.pumpAndSettle();
    expect(find.text('Demo student (temporary)'), findsOneWidget);
    expect(find.text('My study progress'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('landing page content is centered and width constrained', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LandingPageContent(child: ColoredBox(color: Colors.white)),
        ),
      ),
    );

    final content = find.byKey(const Key('landing-page-content'));
    expect(content, findsOneWidget);
    expect(tester.getSize(content).width, 1180);
    expect(tester.getCenter(content).dx, 800);
  });

  testWidgets('landing page frame uses the neutral learning surface', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LandingPageFrame(
          user: testAuthenticatedUser,
          onLogout: testLogout,
          body: SizedBox(),
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(
      find.byKey(const Key('landing-page-scaffold')),
    );
    expect(scaffold.backgroundColor, landingPageBackgroundColor);
  });

  testWidgets('loading state presents assignment placeholders', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AssignmentLoadingState())),
    );

    expect(find.text('Loading assignments…'), findsOneWidget);
    expect(find.byType(AssignmentSkeletonCard), findsNWidgets(3));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error state retries assignment loading', (
    WidgetTester tester,
  ) async {
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssignmentLoadError(onRetry: () => retryCount += 1),
        ),
      ),
    );

    expect(find.text('Assignments are unavailable'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retryCount, 1);
  });

  testWidgets('progress summary reflects completed assignments', (
    WidgetTester tester,
  ) async {
    app.learningProgress.latestScores
      ..clear()
      ..addAll({1: 60, 2: 60});
    app.learningProgress.bestScores
      ..clear()
      ..addAll({1: 100, 2: 60});
    addTearDown(() {
      app.learningProgress.latestScores.clear();
      app.learningProgress.bestScores.clear();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProgressSummary(totalAssignments: 4)),
      ),
    );

    expect(find.text('1 of 4 assignments completed'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);

    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 0.25);
    expect(progress.color, performanceColor(25));
    final percentage = tester.widget<Text>(find.text('25%'));
    expect(percentage.style?.color, performanceColor(25));
  });

  testWidgets('assignment collection switches between grid and list layouts', (
    WidgetTester tester,
  ) async {
    const assignments = [
      AssignmentDto(
        id: 1,
        title: 'Assignment 1: Navigation',
        description: 'Navigate around an obstacle.',
        htmlDesc: '<p>First assignment</p>',
        code: '',
        vals: {},
      ),
      AssignmentDto(
        id: 2,
        title: 'Assignment 2: Planning',
        description: 'Plan a safe path.',
        htmlDesc: '<p>Second assignment</p>',
        code: '',
        vals: {},
      ),
    ];

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget testApp() {
      return MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: AssignmentCollection(
              assignments: assignments,
              theme: Theme.of(context),
              onReturn: () {},
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(testApp());
    expect(find.byKey(const Key('assignment-grid')), findsOneWidget);
    expect(find.byKey(const Key('assignment-list')), findsNothing);

    await tester.binding.setSurfaceSize(const Size(700, 900));
    await tester.pump();

    expect(find.byKey(const Key('assignment-grid')), findsNothing);
    expect(find.byKey(const Key('assignment-list')), findsOneWidget);
  });

  testWidgets('assignment card keeps the existing assignment navigation', (
    WidgetTester tester,
  ) async {
    const assignment = AssignmentDto(
      id: 1,
      title: 'Assignment 1: Obstacle Avoidance',
      description: 'Guide the robot around an obstacle.',
      htmlDesc: '<p>Assignment details</p>',
      code: 'def navigate(): pass',
      vals: {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: AssignmentCard(
              a: assignment,
              theme: Theme.of(context),
              onReturn: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('01'), findsOneWidget);
    expect(find.text('Obstacle Avoidance'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);

    final startButton = find.text('Start assignment');
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(find.byType(app.MyHomePage), findsOneWidget);
  });

  testWidgets('assignment card marks a revealed solution', (
    WidgetTester tester,
  ) async {
    const assignment = AssignmentDto(
      id: 2,
      title: 'Assignment 2: Planning',
      description: 'Plan a safe route.',
      htmlDesc: '<p>Assignment details</p>',
      code: '',
      vals: {},
    );
    app.solutionRevealedAssignments.add(2);
    addTearDown(app.solutionRevealedAssignments.clear);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: AssignmentCard(
              a: assignment,
              theme: Theme.of(context),
              onReturn: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('solution-viewed-badge')), findsOneWidget);
    expect(find.text('Solution viewed'), findsOneWidget);
  });

  testWidgets('assignment card distinguishes progress state from score', (
    WidgetTester tester,
  ) async {
    const assignment = AssignmentDto(
      id: 3,
      title: 'Assignment 3: Navigation',
      description: 'Plan a safe route.',
      htmlDesc: '<p>Assignment details</p>',
      code: 'answer = 0',
      vals: {},
    );
    app.learningProgress.attemptCounts[3] = 1;
    app.learningProgress.latestScores[3] = 60;
    app.learningProgress.bestScores[3] = 60;
    addTearDown(() {
      app.learningProgress.attemptCounts.clear();
      app.learningProgress.latestScores.clear();
      app.learningProgress.bestScores.clear();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: AssignmentCard(
              a: assignment,
              theme: Theme.of(context),
              onReturn: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Attempted'), findsOneWidget);
    expect(find.text('Last score: 60%'), findsOneWidget);
    final badge = tester.widget<Container>(
      find.byKey(const Key('latest-score-badge')),
    );
    final decoration = badge.decoration! as BoxDecoration;
    expect(decoration.color, performanceColor(60).withValues(alpha: 0.12));
    final scoreText = tester.widget<Text>(find.text('Last score: 60%'));
    expect(scoreText.style?.color, performanceColor(60));
  });

  testWidgets('feedback separates weighted score from check pass rate', (
    WidgetTester tester,
  ) async {
    const feedback = UnittestFeedbackDto(
      id: 2,
      score: 35,
      testedVals: ['first', 'second'],
      pass: false,
      unittestFeedback: [
        'The value provided for first is correct',
        'The value of second is incorrect',
      ],
      unittestPassResults: [true, false],
      codeExecResult: '',
      codeOutput: '',
      execSuccess: true,
      hint: '',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: app.Feedback(data: feedback)),
      ),
    );

    expect(find.text('Passed: 1'), findsOneWidget);
    expect(find.text('Failed: 1'), findsOneWidget);
    expect(find.textContaining('Pass rate: 50.0%'), findsOneWidget);
    expect(find.byKey(const Key('result-summary')), findsOneWidget);
    expect(find.byKey(const Key('terminal-output')), findsOneWidget);
    expect(find.text('Keep refining your solution'), findsOneWidget);
    final summary = tester.widget<Container>(
      find.byKey(const Key('result-summary')),
    );
    final summaryDecoration = summary.decoration! as BoxDecoration;
    expect(
      summaryDecoration.color,
      performanceColor(35).withValues(alpha: 0.12),
    );
    final score = tester.widget<Text>(find.text('35%'));
    expect(score.style?.color, performanceColor(35));
    expect(find.text('Passed'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
  });

  testWidgets('results put failed checks first and give a next step', (
    WidgetTester tester,
  ) async {
    const feedback = UnittestFeedbackDto(
      id: 1,
      testedVals: [],
      pass: false,
      unittestFeedback: ['first passes', 'second fails'],
      unittestPassResults: [true, false],
      codeExecResult: '',
      codeOutput: '',
      execSuccess: true,
      hint: '',
    );
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: app.Feedback(data: feedback)),
    ));

    expect(find.byKey(const Key('result-next-step')), findsOneWidget);
    expect(find.text('Test details · failed first'), findsOneWidget);
    final failedPosition = tester.getTopLeft(find.text('Check 2')).dy;
    final passedPosition = tester.getTopLeft(find.text('Check 1')).dy;
    expect(failedPosition, lessThan(passedPosition));
  });

  testWidgets('guided feedback presents terminal output and hint separately', (
    WidgetTester tester,
  ) async {
    const feedback = UnittestFeedbackDto(
      id: 1,
      testedVals: [],
      pass: false,
      unittestFeedback: [],
      unittestPassResults: [],
      codeExecResult: 'NameError',
      codeOutput: '',
      execSuccess: false,
      hint: 'Define total_distance before printing it.',
      tutorSource: 'fallback',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: app.Feedback(data: feedback)),
      ),
    );

    expect(find.byKey(const Key('result-summary')), findsOneWidget);
    expect(find.text('Execution error'), findsOneWidget);
    expect(find.textContaining('NameError'), findsOneWidget);
    expect(find.byKey(const Key('guided-hint')), findsOneWidget);
    expect(find.text('Built-in tutor hint'), findsOneWidget);
    expect(find.text('Hint level 1 of 4'), findsOneWidget);
    expect(find.byKey(const Key('next-hint-button')), findsOneWidget);
    expect(
      find.text('Define total_distance before printing it.'),
      findsOneWidget,
    );
  });

  testWidgets('AI responses stay hidden while AI tutoring is off', (
    WidgetTester tester,
  ) async {
    const feedback = UnittestFeedbackDto(
      id: 1,
      submissionId: 'prior-attempt',
      testedVals: [],
      pass: false,
      unittestFeedback: ['Check the path calculation.'],
      unittestPassResults: [false],
      codeExecResult: '',
      codeOutput: '',
      execSuccess: true,
      hint: 'AI-generated hint',
      tutorSource: 'openai',
      tutorFeedback: {'source': 'openai', 'answer': 'AI response'},
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: app.Feedback(data: feedback))),
    );

    expect(find.text('Test details · failed first'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.byKey(const Key('guided-hint')), findsNothing);
    expect(find.byKey(const Key('tutor-question-field')), findsNothing);
    expect(find.byKey(const Key('tutor-answer-card')), findsNothing);
  });

  testWidgets('AI tutor accepts a question and presents structured guidance', (
    WidgetTester tester,
  ) async {
    const feedback = UnittestFeedbackDto(
      id: 1,
      submissionId: 'submission-1',
      testedVals: ['distance_to_hit'],
      pass: false,
      unittestFeedback: ['The value of distance_to_hit needs attention'],
      unittestPassResults: [false],
      codeExecResult: '',
      codeOutput: '',
      execSuccess: true,
      hint: 'Trace the first distance calculation.',
      tutorSource: 'openai',
      tutorFeedback: {
        'source': 'openai',
        'diagnosis': 'The first distance calculation is incorrect.',
        'answer': '',
        'debugging_steps': ['Inspect both coordinate differences.'],
        'guiding_question': 'Which coordinates define the first segment?',
        'next_action': 'Trace the distance helper inputs.',
      },
    );
    var capturedQuestion = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: app.Feedback(
            data: feedback,
            aiTutorEnabled: true,
            tutorQuestionRequester:
                (assignmentId, submissionId, question, hintLevel) async {
              capturedQuestion = question;
              return {
                'source': 'openai',
                'answer': 'A diagonal depends on both coordinate changes.',
                'diagnosis': 'Only one coordinate is currently used.',
                'debugging_steps': ['Compare both coordinate differences.'],
                'guiding_question': 'Which two differences define the segment?',
                'next_action': 'Trace the distance helper inputs.',
              };
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('tutor-answer-card')), findsOneWidget);
    expect(
      find.textContaining('The first distance calculation is incorrect.'),
      findsOneWidget,
    );

    final field = find.byKey(const Key('tutor-question-field'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Why does the diagonal calculation fail?');
    final button = find.byKey(const Key('ask-tutor-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(capturedQuestion, 'Why does the diagonal calculation fail?');
    expect(find.byKey(const Key('tutor-answer-card')), findsOneWidget);
    expect(find.text('OpenAI tutor response'), findsOneWidget);
    expect(
      find.text('A diagonal depends on both coordinate changes.'),
      findsOneWidget,
    );
    expect(find.textContaining('1. Compare both'), findsOneWidget);
  });

  testWidgets('returned tutor feedback keeps the question form available', (
    WidgetTester tester,
  ) async {
    const feedback = UnittestFeedbackDto(
      id: 1,
      submissionId: 'submission-with-tutor-feedback',
      testedVals: [],
      pass: false,
      unittestFeedback: [],
      unittestPassResults: [],
      codeExecResult: '',
      codeOutput: '',
      execSuccess: true,
      hint: 'Trace the failing calculation.',
      tutorSource: 'fallback',
      tutorFeedback: {
        'source': 'fallback',
        'diagnosis': 'One calculation needs attention.',
        'answer': '',
        'debugging_steps': ['Inspect its inputs.'],
        'guiding_question': 'Which value can you verify?',
        'next_action': 'Compare one intermediate value.',
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: app.Feedback(
            data: feedback,
            aiTutorEnabled: true,
            tutorQuestionRequester:
                (assignmentId, submissionId, question, hintLevel) async => {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('tutor-question-field')), findsOneWidget);
    expect(find.byKey(const Key('tutor-answer-card')), findsOneWidget);
  });

  testWidgets('tutor question failure keeps input and allows retry', (
    WidgetTester tester,
  ) async {
    const feedback = UnittestFeedbackDto(
      id: 2,
      submissionId: 'submission-2',
      testedVals: [],
      pass: true,
      unittestFeedback: [],
      unittestPassResults: [],
      codeExecResult: '',
      codeOutput: '',
      execSuccess: true,
      hint: '',
    );
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: app.Feedback(
            data: feedback,
            aiTutorEnabled: true,
            tutorQuestionRequester:
                (assignmentId, submissionId, question, hintLevel) async {
              calls += 1;
              if (calls == 1) {
                throw Exception('simulated provider failure');
              }
              return {
                'source': 'fallback',
                'answer': 'Use the latest visible test evidence.',
                'diagnosis': 'Review the first unexpected value.',
                'debugging_steps': ['Inspect one intermediate value.'],
                'guiding_question': 'What value can you verify by hand?',
                'next_action': 'Run one focused check.',
              };
            },
          ),
        ),
      ),
    );

    final field = find.byKey(const Key('tutor-question-field'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Can you explain this result?');
    final button = find.byKey(const Key('ask-tutor-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tutor-question-error')), findsOneWidget);
    expect(find.text('Can you explain this result?'), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Built-in tutor response'), findsOneWidget);
    expect(find.byKey(const Key('tutor-question-error')), findsNothing);
  });

  testWidgets('tutor prevents duplicate requests while an answer is loading', (
    WidgetTester tester,
  ) async {
    const feedback = UnittestFeedbackDto(
      id: 3,
      submissionId: 'submission-3',
      testedVals: [],
      pass: false,
      unittestFeedback: [],
      unittestPassResults: [],
      codeExecResult: '',
      codeOutput: '',
      execSuccess: true,
      hint: '',
    );
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: app.Feedback(
            data: feedback,
            aiTutorEnabled: true,
            tutorQuestionRequester:
                (assignmentId, submissionId, question, hintLevel) {
              calls += 1;
              return pending.future;
            },
          ),
        ),
      ),
    );
    final field = find.byKey(const Key('tutor-question-field'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Where should I debug first?');
    final button = find.byKey(const Key('ask-tutor-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    expect(calls, 1);
    expect(find.text('Asking tutor…'), findsOneWidget);

    pending.complete({
      'source': 'openai',
      'answer': 'Start with the first failing calculation.',
      'diagnosis': 'The first value is inconsistent.',
      'debugging_steps': ['Trace its inputs.'],
      'guiding_question': 'What result do you calculate by hand?',
      'next_action': 'Compare one value.',
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tutor-answer-card')), findsOneWidget);
    expect(find.text('Ask tutor'), findsOneWidget);
  });

  testWidgets('test run error explains how to recover and retries', (
    WidgetTester tester,
  ) async {
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: app.TestRunErrorState(onRetry: () => retryCount += 1),
        ),
      ),
    );

    expect(find.byKey(const Key('test-run-error-state')), findsOneWidget);
    expect(find.text('Grading service unavailable'), findsOneWidget);
    expect(find.textContaining('http://127.0.0.1:5000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry-test-run-button')));
    expect(retryCount, 1);
  });

  test('empty or whitespace-only code is not a test submission', () {
    expect(app.hasNonWhitespaceCode(''), isFalse);
    expect(app.hasNonWhitespaceCode('  \n\t  '), isFalse);
    expect(app.hasNonWhitespaceCode('pass'), isTrue);
  });

  testWidgets('empty editor shows a recovery action, not a score', (
    WidgetTester tester,
  ) async {
    var restoreRequested = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: app.EmptyCodeTestRunState(
          onRestore: () => restoreRequested = true,
        ),
      ),
    ));

    expect(find.text('The code editor is empty'), findsOneWidget);
    expect(find.textContaining('No attempt was submitted'), findsOneWidget);
    expect(find.textContaining('0%'), findsNothing);
    await tester.tap(find.byKey(const Key('restore-starter-from-results')));
    expect(restoreRequested, isTrue);
  });

  testWidgets('secure grader loading state explains free-tier startup delay', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: app.SecureGraderLoadingState())),
    );

    expect(
      find.byKey(const Key('secure-grader-loading-state')),
      findsOneWidget,
    );
    expect(find.text('Starting secure grader…'), findsOneWidget);
    expect(find.textContaining('up to one minute'), findsOneWidget);
  });

  testWidgets('results remain readable and overflow-free on a narrow screen', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();

    const feedback = UnittestFeedbackDto(
      id: 3,
      submissionId: 'narrow-submission',
      testedVals: ['optimal_sector_angle'],
      pass: false,
      unittestFeedback: [
        'The value of optimal_sector_angle needs additional attention',
      ],
      unittestPassResults: [false],
      codeExecResult: '',
      codeOutput: 'Calculated sector: 82 degrees',
      execSuccess: true,
      hint: 'Compare nearby sectors before selecting the final heading.',
      tutorSource: 'openai',
      tutorFeedback: {
        'source': 'openai',
        'answer': '',
        'diagnosis': 'The chosen sector is not the nearest safe sector.',
        'debugging_steps': [
          'List the safe candidates.',
          'Compare each candidate with the goal direction.',
        ],
        'guiding_question': 'Which safe sector is nearest the goal?',
        'next_action': 'Trace the selection step.',
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: app.Feedback(
            data: feedback,
            aiTutorEnabled: true,
            tutorQuestionRequester:
                (assignmentId, submissionId, question, hintLevel) async => {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('result-summary')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Test score 0 percent')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Test needs attention')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tutor-question-field')), findsOneWidget);
    expect(find.byKey(const Key('tutor-answer-card')), findsOneWidget);
    semantics.dispose();
  });
}
