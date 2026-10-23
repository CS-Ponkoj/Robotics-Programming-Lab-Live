import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iuse_demo/screens/student_accounts_page.dart';
import 'package:iuse_demo/theme/app_theme.dart';

void main() {
  test('credentials message has the site, login ID, and password', () {
    final message = credentialsMessage(
      loginId: 'stu-042',
      password: 'Temp-Pass-123',
      appUrl: 'https://rpl.ponkoj.com/app',
    );
    expect(message, contains('Site: https://rpl.ponkoj.com/app'));
    expect(message, contains('Login ID: stu-042'));
    expect(message, contains('Temporary password: Temp-Pass-123'));
  });

  testWidgets('new account dialog copies the generated credentials',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final client = MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response(
          jsonEncode({
            'user': {'id': 's9', 'login_id': 'stu-099', 'role': 'student'},
            'temporary_password': 'Gen-Pass-9876',
            'email_sent': false,
          }),
          201,
        );
      }
      if (request.url.path.endsWith('/instructors')) {
        return http.Response(jsonEncode({'instructors': []}), 200);
      }
      if (request.url.path.endsWith('/email/status')) {
        return http.Response(jsonEncode({'configured': false}), 200);
      }
      return http.Response(jsonEncode({'students': []}), 200);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(), home: const StudentAccountsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-account-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Login ID'), 'stu-099');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Account created'), findsOneWidget);
      await tester.tap(find.byKey(const Key('copy-credentials')));
      await tester.pumpAndSettle();
    }, () => client);

    expect(clipboard, contains('Login ID: stu-099'));
    expect(clipboard, contains('Temporary password: Gen-Pass-9876'));
    expect(find.text('Copied'), findsOneWidget);
  });
}

