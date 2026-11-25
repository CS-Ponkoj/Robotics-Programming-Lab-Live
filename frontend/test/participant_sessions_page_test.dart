import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/screens/participant_sessions_page.dart';

const _participants = [
  {
    'id': 'u1',
    'participant_code': 'P-001',
    'login_id': 'alex',
    'feedback_mode': 'tdd_ai',
  },
  {
    'id': 'u2',
    'participant_code': 'P-002',
    'login_id': 'sam',
    'feedback_mode': 'tdd',
  },
];

Map<String, dynamic> _payload(String id) => {
      'participant': {
        'id': id,
        'participant_code': id == 'u1' ? 'P-001' : 'P-002',
        'login_id': id == 'u1' ? 'alex' : 'sam',
        'feedback_mode': id == 'u1' ? 'tdd_ai' : 'tdd',
      },
      'columns': [
        {'key': 'time', 'label': 'Time (UTC)'},
        {'key': 'activity', 'label': 'Activity'},
        {'key': 'assignment', 'label': 'Assignment'},
        {'key': 'result', 'label': 'Result'},
        {'key': 'details', 'label': 'Details'},
        {'key': 'attempt_id', 'label': 'Attempt'},
      ],
      'sessions': [
        {
          'number': 1,
          'started_at': '2026-11-25T08:00:00+00:00',
          'last_active_at': '2026-11-25T08:01:00+00:00',
          'ended_at': '',
          'active_seconds': 30,
          'rows': [],
        },
        {
          'number': 2,
          'started_at': '2026-11-25T09:00:00+00:00',
          'last_active_at': '2026-11-25T09:20:00+00:00',
          'ended_at': '',
          'active_seconds': 1200,
          'rows': [
            {
              'time': '2026-11-25T09:01:00+00:00',
              'activity': 'Test run',
              'assignment': 'Assignment 1',
              'result': '91%',
              'details': 'Checks 20/21',
              'attempt_id': 'a1',
            },
            {
              'time': '2026-11-25T09:02:00+00:00',
              'activity': 'Tutor question',
              'assignment': 'Assignment 1',
              'result': 'level 1, AI',
              'details': 'Q: "Why does it stop?" A: Look at the comparison.',
              'attempt_id': 'a1',
            },
          ],
        },
      ],
      'outside_sessions': [],
    };

void main() {
  testWidgets('shows each session as its own table with the login ID',
      (tester) async {
    final loaded = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: ParticipantSessionsPage(
        participants: _participants,
        initialParticipantId: 'u1',
        loadSessions: (id) async {
          loaded.add(id);
          return _payload(id);
        },
        downloadSessions: (id, label) async => true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(loaded, ['u1']);
    expect(find.text('alex'), findsOneWidget);
    expect(find.text('TDD + AI'), findsOneWidget);
    expect(find.textContaining('Session 2 · 2 activities'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.textContaining('Session 1 · 0 activities'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Session 1 · 0 activities'), findsOneWidget);
    expect(find.text('Test run'), findsOneWidget);
    expect(find.textContaining('Why does it stop?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sessions-download')));
    await tester.pumpAndSettle();
    expect(find.text('Downloaded sessions_alex.csv'), findsOneWidget);
  });

  testWidgets('switching participant loads their sessions', (tester) async {
    final loaded = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: ParticipantSessionsPage(
        participants: _participants,
        loadSessions: (id) async {
          loaded.add(id);
          return _payload(id);
        },
        downloadSessions: (id, label) async => true,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sessions-participant')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('sam · P-002 · TDD').last);
    await tester.pumpAndSettle();
    expect(loaded, ['u1', 'u2']);
    expect(find.text('sam'), findsOneWidget);
  });

  testWidgets('a failed load explains and retries; phone width fits',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var fail = true;
    await tester.pumpWidget(MaterialApp(
      home: ParticipantSessionsPage(
        participants: _participants,
        loadSessions: (id) async {
          if (fail) throw Exception('Instructor authentication required.');
          return _payload(id);
        },
        downloadSessions: (id, label) async => true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sessions-error')), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('alex'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
