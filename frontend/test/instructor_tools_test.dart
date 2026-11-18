import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/screens/assignment_insights_page.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/sim_world_editor.dart';

Map<String, dynamic> world() => {
      'walls': [
        [1.2, -3.0, 1.2, 3.0],
      ],
      'robot': {'x': 0.0, 'y': 0.0, 'theta': 0.0, 'radius': 0.15},
      'duration_seconds': 8.0,
      'wall_move': {
        'wall': 0,
        'after_stopped_seconds': 1.0,
        'dx': 1.5,
        'dy': 0.0
      },
    };

void main() {
  group('simulation world editor', () {
    test('finds the problems the server would reject', () {
      expect(simWorldProblems(world()), isEmpty);
      expect(simWorldProblems({...world(), 'walls': []}),
          contains('Add at least one wall.'));
      expect(
        simWorldProblems({
          ...world(),
          'walls': [
            [1.0, 2.0, 30.0, 1.0],
          ],
        }),
        contains('Wall 1 needs four numbers from -20 to 20 m.'),
      );
      expect(simWorldProblems({...world(), 'duration_seconds': 9}),
          contains('Duration must be more than 0 and at most 8.0 s.'));
      expect(
        simWorldProblems({
          ...world(),
          'wall_move': {
            'wall': 3,
            'after_stopped_seconds': 1.0,
            'dx': 1,
            'dy': 0
          },
        }),
        contains('The moving wall must be one of the walls above.'),
      );
    });

    testWidgets('edits walls with a live preview and returns the world',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? result;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  result = await editSimWorld(context, world()),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sim-world-preview')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sim-world-add-wall')));
      await tester.pump();
      // A bad duration disables Use this world until it is fixed.
      await tester.enterText(
          find.widgetWithText(TextField, 'duration (s)'), '12');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sim-world-apply')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
          find.widgetWithText(TextField, 'duration (s)'), '6');
      await tester.pump();
      await tester.tap(find.byKey(const Key('sim-world-apply')));
      await tester.pumpAndSettle();
      expect(result!['walls'], hasLength(2));
      expect(result!['duration_seconds'], 6);
      expect(result!['wall_move'], isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('assignment insights', () {
    Future<void> pumpInsights(WidgetTester tester, Map<String, dynamic> data,
        {Size size = const Size(1200, 900)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: AssignmentInsightsPage(
          assignmentId: 7,
          title: 'Stop Before the Wall',
          load: (_, __) async => data,
        ),
      ));
      await tester.pumpAndSettle();
    }

    final data = {
      'version': 3,
      'students_attempted': 4,
      'students_passed': 1,
      'attempts': 9,
      'median_attempts_to_pass': 3,
      'median_minutes_to_pass': 12.5,
      'checks': [
        {
          'test_id': 'stop-wall-0-3',
          'label': 'Stops at 0.3 m',
          'students_failing': 3
        },
      ],
      'observed_patterns': [
        {'hint_key': 'stops-too-late', 'students': 2},
      ],
      'misconceptions': [],
      'simulation_outcomes': [
        {'outcome': 'collided', 'runs': 5},
      ],
    };

    testWidgets('names where students get stuck in plain words',
        (tester) async {
      await pumpInsights(tester, data);
      expect(find.text('Stops at 0.3 m'), findsOneWidget);
      expect(find.text('3 of 4'), findsOneWidget);
      expect(find.text('Keeps driving when the wall is close'), findsOneWidget);
      expect(find.text('Hit the wall'), findsOneWidget);
      expect(find.text('12.5 min'), findsOneWidget);
    });

    testWidgets('fits a phone and handles no attempts', (tester) async {
      await pumpInsights(
        tester,
        {
          ...data,
          'students_attempted': 0,
          'students_passed': 0,
          'attempts': 0,
          'median_attempts_to_pass': null,
          'median_minutes_to_pass': null
        },
        size: const Size(360, 780),
      );
      await tester.scrollUntilVisible(
          find.text('No student has attempted this version yet.'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('No student has attempted this version yet.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
