import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iuse_demo/main.dart' as app;
import 'package:iuse_demo/screens/login_page.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/state/learning_progress_store.dart';
import 'package:iuse_demo/state/progress_storage_base.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('an expired sign-in explains itself and returns to sign-in',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'auth_session_token': 'old'});
    // The saved sign-in is accepted once, then every request is rejected,
    // as when the 12-hour session ends while a page is open.
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/me')) {
        return http.Response(
          jsonEncode({'id': 'u1', 'login_id': 'student2', 'role': 'student'}),
          200,
        );
      }
      return http.Response(
          jsonEncode({'error': 'Authentication required.'}), 401);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const app.MyApp(forceFreshLoginOnStart: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('session-expired-dialog')), findsOneWidget);
      expect(find.textContaining('Your latest code is kept on this device'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('session-expired-sign-in')));
      await tester.pumpAndSettle();
    }, () => client);

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byKey(const Key('session-expired-dialog')), findsNothing);
    expect(AuthApi.sessionExpired.value, isFalse);
  });

  test('code from an earlier assignment version is kept, never reloaded',
      () async {
    final store = LearningProgressStore();
    await store.load(storage: InMemoryProgressStorage());
    await store.saveDraft(1, 16, 'old version work');

    // The new version's editor must not receive the old code.
    expect(store.draftFor(1, 17), isNull);
    expect(store.earlierDraftFor(1, 17), 'old version work');

    // Editing the new version keeps the earlier code available to copy.
    await store.saveDraft(1, 17, 'new start');
    expect(store.draftFor(1, 17), 'new start');
    expect(store.earlierDraftFor(1, 17), 'old version work');

    await store.dismissEarlierDraft(1, 17);
    expect(store.earlierDraftFor(1, 17), isNull);
    expect(store.draftFor(1, 17), 'new start');
  });
}
