import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iuse_demo/screens/instructor_assignment_admin.dart';
import 'package:iuse_demo/theme/app_theme.dart';

void main() {
  testWidgets('Instructor Studio shows tool cards, not the assignment list',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'assignments': [
              {
                'id': 1,
                'title': 'Assignment 1: Bug algorithm',
                'status': 'published',
                'version': 14,
                'language': 'python',
                'slug': 'robotics-assignment-1',
              },
            ],
          }),
          200,
        ));
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const InstructorAssignmentAdmin(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Instructor Studio'), findsWidgets);
      for (final title in [
        'Assignment management',
        'Manage accounts',
        'Research study dashboard',
        'Feedback',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.byKey(const Key('create-assignment-button')), findsNothing);
      expect(find.text('Sign-in history'), findsNothing);

      await tester.tap(find.byKey(const Key('studio-assignments-card')));
      await tester.pumpAndSettle();
    }, () => client);

    expect(find.byKey(const Key('create-assignment-button')), findsOneWidget);
    expect(find.text('Manage versioned assignments'), findsOneWidget);
  });
}
