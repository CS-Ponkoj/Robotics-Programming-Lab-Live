import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/screens/research_dashboard_page.dart';
import 'package:iuse_demo/theme/app_theme.dart';

Map<String, dynamic> _studentData() => {
      'summary': {
        'participant_code': 'P-042',
        'study_sessions': 2,
        'active_seconds': 3720,
        'attempts': 3,
        'assignments_completed': 1,
        'average_score': 72.5,
        'best_score': 100,
        'hints_requested': 1,
        'solutions_revealed': 0,
        'ai_tutor_uses': 0,
      },
      'assignment_summaries': [
        {
          'assignment_id': 1,
          'assignment_version': 3,
          'assignment_title': 'Obstacle avoidance',
          'status': 'completed',
          'attempt_count': 3,
          'attempts_to_first_success': 3,
          'first_score': 40,
          'latest_score': 100,
          'best_score': 100,
          'score_improvement': 60,
          'public_test_pass_percentage': 100,
          'total_active_seconds': 1800,
          'active_seconds_to_completion': 1500,
          'elapsed_seconds_to_completion': 3600,
          'time_availability': 'available',
          'completion_time_availability': 'available',
          'first_attempt_at': '2026-08-05T10:05:00Z',
          'last_attempt_at': '2026-08-05T10:30:00Z',
          'syntax_error_count': 0,
          'runtime_error_count': 1,
          'timeout_count': 0,
          'rejection_count': 0,
          'excessive_output_count': 0,
          'oversized_submission_count': 0,
          'built_in_hint_count': 1,
          'ai_interaction_count': 0,
          'highest_hint_level': 2,
        },
      ],
      'attempts': [
        {
          'assignment_id': 1,
          'assignment_version': 3,
          'mode': 'submit',
          'score': 100,
          'passed': true,
          'execution_status_label': 'Completed',
          'created_at': '2026-08-05T10:30:00Z',
        },
      ],
      'metric_catalog': {
        'catalog_version': '1.1',
        'metrics': [
          {
            'metric_id': 'OUT-01',
            'name': 'Assignments completed',
            'definition': 'Published assignment versions completed.',
          },
        ],
      },
      'events': [
        {
          'event_type': 'assignment_opened',
          'assignment_id': 1,
          'created_at': '2026-08-05T10:00:00Z',
        },
      ],
    };

Widget _app(Widget home) => MaterialApp(
      theme: buildAppTheme(),
      home: home,
    );

void main() {
  testWidgets('student sees only participant progress and recent attempts',
      (tester) async {
    await tester.pumpWidget(
      _app(StudentResearchPage(initialData: _studentData())),
    );
    await tester.pumpAndSettle();

    expect(find.text('My study progress'), findsOneWidget);
    expect(find.textContaining('Participant P-042'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('100%'), findsWidgets);
    expect(find.text('Assignment analytics'), findsOneWidget);
    expect(find.textContaining('Obstacle avoidance'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Attempt #1'), 300);
    expect(find.textContaining('Attempt #1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Phase 1 metric definitions'),
      300,
    );
    expect(find.text('Phase 1 metric definitions'), findsOneWidget);
    expect(find.textContaining('login'), findsNothing);
    expect(find.textContaining('password'), findsNothing);
  });

  testWidgets('instructor dashboard is responsive and uses participant codes',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        InstructorResearchDashboard(
          initialParticipants: [
            {
              'participant_code': 'P-042',
              'student_id': 'student-uuid',
              'active_seconds': 30,
              'attempts': 3,
              'assignments_completed': 1,
              'best_score': 100,
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Research study dashboard'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('research-participant-P-042')),
      300,
    );
    expect(find.text('P-042'), findsOneWidget);
    expect(find.textContaining('3 attempts'), findsOneWidget);
    expect(find.text('<1m'), findsWidgets);
    expect(find.byKey(const Key('research-export-menu')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('instructor participant detail shows assignment and attempts',
      (tester) async {
    await tester.pumpWidget(
      _app(
        ResearchStudentDetailPage(
          studentId: 'student-uuid',
          initialData: _studentData(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Participant detail'), findsOneWidget);
    expect(find.text('P-042'), findsOneWidget);
    expect(find.text('Assignment analytics'), findsOneWidget);
    expect(find.textContaining('Obstacle avoidance'), findsOneWidget);
  });
}
