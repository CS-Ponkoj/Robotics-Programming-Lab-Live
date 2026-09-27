import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iuse_demo/screens/course_content_page.dart';
import 'package:iuse_demo/services/course_content_api.dart';

void main() {
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

  testWidgets('all six topics appear at mobile width and open a lesson',
      (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: CourseCatalogPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('content-topic-obstacle-avoidance')),
        findsOneWidget);
    expect(find.byKey(const Key('content-topic-hybrid-navigation-and-gps')),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('content-topic-obstacle-avoidance')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<HtmlWidget>(find.byKey(const Key('course-section-html')))
            .html,
        contains('robot’s turn is π radians'));
    expect(find.text('Exercises'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'exercises remain readable and quiz score appears only after submission',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: CourseTopicPage(topicId: 'obstacle-avoidance')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exercises'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<HtmlWidget>(find.byKey(const Key('course-section-html')))
            .html,
        contains('Try the exercise'));
    expect(find.textContaining('does not affect'), findsOneWidget);
    await tester.tap(find.text('Quiz'));
    await tester.pumpAndSettle();
    expect(find.text('Which direction?'), findsOneWidget);
    expect(find.textContaining('Score:'), findsNothing);
    expect(find.text('Check answer'), findsNothing);
    await tester.tap(find.text('Submit quiz'));
    await tester.pump();
    expect(find.textContaining('Answer all'), findsOneWidget);
    await tester.tap(find.text('B. Forward'));
    await tester.pump();
    await tester.tap(find.text('Submit quiz'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Score: 100%'), findsOneWidget);
    expect(find.textContaining('Score saved.'), findsOneWidget);
  });
}
