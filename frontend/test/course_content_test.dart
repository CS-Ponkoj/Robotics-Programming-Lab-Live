import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/widgets/lesson_reader.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iuse_demo/screens/course_content_page.dart';
import 'package:iuse_demo/services/course_content_api.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/screens/assignment_list.dart';
import 'package:iuse_demo/theme/app_theme.dart';

const _student =
    AuthenticatedUser(id: 'test-student', loginId: 'student', role: 'student');
Future<void> _logout() async {}

void main() {
  test('incomplete quiz message names the unanswered question numbers', () {
    expect(unansweredQuizMessage([3]), 'Answer question 3 before submitting.');
    expect(unansweredQuizMessage([3, 7]),
        'Answer questions 3 and 7 before submitting.');
    expect(unansweredQuizMessage([2, 5, 9]),
        'Answer questions 2, 5 and 9 before submitting.');
  });

  testWidgets('expired session is distinguished from a content outage',
      (tester) async {
    CourseContentApi.testClient =
        MockClient((_) async => http.Response('{}', 401));
    addTearDown(() => CourseContentApi.testClient = null);
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: CourseCatalogPage(user: _student, onLogout: _logout)));
    await tester.pumpAndSettle();
    expect(find.text('Please sign in again'), findsOneWidget);
    expect(find.textContaining('Your saved scores are unchanged.'),
        findsOneWidget);
    expect(find.text('Course content is unavailable right now.'), findsNothing);
  });
  late MockClient client;

  setUp(() {
    client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/contents') {
        return http.Response(
            jsonEncode({
              'topics': [
                for (final name in [
                  'Obstacle Avoidance',
                  'Path Planning',
                  'Sensor Fusion',
                  'Range Sensors',
                  'Locomotion',
                  'Hybrid Navigation and GPS'
                ])
                  {
                    'id': name.toLowerCase().replaceAll(' ', '-'),
                    'title': name,
                    'summary': 'Learn $name',
                    'quiz_progress': name == 'Obstacle Avoidance'
                        ? {
                            'attempt_count': 2,
                            'latest_score': 40,
                            'best_score': 100
                          }
                        : {
                            'attempt_count': 0,
                            'latest_score': null,
                            'best_score': null
                          },
                  },
              ],
            }),
            200);
      }
      if (path == '/contents/obstacle-avoidance') {
        return http.Response(
            jsonEncode({
              'id': 'obstacle-avoidance',
              'title': 'Obstacle Avoidance',
              'summary': 'Learn Obstacle Avoidance',
              'sections': [
                {'id': 'lesson', 'title': 'Lesson', 'kind': 'lesson'},
                {'id': 'practice', 'title': 'Practice', 'kind': 'exercise'},
                {'id': 'quiz', 'title': 'Quiz', 'kind': 'quiz'},
              ],
            }),
            200);
      }
      if (path.endsWith('/sections/lesson')) {
        return http.Response(
            jsonEncode({
              'id': 'lesson',
              'title': 'Lesson',
              'kind': 'lesson',
              'html': '<p>Robot lesson content: robot’s turn is π radians</p>',
              'questions': [],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (path.endsWith('/sections/practice')) {
        return http.Response(
            jsonEncode({
              'id': 'practice',
              'title': 'Practice',
              'kind': 'exercise',
              'html': '<p>Try the exercise</p>',
              'questions': [],
            }),
            200);
      }
      if (path.endsWith('/sections/quiz')) {
        return http.Response(
            jsonEncode({
              'id': 'quiz',
              'title': 'Quiz',
              'kind': 'quiz',
              'version': 'test-version',
              'html': '',
              'questions': [
                {
                  'id': 'q1',
                  'prompt': 'Which direction?',
                  'options': [
                    {'id': 'A', 'text': 'Backward'},
                    {'id': 'B', 'text': 'Forward'},
                  ],
                }
              ],
            }),
            200);
      }
      if (path.endsWith('/quiz/attempts')) {
        return http.Response(jsonEncode({'attempts': []}), 200);
      }
      if (path.endsWith('/quiz/submit')) {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['quiz_version'], 'test-version');
        expect(payload['choices'], {'q1': 'B'});
        return http.Response(
            jsonEncode({
              'score_percent': 100,
              'correct_count': 1,
              'total_questions': 1,
              'saved': true,
            }),
            200);
      }
      return http.Response('Not found', 404);
    });
    CourseContentApi.testClient = client;
  });

  tearDown(() {
    CourseContentApi.testClient = null;
    client.close();
  });

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('catalog remains readable at width $width with enlarged text',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: CourseCatalogPage(user: _student, onLogout: _logout),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Attempted: 0'), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('contents shares branding and account controls and returns home',
      (tester) async {
    var logoutCount = 0;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CourseCatalogPage(
              user: _student,
              onLogout: () async {
                logoutCount++;
              }),
        )),
        child: const Text('Open catalog'),
      ));
    })));
    await tester.tap(find.text('Open catalog'));
    await tester.pumpAndSettle();
    expect(find.text('Robotics Programming Lab'), findsOneWidget);
    expect(find.byIcon(Icons.memory_rounded), findsOneWidget);
    expect(find.text('student'), findsOneWidget);
    await tester.tap(find.byKey(const Key('course-home-button')));
    await tester.pumpAndSettle();
    expect(find.text('Open catalog'), findsOneWidget);
    await tester.tap(find.text('Open catalog'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Account menu'));
    await tester.pumpAndSettle();
    expect(find.text('My study progress'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(logoutCount, 1);
    expect(find.text('Open catalog'), findsOneWidget);
  });

  testWidgets('assignments and contents toggle below the same fixed header',
      (tester) async {
    final assignmentsClient =
        MockClient((_) async => http.Response('{"assignments":[]}', 200));
    addTearDown(assignmentsClient.close);
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          home: AssignmentListPage(user: _student, onLogout: _logout)));
      await tester.pumpAndSettle();
      final header = tester.element(find.byType(LandingPageHeader));
      await tester.tap(find.byKey(const Key('open-course-contents')));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(LandingPageHeader)), same(header));
      expect(find.byType(LandingPageHeader), findsOneWidget);
      expect(find.text('student'), findsOneWidget);
      expect(find.text('Learn the ideas, then practice them'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-assignments')));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(LandingPageHeader)), same(header));
      expect(find.text('Learn the ideas, then practice them'), findsNothing);
      await tester.tap(find.byKey(const Key('open-course-contents')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('course-home-button')));
      await tester.pumpAndSettle();
      expect(find.text('Learn the ideas, then practice them'), findsNothing);
      expect(tester.takeException(), isNull);
    }, () => assignmentsClient);
  });

  testWidgets('all six topics appear at mobile width and open a lesson',
      (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: CourseCatalogPage(user: _student, onLogout: _logout)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('content-topic-obstacle-avoidance')),
        findsOneWidget);
    expect(find.byKey(const Key('content-topic-hybrid-navigation-and-gps')),
        findsOneWidget);
    await tester.ensureVisible(find.text('Open content →').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open content →').first);
    await tester.pumpAndSettle();
    expect(find.text('Robotics Programming Lab'), findsOneWidget);
    expect(find.byKey(const Key('account-name-label')), findsOneWidget);
    expect(find.byKey(const Key('course-home-button')), findsOneWidget);
    expect(
        tester
            .widget<LessonReader>(find.byKey(const Key('course-section-html')))
            .html,
        contains('robot’s turn is π radians'));
    expect(find.text('Exercises'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'catalog shows latest and best quiz score without treating zero as missing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CourseCatalogPage(user: _student, onLogout: _logout)));
    await tester.pumpAndSettle();
    expect(find.text('Last score: 40%'), findsOneWidget);
    expect(find.text('Best score: 100%'), findsOneWidget);
    expect(find.text('Attempted: 2'), findsOneWidget);
    expect(find.text('Attempted: 0'), findsNWidgets(5));
    expect(find.text('Best score: —'), findsNWidgets(5));
    expect(find.text('Last score: —'), findsNWidgets(5));
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const Key('quiz-progress-obstacle-avoidance')))
            .value,
        0.4);
    expect(find.text('Quiz: Not attempted'), findsWidgets);
    client = MockClient((_) async => http.Response(
        jsonEncode({
          'topics': [
            {
              'id': 'zero',
              'title': 'Zero score',
              'summary': 'Lesson',
              'quiz_progress': {
                'attempt_count': 1,
                'latest_score': 0,
                'best_score': 0,
                'temporary': true
              }
            }
          ]
        }),
        200));
    CourseContentApi.testClient = client;
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(MaterialApp(
        home: CourseCatalogPage(user: _student, onLogout: _logout)));
    await tester.pumpAndSettle();
    expect(find.text('Last score: 0%'), findsOneWidget);
    expect(find.text('Best score: 0%'), findsOneWidget);
    expect(find.text('Attempted: 1'), findsOneWidget);
    expect(find.text('Temporary demo progress'), findsOneWidget);
    expect(find.text('Quiz: Not attempted'), findsNothing);
  });

  testWidgets('Previous and Next walk the topic in reading order',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CourseTopicPage(
            topicId: 'obstacle-avoidance', user: _student, onLogout: _logout)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('previous-section')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('next-section')));
    await tester.pumpAndSettle();
    expect(find.text('Next: Practice'), findsOneWidget);
    await tester.tap(find.byKey(const Key('next-section')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LessonReader>(find.byKey(const Key('course-section-html')))
            .html,
        contains('Try the exercise'));
    await tester.ensureVisible(find.byKey(const Key('previous-section')));
    await tester.pumpAndSettle();
    expect(find.text('Previous: Lesson'), findsOneWidget);
    expect(find.text('Next: Quiz'), findsOneWidget);
    await tester.tap(find.byKey(const Key('next-section')));
    await tester.pumpAndSettle();
    expect(find.text('Which direction?'), findsOneWidget);
    expect(find.byKey(const Key('next-section')), findsNothing);
  });

  testWidgets(
      'exercises remain readable and quiz score appears only after submission',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CourseTopicPage(
            topicId: 'obstacle-avoidance', user: _student, onLogout: _logout)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exercises'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LessonReader>(find.byKey(const Key('course-section-html')))
            .html,
        contains('Try the exercise'));
    expect(find.textContaining('does not affect'), findsOneWidget);
    await tester.tap(find.text('Quiz'));
    await tester.pumpAndSettle();
    expect(find.text('Which direction?'), findsOneWidget);
    expect(find.textContaining('Score:'), findsNothing);
    expect(find.text('Check answer'), findsNothing);
    // The whole topic page scrolls, so bring each control into view first.
    await tester.ensureVisible(find.text('Submit quiz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit quiz'));
    await tester.pump();
    expect(find.text('Answer question 1 before submitting.'), findsOneWidget);
    expect(find.text('QUESTION 1 OF 1'), findsOneWidget);
    expect(find.text('0 of 1 answered'), findsOneWidget);
    await tester.ensureVisible(find.text('B. Forward'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B. Forward'));
    await tester.pump();
    expect(find.text('1 of 1 answered'), findsOneWidget);
    await tester.ensureVisible(find.text('Submit quiz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit quiz'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Score: 100%'), findsOneWidget);
    expect(find.textContaining('Score saved.'), findsOneWidget);
  });
}
