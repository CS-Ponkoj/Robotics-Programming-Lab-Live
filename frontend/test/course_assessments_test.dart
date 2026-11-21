import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/screens/course_content_page.dart';
import 'package:iuse_demo/services/course_content_api.dart';
import 'package:iuse_demo/theme/app_theme.dart';

const _student = AuthenticatedUser(
    id: 'student-1', loginId: 'student', role: 'student');
Future<void> _logout() async {}

Map<String, dynamic> _questions(String prefix) => {
      'questions': [
        for (final id in ['q1', 'q2'])
          {
            'id': id,
            'prompt': '$prefix $id?',
            'options': [
              {'id': 'A', 'text': '$id first'},
              {'id': 'B', 'text': '$id second'},
            ],
          },
      ],
    };

MockClient _server({required bool pretestTaken, List<String>? log}) =>
    MockClient((request) async {
      final path = request.url.path;
      log?.add('${request.method} $path');
      Map<String, dynamic>? body;
      if (path.endsWith('/contents/ros2')) {
        body = {
          'id': 'ros2',
          'title': 'ROS 2',
          'summary': 'Robots',
          'sections': [
            {'id': 'lesson', 'title': 'Lesson', 'kind': 'lesson'},
            {'id': 'quiz', 'title': 'Quiz', 'kind': 'quiz'},
            {'id': 'pretest', 'title': 'Pre-test', 'kind': 'pretest'},
          ],
        };
      } else if (path.endsWith('/contents/ros2/pretest')) {
        body = {'taken': pretestTaken, 'score_percent': pretestTaken ? 40 : null};
      } else if (path.endsWith('/sections/pretest')) {
        body = {
          'id': 'pretest', 'title': 'Pre-test', 'kind': 'pretest',
          'version': 'pre-v', 'html': '', ..._questions('Before'),
        };
      } else if (path.endsWith('/pretest/submit')) {
        body = {'score_percent': 50, 'correct_count': 1, 'total_questions': 2, 'saved': true};
      } else if (path.endsWith('/sections/lesson')) {
        body = {'id': 'lesson', 'title': 'Lesson', 'kind': 'lesson',
          'html': '<p>Lesson text</p>', 'questions': []};
      } else if (path.endsWith('/sections/quiz')) {
        body = {'id': 'quiz', 'title': 'Quiz', 'kind': 'quiz',
          'version': 'quiz-v', 'html': '', ..._questions('After')};
      } else if (path.endsWith('/quiz/attempts')) {
        body = {'attempts': [], 'learning_score': null};
      } else if (path.endsWith('/quiz/submit')) {
        body = {
          'score_percent': 100, 'correct_count': 2, 'total_questions': 2,
          'saved': true, 'scored': false, 'learning_score': 50,
          'results': [
            for (final id in ['q1', 'q2'])
              {'question_id': id, 'correct': true, 'correct_option': 'A'},
          ],
        };
      }
      return body == null
          ? http.Response('Not found', 404)
          : http.Response(jsonEncode(body), 200);
    });

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: CourseTopicPage(topicId: 'ros2', user: _student, onLogout: _logout)));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => CourseContentApi.testClient = null);

  testWidgets('a topic opens on its untaken pre-test, which shows only a score',
      (tester) async {
    final log = <String>[];
    CourseContentApi.testClient = _server(pretestTaken: false, log: log);
    await _open(tester);
    expect(find.byKey(const Key('pretest-intro')), findsOneWidget);
    expect(find.text('Before q1?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('submit-pretest')));
    await tester.pumpAndSettle();
    expect(find.text('Answer every question before submitting.'), findsOneWidget);
    expect(log.where((l) => l.endsWith('/pretest/submit')), isEmpty);
    await tester.tap(find.text('A. q1 first'));
    await tester.tap(find.text('B. q2 second'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submit-pretest')));
    await tester.pumpAndSettle();
    expect(find.text('Your pre-test score: 50%'), findsOneWidget);
    // No answers or per-question marks after a pre-test.
    expect(find.text('Correct'), findsNothing);
    expect(find.textContaining('correct answer'), findsNothing);
  });

  testWidgets('a taken pre-test opens the lesson and shows the earlier score',
      (tester) async {
    CourseContentApi.testClient = _server(pretestTaken: true);
    await _open(tester);
    expect(find.byKey(const Key('course-section-html')), findsOneWidget);
    expect(find.byKey(const Key('pretest-intro')), findsNothing);
    await tester.tap(find.text('Pre-test'));
    await tester.pumpAndSettle();
    expect(find.text('Your pre-test score: 40%'), findsOneWidget);
    expect(find.byKey(const Key('submit-pretest')), findsNothing);
  });

  testWidgets('the quiz explains that the first attempt is the score',
      (tester) async {
    CourseContentApi.testClient = _server(pretestTaken: true);
    await _open(tester);
    await tester.tap(find.text('Quiz'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quiz-score-rule')), findsOneWidget);
    await tester.tap(find.text('A. q1 first'));
    await tester.tap(find.text('A. q2 first'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit quiz'));
    await tester.tap(find.text('Submit quiz'));
    await tester.pumpAndSettle();
    expect(find.text('Practice retake. Your quiz score stays 50% (your first attempt).'),
        findsOneWidget);
  });
}
