import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/main.dart' as app;
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/navigation/app_entry_policy.dart';
import 'package:iuse_demo/screens/assignment_list.dart';
import 'package:iuse_demo/screens/login_page.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const testAuthenticatedUser = AuthenticatedUser(
  id: 'test-user-id',
  loginId: 'student',
  role: 'student',
);

Future<void> testLogout() async {}

void main() {
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

  testWidgets('the public root clears a saved session and shows login',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'auth_session_token': 'previous-demo-session',
    });

    await tester.pumpWidget(
      const app.MyApp(forceFreshLoginOnStart: true),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('auth_session_token'), isNull);
  });

  testWidgets('shared app theme defines the visual system',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: FilledButton(
            onPressed: null,
            child: Text('Themed action'),
          ),
        ),
      ),
    );

    final context = tester.element(find.text('Themed action'));
    final theme = Theme.of(context);
    expect(theme.colorScheme.primary, AppColors.brand);
    expect(theme.scaffoldBackgroundColor, AppColors.pageBackground);
    expect(theme.cardTheme.elevation, 0);
    expect(theme.progressIndicatorTheme.linearMinHeight, 8);
  });

  testWidgets('assignment workspace adapts from desktop panels to mobile tabs',
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
    expect(find.byKey(const Key('assignment-results-panel')), findsOneWidget);
    expect(
      find.byKey(const Key('workspace-resize-handle')),
      findsOneWidget,
    );

    final initialEditorWidth =
        tester.getSize(find.byKey(const Key('assignment-editor-panel'))).width;
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
    expect(find.byTooltip('Restore workspace'), findsOneWidget);

    await tester.tap(find.byKey(const Key('focus-editor-button')));
    await tester.pump();
    expect(
      find.byKey(const Key('assignment-instructions-panel')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('assignment-results-panel')), findsOneWidget);

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
    expect(find.byKey(const Key('assignment-results-panel')), findsOneWidget);

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

    await tester.tap(find.text('Results'));
    await tester.pump();

    expect(
      find.byKey(const Key('assignment-instructions-panel')),
      findsNothing,
    );
    expect(find.byKey(const Key('assignment-results-panel')), findsOneWidget);
  });

  testWidgets('assignment header preserves back and feedback controls',
      (WidgetTester tester) async {
    var backCount = 0;
    var homeCount = 0;
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

    await tester.tap(find.byType(Switch));
    expect(feedbackEnabled, isTrue);
  });

  testWidgets('control enter runs assignment tests from the keyboard',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const MediaQuery(
          data: MediaQueryData(size: Size(1200, 900)),
          child: app.MyHomePage(
            title: 'Assignment 1: Navigation',
            id: 1,
          ),
        ),
      ),
    );
    addTearDown(() {
      app.learningProgress.latestScores.clear();
      app.learningProgress.bestScores.clear();
      app.learningProgress.attemptCounts.clear();
    });

    expect(find.text('Ready when you are'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Ready when you are'), findsNothing);
  });

  testWidgets('editor toolbar runs tests once and exposes running state',
      (WidgetTester tester) async {
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

  testWidgets('workspace panel header presents consistent panel identity',
      (WidgetTester tester) async {
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
    expect(
      find.text('Review test outcomes and feedback'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(app.AssignmentPanelHeader)).height,
      64,
    );
  });

  testWidgets('assignment instructions organize content without losing it',
      (WidgetTester tester) async {
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

    await tester.tap(
      find.byKey(const Key('confirm-solution-reveal-button')),
    );
    await tester.pumpAndSettle();

    expect(solutionRevealed, isTrue);
    expect(find.text('Solution viewed'), findsOneWidget);
    expect(
      find.textContaining('The path is 16 units.', findRichText: true),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('worked solution stays locked until a test run is completed',
      (WidgetTester tester) async {
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

  testWidgets('landing page header presents the robotics lab identity',
      (WidgetTester tester) async {
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

  testWidgets('account menu waits for logout without leaving a popup route',
      (WidgetTester tester) async {
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

  testWidgets('instructor header exposes role-authorized management',
      (WidgetTester tester) async {
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
  });

  testWidgets('login page asks for study credentials',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(onAuthenticated: (_) {}),
      ),
    );

    expect(find.byKey(const Key('login-id-field')), findsOneWidget);
    expect(find.byKey(const Key('login-password-field')), findsOneWidget);
    expect(find.byKey(const Key('login-submit-button')), findsOneWidget);
    expect(find.textContaining('student / student'), findsNothing);
    expect(find.textContaining('instructor / instructor'), findsNothing);
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('landing page content is centered and width constrained',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LandingPageContent(
            child: ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );

    final content = find.byKey(const Key('landing-page-content'));
    expect(content, findsOneWidget);
    expect(tester.getSize(content).width, 1180);
    expect(tester.getCenter(content).dx, 800);
  });

  testWidgets('landing page frame uses the neutral learning surface',
      (WidgetTester tester) async {
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

  testWidgets('loading state presents assignment placeholders',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AssignmentLoadingState()),
      ),
    );

    expect(find.text('Loading assignments…'), findsOneWidget);
    expect(find.byType(AssignmentSkeletonCard), findsNWidgets(3));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error state retries assignment loading',
      (WidgetTester tester) async {
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssignmentLoadError(
            onRetry: () => retryCount += 1,
          ),
        ),
      ),
    );

    expect(find.text('Assignments are unavailable'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retryCount, 1);
  });

  testWidgets('progress summary reflects completed assignments',
      (WidgetTester tester) async {
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
        home: Scaffold(
          body: ProgressSummary(totalAssignments: 4),
        ),
      ),
    );

    expect(find.text('1 of 4 assignments completed'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);

    final progress = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(progress.value, 0.25);
  });

  testWidgets('assignment collection switches between grid and list layouts',
      (WidgetTester tester) async {
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

  testWidgets('assignment card keeps the existing assignment navigation',
      (WidgetTester tester) async {
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

  testWidgets('assignment card marks a revealed solution',
      (WidgetTester tester) async {
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

  testWidgets('assignment card distinguishes progress state from score',
      (WidgetTester tester) async {
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
  });

  testWidgets('feedback uses boolean results for pass and accuracy counts',
      (WidgetTester tester) async {
    const feedback = UnittestFeedbackDto(
      id: 2,
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
    expect(find.textContaining('Accuracy: 50.0%'), findsOneWidget);
    expect(find.byKey(const Key('result-summary')), findsOneWidget);
    expect(find.byKey(const Key('terminal-output')), findsOneWidget);
    expect(find.text('Keep refining your solution'), findsOneWidget);
    expect(find.text('Passed'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
  });

  testWidgets('guided feedback presents terminal output and hint separately',
      (WidgetTester tester) async {
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
      tutorSource: 'openai',
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
    expect(find.text('OpenAI tutor hint'), findsOneWidget);
    expect(find.text('Hint level 1 of 4'), findsOneWidget);
    expect(find.byKey(const Key('next-hint-button')), findsOneWidget);
    expect(
      find.text('Define total_distance before printing it.'),
      findsOneWidget,
    );
  });

  testWidgets('test run error explains how to recover and retries',
      (WidgetTester tester) async {
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: app.TestRunErrorState(
            onRetry: () => retryCount += 1,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('test-run-error-state')), findsOneWidget);
    expect(find.text('Grading service unavailable'), findsOneWidget);
    expect(find.textContaining('http://127.0.0.1:5000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry-test-run-button')));
    expect(retryCount, 1);
  });

  testWidgets('results remain readable and overflow-free on a narrow screen',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();

    const feedback = UnittestFeedbackDto(
      id: 3,
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
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: app.Feedback(data: feedback)),
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
    semantics.dispose();
  });
}
