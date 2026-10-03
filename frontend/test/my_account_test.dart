import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/screens/my_account_page.dart';
import 'package:iuse_demo/screens/student_accounts_page.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/landing_page_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _student = AuthenticatedUser(
  id: 'student-1',
  loginId: 'stu-042',
  role: 'student',
  participantCode: 'P-042',
);

Widget _page({required Future<void> Function() onSignedOut}) => MaterialApp(
      theme: buildAppTheme(),
      home: MyAccountPage(user: _student, onSignedOut: onSignedOut),
    );

Future<void> _fill(WidgetTester tester, String current, String next,
    {String? confirm}) async {
  await tester.enterText(
      find.byKey(const Key('current-password-field')), current);
  await tester.enterText(find.byKey(const Key('new-password-field')), next);
  await tester.enterText(
      find.byKey(const Key('confirm-password-field')), confirm ?? next);
  await tester.ensureVisible(find.byKey(const Key('change-password-button')));
  await tester.tap(find.byKey(const Key('change-password-button')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The whole page fits, so taps reach the Change password button.
  Future<void> tallWindow(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('shows account details with a read-only participant code',
      (tester) async {
    await tallWindow(tester);
    await tester.pumpWidget(_page(onSignedOut: () async {}));

    expect(find.text('stu-042'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('P-042'), findsOneWidget);
    expect(find.textContaining('assigned by your instructor'), findsOneWidget);
    // Only the three password fields are editable.
    expect(find.byType(TextFormField), findsNWidgets(3));
  });

  testWidgets('validates the new password before contacting the server',
      (tester) async {
    await tallWindow(tester);
    var requests = 0;
    final client = MockClient((_) async {
      requests += 1;
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_page(onSignedOut: () async {}));
      await _fill(tester, 'Current-5827', 'short');
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      await _fill(tester, 'Current-5827', 'Current-5827');
      expect(find.textContaining('different from the current'), findsOneWidget);
      await _fill(tester, 'Current-5827', 'Next-Pass-5827',
          confirm: 'Other-Pass-5827');
      expect(find.text('Passwords do not match.'), findsOneWidget);
    }, () => client);
    expect(requests, 0);
  });

  testWidgets('shows the server error for a wrong current password',
      (tester) async {
    await tallWindow(tester);
    var signedOut = false;
    final client = MockClient((_) async => http.Response(
        jsonEncode({'error': 'Current password is incorrect.'}), 400));
    await http.runWithClient(() async {
      await tester.pumpWidget(_page(onSignedOut: () async => signedOut = true));
      await _fill(tester, 'Wrong-5827', 'Next-Pass-5827');
    }, () => client);

    expect(find.byKey(const Key('change-password-error')), findsOneWidget);
    expect(find.text('Current password is incorrect.'), findsOneWidget);
    expect(signedOut, isFalse);
  });

  testWidgets('a successful change signs the user out', (tester) async {
    await tallWindow(tester);
    var signedOut = false;
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({'password_changed': true, 'login_required': true}), 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_page(onSignedOut: () async => signedOut = true));
      await _fill(tester, 'Current-5827', 'Next-Pass-5827');
      expect(find.byKey(const Key('password-changed-dialog')), findsOneWidget);
      await tester.tap(find.text('Sign in again'));
      await tester.pumpAndSettle();
    }, () => client);

    expect(sent, {
      'current_password': 'Current-5827',
      'new_password': 'Next-Pass-5827',
    });
    expect(signedOut, isTrue);
  });

  testWidgets('Edit details is offered for students but not instructors',
      (tester) async {
    await tallWindow(tester);
    final client = MockClient((request) async => http.Response(
        jsonEncode(request.url.path.endsWith('/instructors')
            ? {
                'instructors': [
                  {
                    'id': 'i1',
                    'login_id': 'prof',
                    'role': 'instructor',
                    'is_active': true
                  },
                ],
              }
            : {
                'students': [
                  {
                    'id': 's1',
                    'login_id': 'stu-042',
                    'role': 'student',
                    'is_active': true,
                    'participant_code': 'P-042'
                  },
                ],
              }),
        200));
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(), home: const StudentAccountsPage()));
      await tester.pumpAndSettle();
    }, () => client);

    final menus = find.byTooltip('Account actions');
    expect(menus, findsNWidgets(2));
    // Rows are sorted by login ID: prof (instructor), then stu-042.
    for (final (index, expected) in [(0, findsNothing), (1, findsOneWidget)]) {
      await tester.tap(menus.at(index));
      await tester.pumpAndSettle();
      expect(find.text('Reset password'), findsOneWidget);
      expect(find.byKey(const Key('edit-account-menu-item')), expected);
      await tester.tapAt(const Offset(5, 1300));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('account menu offers My account except in the demo',
      (tester) async {
    await tallWindow(tester);
    Future<void> logout() async {}
    for (final (user, expected) in [
      (_student, findsOneWidget),
      (
        const AuthenticatedUser(
            id: 'demo', loginId: 'demo', role: 'student', isDemo: true),
        findsNothing
      ),
    ]) {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(appBar: LandingPageHeader(user: user, onLogout: logout)),
      ));
      await tester.tap(find.byTooltip('Account menu'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my-account-menu-item')), expected);
      await tester.tapAt(const Offset(5, 500));
      await tester.pumpAndSettle();
    }
  });
}
