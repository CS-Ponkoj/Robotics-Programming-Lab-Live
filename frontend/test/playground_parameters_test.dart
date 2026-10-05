import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/models/playground_diagram.dart';
import 'package:iuse_demo/models/playground_parameter.dart';
import 'package:iuse_demo/models/playground_result_dto.dart';
import 'package:iuse_demo/services/assignment_api.dart';
import 'package:iuse_demo/widgets/playground_dialog.dart';

// Mirrors backend/assignments/assignment_1.json simulation_config.playground.
const bugPlayground = {
  'parameters': [
    {
      'name': 'start',
      'kind': 'point',
      'label': 'Start',
      'meaning': 'Where the robot begins (S)',
      'unit': 'm',
      'example': '(2.0, 1.0)',
    },
    {
      'name': 'hit',
      'kind': 'point',
      'label': 'Hit point',
      'meaning': 'Where the m-line first reaches the obstacle (H)',
      'unit': 'm',
      'example': '(4.0, 3.6666666666666665)',
    },
    {
      'name': 'corner',
      'kind': 'point',
      'label': 'Corner',
      'meaning': 'Obstacle corner the robot follows around clockwise',
      'unit': 'm',
      'example': '(4.0, 6.0)',
    },
    {
      'name': 'leave',
      'kind': 'point',
      'label': 'Leave point',
      'meaning': 'Where the boundary meets the m-line again (L)',
      'unit': 'm',
      'example': '(5.75, 6.0)',
    },
    {
      'name': 'goal',
      'kind': 'point',
      'label': 'Goal',
      'meaning': 'Where the robot must arrive (G)',
      'unit': 'm',
      'example': '(8.0, 9.0)',
    },
  ],
  'hints_enabled': true,
};

const bugExample =
    '(2.0, 1.0), (4.0, 3.6666666666666665), (4.0, 6.0), (5.75, 6.0), (8.0, 9.0)';

const bugCode =
    'def calculate_bug2_route(start, hit, corner, leave, goal):\n'
    '    return 0.0, 0.0, 0.0, 0.0';

Map<String, dynamic> elevatorPlayground() {
  Map<String, dynamic> item(
    String name,
    String kind,
    String group,
    String example,
  ) => {
    'name': name,
    'kind': kind,
    'label': name.replaceAll('_', ' '),
    'meaning': 'Meaning of $name',
    'example': example,
    'group': group,
  };
  return {
    'parameters': [
      item('robot_speed', 'number', 'Robot', '1.0'),
      item('service_detour_radius', 'number', 'Robot', '1.0'),
      item('main_elevator_wait', 'number', 'Elevators', '30.0'),
      item('service_elevator_wait', 'number', 'Elevators', '10.0'),
      item('main_seconds_per_floor', 'number', 'Elevators', '15.0'),
      item('service_seconds_per_floor', 'number', 'Elevators', '20.0'),
      item('floors_to_travel', 'integer', 'Elevators', '5'),
      item('start', 'point', 'Map', '(5.0, 5.0)'),
      item('goal', 'point', 'Map', '(25.0, 30.0)'),
      item('main_elevator', 'point', 'Map', '(10.0, 5.0)'),
      item('service_elevator', 'point', 'Map', '(6.0, 15.0)'),
      item(
        'main_waypoints',
        'list_of_points',
        'Map',
        '[(7.5, 4.5), (8.5, 4.5)]',
      ),
    ],
  };
}

PlaygroundResultDto okResult() => const PlaygroundResultDto(
  success: true,
  call: 'calculate_bug2_route(...)',
  expectedReturnCount: 4,
  returnCount: 4,
  values: [
    PlaygroundValueDto(label: 'Approach distance', value: 1.0, display: '1.0'),
  ],
);

Widget dialogFor(
  Map<String, dynamic> playground, {
  String initial = '',
  PlaygroundRunner? runner,
  ValueChanged<String>? onChanged,
  String code = bugCode,
}) {
  final config = {'enabled': true, 'playground': playground};
  return MaterialApp(
    home: Scaffold(
      body: PlaygroundDialog(
        assignmentId: 1,
        functionName: 'calculate_bug2_route',
        code: code,
        initialArguments: initial,
        sampleArguments: playgroundSampleArguments(config),
        parameters: playgroundParameters(config),
        simulationConfig: config,
        onArgumentsChanged: onChanged,
        runner: runner ?? (_, __, ___) async => okResult(),
      ),
    ),
  );
}

/// Room for every labelled field, so typing and tapping need no scrolling.
void useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The dialog scrolls; bring a control into view before tapping it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

String fieldText(WidgetTester tester, String name) => tester
    .widget<TextField>(find.byKey(Key('playground-field-$name')))
    .controller!
    .text;

