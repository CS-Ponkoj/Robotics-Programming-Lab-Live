import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iuse_demo/screens/sign_in_history_page.dart';
import 'package:iuse_demo/screens/student_accounts_page.dart';
import 'package:iuse_demo/theme/app_theme.dart';

void main() {
  testWidgets('sign-in history shows each session and its state',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Uri? requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response(
        jsonEncode({
          'items': [
            {
              'session_id': 'a',
              'user_id': 'u1',
              'login_id': 'dave',
              'role': 'student',
              'signed_in_at': '2026-10-22T10:00:00Z',
              'last_active_at': '2026-10-22T10:30:00Z',
              'signed_out_at': null,
              'expires_at': '2026-10-22T22:00:00Z',
              'state': 'active',
              'device': 'phone',
            },
            {
              'session_id': 'b',
              'user_id': 'u1',
              'login_id': 'dave',
              'role': 'student',
              'signed_in_at': '2026-10-21T09:00:00Z',
              'last_active_at': '2026-10-21T09:40:00Z',
              'signed_out_at': '2026-10-21T09:45:00Z',
              'expires_at': '2026-10-21T21:00:00Z',
              'state': 'signed_out',
            },
          ],
          'total': 2,
          'page': 1,
          'page_size': 50,
        }),
        200,
      );
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const SignInHistoryPage(userId: 'u1', loginId: 'dave'),
      ));
      await tester.pumpAndSettle();
    }, () => client);

    expect(requested?.queryParameters['user_id'], 'u1');
    expect(find.text('dave: sign-ins'), findsOneWidget);
    expect(find.byKey(const Key('sign-in-table')), findsOneWidget);
    expect(find.text('Still signed in'), findsOneWidget);
    expect(find.text('Mobile'), findsOneWidget);
    expect(find.text('Not recorded'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('clicking an account in Manage accounts opens its sign-ins',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? historyUser;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/admin/sign-in-history')) {
        historyUser = request.url.queryParameters['user_id'];
        return http.Response(
          jsonEncode({'items': [], 'total': 0, 'page': 1, 'page_size': 50}),
          200,
        );
      }
      if (path.endsWith('/instructors')) {
        return http.Response(jsonEncode({'instructors': []}), 200);
      }
      return http.Response(
        jsonEncode({
          'students': [
            {
              'id': 's1',
              'login_id': 'dave',
              'role': 'student',
              'is_active': true,
            },
          ],
        }),
        200,
      );
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const StudentAccountsPage(),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-row-dave')));
      await tester.pumpAndSettle();
    }, () => client);

    expect(historyUser, 's1');
    expect(find.text('dave: sign-ins'), findsOneWidget);
    expect(find.text('This account has not signed in yet.'), findsOneWidget);
  });

  testWidgets('sign-in history explains a permission error', (tester) async {
    final client = MockClient((_) async => http.Response('{}', 403));
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const SignInHistoryPage(userId: 'u1', loginId: 'dave'),
      ));
      await tester.pumpAndSettle();
    }, () => client);

    expect(find.text('Only instructors can view sign-in history.'),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
