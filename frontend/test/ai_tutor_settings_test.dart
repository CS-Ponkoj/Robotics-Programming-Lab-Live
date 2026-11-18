import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/screens/ai_tutor_settings_page.dart';
import 'package:iuse_demo/theme/app_theme.dart';

Map<String, dynamic> status({bool enabled = false, bool key = false}) => {
      'enabled': enabled,
      'daily_limit': 20,
      'key_configured': key,
      'assignments': [
        {
          'id': 7,
          'title': 'Stop Before the Wall',
          'version': 3,
          'reviewed': false
        },
      ],
    };

void main() {
  testWidgets('shows each gate and saves the course switch', (tester) async {
    final saved = <(bool, int)>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: AiTutorSettingsPage(
        load: (_) async => status(),
        save: (_, {required enabled, required dailyLimit}) async {
          saved.add((enabled, dailyLimit));
          return status(enabled: enabled);
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not configured'), findsOneWidget);
    expect(
        find.textContaining('waiting for instructor review'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('ai-course-switch')))
          .value,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('ai-course-switch')));
    await tester.enterText(find.byKey(const Key('ai-daily-limit')), '0');
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pump();
    expect(saved, isEmpty);
    expect(find.textContaining('from 1 to 200'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('ai-daily-limit')), '15');
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();
    expect(saved, [(true, 15)]);
    expect(find.text('Saved.'), findsOneWidget);
  });

  testWidgets('fits a phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: AiTutorSettingsPage(
        load: (_) async => status(key: true),
        save: (_, {required enabled, required dailyLimit}) async => status(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('never shown'), findsOneWidget);
  });
}