void main() {
  group('splitting one line of inputs', () {
    test('splits only at top-level commas', () {
      expect(splitPlaygroundArguments('(1, 2), 3'), ['(1, 2)', '3']);
      expect(
        splitPlaygroundArguments("{0: 10, 1: 8}, [(1, 2), (3, 4)], 'a, b'"),
        ['{0: 10, 1: 8}', '[(1, 2), (3, 4)]', "'a, b'"],
      );
      expect(splitPlaygroundArguments(r"'it\'s, fine', 2"), [
        r"'it\'s, fine'",
        '2',
      ]);
      expect(splitPlaygroundArguments('1, 2,'), ['1', '2']);
      expect(splitPlaygroundArguments('1,,2'), ['1', '', '2']);
      expect(splitPlaygroundArguments('   '), isEmpty);
    });

    test('unbalanced brackets or quotes cannot be split', () {
      expect(splitPlaygroundArguments('(1, 2'), isNull);
      expect(splitPlaygroundArguments('1, 2)'), isNull);
      expect(splitPlaygroundArguments("'open, 2"), isNull);
    });
  });

  group('parameter settings', () {
    test('parameters, examples, and hint switch are read from the config', () {
      const config = {'playground': bugPlayground};
      final parameters = playgroundParameters(config);
      expect(parameters.map((p) => p.name), [
        'start',
        'hit',
        'corner',
        'leave',
        'goal',
      ]);
      expect(
        parameters.first.helper,
        'point (x, y) in m · Where the robot begins (S)',
      );
      expect(playgroundSampleArguments(config), bugExample);
      expect(playgroundHintsEnabled(config), isTrue);
      expect(
        playgroundHintsEnabled(const {
          'playground': {'hints_enabled': false},
        }),
        isFalse,
      );
      // A v6.3 configuration without parameters keeps its one-line sample.
      expect(
        playgroundSampleArguments(const {
          'playground': {'sample_arguments': '1, 2'},
        }),
        '1, 2',
      );
      expect(playgroundParameters(null), isEmpty);
      expect(playgroundSampleArguments(const {}), isEmpty);
    });

    test('every kind has a readable label', () {
      for (final kind in [
        'point',
        'number',
        'integer',
        'list_of_points',
        'angle_map',
        'text',
      ]) {
        expect(parameterKindLabel(kind), isNot('value'));
      }
      expect(parameterKindLabel('unknown'), 'value');
    });

    test('instructors can switch diagram hints off', () {
      final config = {
        'enabled': true,
        'playground': {'hints_enabled': false},
        'diagram': {
          'view': 'route',
          'points': [
            {'id': 'S', 'arg': 0},
            {'id': 'G', 'arg': 1},
          ],
          'paths': [
            {
              'points': ['S', 'G'],
              'value': 0,
            },
          ],
          'checks': [
            {
              'type': 'sum',
              'parts': [0, 1],
              'total': 2,
            },
          ],
        },
      };
      const result = PlaygroundResultDto(
        success: true,
        call: 'f()',
        arguments: [
          [0, 0],
          [3, 4],
        ],
        values: [
          PlaygroundValueDto(label: 'A', value: 1.0, display: '1.0'),
          PlaygroundValueDto(label: 'B', value: 1.0, display: '1.0'),
          PlaygroundValueDto(label: 'Total', value: 9.0, display: '9.0'),
        ],
      );
      expect(buildPlaygroundDiagram(config, result)!.hints, isEmpty);
      final withHints = Map<String, dynamic>.from(config)
        ..['playground'] = {'hints_enabled': true};
      expect(buildPlaygroundDiagram(withHints, result)!.hints, hasLength(1));
    });
  });

  group('labelled input fields', () {
    testWidgets('each input has its own labelled field with the example', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      final calls = <String>[];
      await tester.pumpWidget(
        dialogFor(
          bugPlayground,
          runner: (_, __, arguments) async {
            calls.add(arguments);
            return okResult();
          },
        ),
      );

      expect(find.text('Function'), findsOneWidget);
      expect(find.text('Hit point'), findsOneWidget);
      expect(
        find.text(
          'point (x, y) in m · Where the m-line first reaches the obstacle (H)',
        ),
        findsOneWidget,
      );
      expect(fieldText(tester, 'corner'), '(4.0, 6.0)');
      expect(find.byKey(const Key('playground-arguments')), findsNothing);
      expect(find.byKey(const Key('playground-use-example')), findsNothing);

      await tapVisible(tester, find.byKey(const Key('playground-run-button')));
      await tester.pumpAndSettle();
      expect(calls, [bugExample]);
    });

    testWidgets('server problems appear on the exact field', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      await tester.pumpWidget(
        dialogFor(
          bugPlayground,
          runner: (_, __, ___) async {
            throw const PlaygroundInputException(
              'Hit point should be a point with two numbers, like (2.0, 1.0).',
              fieldErrors: {
                1: 'Hit point should be a point with two numbers, like (2.0, 1.0).',
                2: 'Corner should be a point with two numbers, like (2.0, 1.0).',
              },
            );
          },
        ),
      );
      await tester.enterText(
        find.byKey(const Key('playground-field-hit')),
        '2',
      );
      await tester.enterText(
        find.byKey(const Key('playground-field-corner')),
        '3',
      );
      await tapVisible(tester, find.byKey(const Key('playground-run-button')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Hit point should be a point'),
        findsOneWidget,
      );
      expect(find.textContaining('Corner should be a point'), findsOneWidget);
      expect(find.byKey(const Key('playground-request-error')), findsNothing);

      // Editing a field clears only its own message (after its fade-out).
      await tester.enterText(
        find.byKey(const Key('playground-field-hit')),
        '(4, 3)',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Hit point should be a point'), findsNothing);
      expect(find.textContaining('Corner should be a point'), findsOneWidget);
    });

    testWidgets('a general input problem is shown above the results', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      await tester.pumpWidget(
        dialogFor(
          bugPlayground,
          runner: (_, __, ___) async {
            throw const PlaygroundInputException(
              'Enter 5 inputs, one for each parameter.',
            );
          },
        ),
      );
      await tapVisible(tester, find.byKey(const Key('playground-run-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playground-request-error')), findsOneWidget);
    });

    testWidgets('empty fields are caught before running', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      var ran = false;
      await tester.pumpWidget(
        dialogFor(
          bugPlayground,
          runner: (_, __, ___) async {
            ran = true;
            return okResult();
          },
        ),
      );
      await tester.enterText(
        find.byKey(const Key('playground-field-goal')),
        '  ',
      );
      await tapVisible(tester, find.byKey(const Key('playground-run-button')));
      await tester.pumpAndSettle();
      expect(ran, isFalse);
      expect(find.text('Enter a value for Goal.'), findsOneWidget);
    });

    testWidgets('example inputs can be restored after edits', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      String? latest;
      await tester.pumpWidget(
        dialogFor(bugPlayground, onChanged: (value) => latest = value),
      );
      await tester.enterText(
        find.byKey(const Key('playground-field-start')),
        '(0, 0)',
      );
      await tester.pump();
      expect(latest, startsWith('(0, 0), (4.0, 3.6666666666666665)'));
      expect(find.byKey(const Key('playground-use-example')), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('playground-use-example')));
      await tester.pump();
      expect(fieldText(tester, 'start'), '(2.0, 1.0)');
      expect(latest, bugExample);
      expect(find.byKey(const Key('playground-use-example')), findsNothing);
    });

    testWidgets('inputs move between fields and one line', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      await tester.pumpWidget(dialogFor(bugPlayground));
      await tester.enterText(
        find.byKey(const Key('playground-field-start')),
        '(0, 0)',
      );
      await tapVisible(tester, find.byKey(const Key('playground-mode-toggle')));
      await tester.pump();

      final line = tester.widget<TextField>(
        find.byKey(const Key('playground-arguments')),
      );
      expect(
        line.controller!.text,
        startsWith('(0, 0), (4.0, 3.6666666666666665)'),
      );
      expect(find.text('Edit each input'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('playground-arguments')),
        '(1, 1), (2, 2), (3, 3), (4, 4), (5, 5)',
      );
      await tapVisible(tester, find.byKey(const Key('playground-mode-toggle')));
      await tester.pump();
      expect(fieldText(tester, 'goal'), '(5, 5)');

      // A line that does not split into five inputs stays as one line.
      await tapVisible(tester, find.byKey(const Key('playground-mode-toggle')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('playground-arguments')),
        '(1, 1), (2, 2)',
      );
      await tapVisible(tester, find.byKey(const Key('playground-mode-toggle')));
      await tester.pump();
      expect(find.byKey(const Key('playground-mode-note')), findsOneWidget);
      expect(find.byKey(const Key('playground-arguments')), findsOneWidget);
    });

    testWidgets('earlier inputs fill the fields when they fit', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      await tester.pumpWidget(
        dialogFor(
          bugPlayground,
          initial: '(1, 1), (2, 2), (3, 3), (4, 4), (5, 5)',
        ),
      );
      expect(fieldText(tester, 'hit'), '(2, 2)');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(dialogFor(bugPlayground, initial: '(1, 1), 2'));
      // Earlier inputs that do not fit stay editable as one line.
      expect(find.byKey(const Key('playground-arguments')), findsOneWidget);
    });

    testWidgets('grouped inputs show section headings and fit a phone', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(dialogFor(elevatorPlayground()));
      expect(tester.takeException(), isNull);
      expect(find.text('Robot'), findsOneWidget);
      expect(find.text('Elevators'), findsOneWidget);
      expect(find.text('Map'), findsOneWidget);
      expect(
        find.byKey(const Key('playground-field-main_waypoints')),
        findsOneWidget,
      );
      expect(
        find.text('whole number · Meaning of floors_to_travel'),
        findsOneWidget,
      );
    });

    testWidgets('assignments without parameters keep the single box', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      await tester.pumpWidget(dialogFor(const {}));
      expect(find.byKey(const Key('playground-arguments')), findsOneWidget);
      expect(find.byKey(const Key('playground-mode-toggle')), findsNothing);
    });
  });
}
