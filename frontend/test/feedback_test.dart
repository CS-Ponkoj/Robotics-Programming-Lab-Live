import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iuse_demo/screens/feedback_inbox_page.dart';
import 'package:iuse_demo/state/feedback_page_tracker.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/feedback_button.dart';

void main() {
  testWidgets('feedback dialog sends the page, category, and message',
      (tester) async {
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.url.path, endsWith('/feedback'));
      return http.Response(jsonEncode({'id': '1', 'status': 'received'}), 201);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: FeedbackDialog(page: 'Assignment 2')),
      ));
      expect(find.text('Page: Assignment 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('feedback-send')));
      await tester.pump();
      expect(find.byKey(const Key('feedback-error')), findsOneWidget);
      expect(sent, isNull);

      await tester.enterText(
          find.byKey(const Key('feedback-message')), 'Diagram is missing');
      await tester.tap(find.byKey(const Key('feedback-send')));
      await tester.pumpAndSettle();
    }, () => client);

    expect(sent, {
      'page': 'Assignment 2',
      'category': 'bug',
      'message': 'Diagram is missing',
    });
  });

  testWidgets('feedback dialog shows server errors and stays open',
      (tester) async {
    final client = MockClient((_) async => http.Response('', 429));
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: FeedbackDialog(page: 'Home: Contents')),
      ));
      await tester.enterText(find.byKey(const Key('feedback-message')), 'Hi');
      await tester.tap(find.byKey(const Key('feedback-send')));
      await tester.pumpAndSettle();
    }, () => client);

    expect(find.textContaining('Too many feedback messages'), findsOneWidget);
    expect(find.byKey(const Key('feedback-send')), findsOneWidget);
  });

  testWidgets('page tracker reports named pages and falls back to home',
      (tester) async {
    final tracker = FeedbackPageTracker()..homeLabel = 'Home: Assignments';
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [tracker],
      home: const Scaffold(body: Text('home')),
    ));
    expect(tracker.currentPage, 'Home: Assignments');

    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(arguments: FeedbackPage('My account')),
      builder: (_) => const Scaffold(body: Text('account')),
    ));
    await tester.pumpAndSettle();
    expect(tracker.currentPage, 'My account');

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tracker.currentPage, 'Home: Assignments');
  });

  testWidgets('instructor inbox lists feedback and marks it resolved',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var status = 'new';
    String? patched;
    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        patched = (jsonDecode(request.body) as Map)['status'] as String;
        status = patched!;
        return http.Response('{}', 200);
      }
      final items =
          request.url.queryParameters['status'] == 'new' && status != 'new'
              ? []
              : [
                  {
                    'id': 'f1',
                    'page': 'Assignment 5',
                    'category': 'bug',
                    'message': 'ROS build hangs',
                    'status': status,
                    'sender_role': 'student',
                    'sender_login_id': 'dave',
                    'created_at': '2026-10-22T10:00:00Z',
                    'resolved_at': null,
                  }
                ];
      return http.Response(
        jsonEncode({
          'items': items,
          'total': items.length,
          'new_count': status == 'new' ? 1 : 0,
          'page': 1,
          'page_size': 50,
        }),
        200,
      );
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const FeedbackInboxPage(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('ROS build hangs'), findsOneWidget);
      expect(find.textContaining('Login ID: dave'), findsOneWidget);
      expect(find.text('New (1)'), findsOneWidget);

      await tester.tap(find.text('Mark resolved'));
      await tester.pumpAndSettle();
    }, () => client);

    expect(patched, 'resolved');
    expect(find.text('No feedback here yet.'), findsOneWidget);
    expect(find.text('New (0)'), findsOneWidget);
  });

  testWidgets('phones get a full-screen form that sends feedback',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'id': '1', 'status': 'received'}), 201);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showFeedbackDialog(context, 'Home: Contents'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(feedbackFormOpen.value, isTrue);

      await tester.enterText(
          find.byKey(const Key('feedback-message')), 'Quiz button overlaps');
      await tester.tap(find.byKey(const Key('feedback-send')));
      await tester.pumpAndSettle();
    }, () => client);

    expect(sent?['page'], 'Home: Contents');
    expect(sent?['message'], 'Quiz button overlaps');
    expect(find.byType(Dialog), findsNothing);
    expect(feedbackFormOpen.value, isFalse);
    expect(find.text('Thank you. Your feedback was sent.'), findsOneWidget);
  });
}
