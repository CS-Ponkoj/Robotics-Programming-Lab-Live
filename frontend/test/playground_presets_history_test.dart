import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/models/playground_parameter.dart';
import 'package:iuse_demo/models/playground_result_dto.dart';
import 'package:iuse_demo/services/assignment_api.dart';
import 'package:iuse_demo/widgets/playground_dialog.dart';

Map<String, dynamic> point(String name, String label, String example) => {
  'name': name,
  'kind': 'point',
  'label': label,
  'meaning': 'Meaning of $label',
  'unit': 'm',
  'example': example,
};

// Mirrors the shape of backend/assignments/assignment_1.json playground.
final playground = <String, dynamic>{
  'parameters': [
    point('start', 'Start', '(2.0, 1.0)'),
    point('hit', 'Hit point', '(4.0, 3.5)'),
    point('goal', 'Goal', '(8.0, 9.0)'),
  ],
  'scenarios': [
    {
      'id': 'hit_right_after_start',
      'label': 'Hit right after start',
      'description': 'A very short approach. Does the total still add up?',
      'values': {
        'start': '(0.0, 0.0)',
        'hit': '(0.5, 0.5)',
        'goal': '(5.0, 5.0)',
      },
    },
    {
      'id': 'negative_coordinates',
      'label': 'Negative coordinates',
      'values': {
        'start': '(-4.0, -2.0)',
        'hit': '(-2.0, -1.0)',
        'goal': '(4.0, 2.0)',
      },
    },
    // Missing a parameter, so it is never offered.
    {
      'id': 'broken',
      'label': 'Broken',
      'values': {'start': '(0, 0)'},
    },
  ],
};

const code = 'def route(start, hit, goal):\n    return 1.0, 2.0';

PlaygroundResultDto resultFor(String arguments) => PlaygroundResultDto(
  success: true,
  call: 'route($arguments)',
  expectedReturnCount: 2,
  returnCount: 2,
  values: [
    PlaygroundValueDto(
      label: 'Approach distance',
      value: arguments.length.toDouble(),
      display: '${arguments.length}.0',
    ),
    const PlaygroundValueDto(label: 'Total', value: 2.0, display: '2.0'),
  ],
);

Widget dialogFor({
  Map<String, dynamic>? settings,
  List<PlaygroundRun> history = const [],
  ValueChanged<List<PlaygroundRun>>? onHistoryChanged,
  PlaygroundRunner? runner,
  List<String>? calls,
}) {
  final config = {'enabled': true, 'playground': settings ?? playground};
  return MaterialApp(
    home: Scaffold(
      body: PlaygroundDialog(
        assignmentId: 1,
        functionName: 'route',
        code: code,
        sampleArguments: playgroundSampleArguments(config),
        parameters: playgroundParameters(config),
        scenarios: playgroundScenarios(config),
        simulationConfig: config,
        history: history,
        onHistoryChanged: onHistoryChanged,
        runner:
            runner ??
            (_, __, arguments) async {
              calls?.add(arguments);
              return resultFor(arguments);
            },
      ),
    ),
  );
}

void useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

String fieldText(WidgetTester tester, String name) => tester
    .widget<TextField>(find.byKey(Key('playground-field-$name')))
    .controller!
    .text;

Future<void> choose(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('playground-scenario')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> run(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('playground-run-button')));
  await tester.pumpAndSettle();
}

void main() {
  group('advisory kind check', () {
    PlaygroundParameterSpec spec(String kind) => PlaygroundParameterSpec(
      name: 'x',
      kind: kind,
      label: 'X',
      example: '1',
    );

    final cases = <String, (List<String>, List<String>)>{
      'point': (
        ['(1, 2)', '[1.5, -2]', '(1e3, .5)', ' ( 1 , 2 , ) '],
        ['5', '(1,)', '(1, 2, 3)', "('a', 1)", '1, 2'],
      ),
      'number': (['1', '-2.5', '3e-2', '.5'], ['abc', '(1, 2)', "'1'"]),
      'integer': (['0', '5', '-2'], ['2.5', '1e3', 'five']),
      'list_of_points': (
        ['[]', '[(1, 2)]', '[(1, 2), [3, 4],]', '((1, 2),)'],
        ['[1, 2]', '[(1, 2), 3]', '(1, 2)', 'x'],
      ),
      'angle_map': (
        ['{}', '{0: 10, 359: 9.5}', '{ 1 : 2 , }'],
        ['{0.5: 1}', "{'0': 1}", "{1: 'far'}", '[1]'],
      ),
      'text': (
        ["'Main Elevator'", '"a, b"', r"'it\'s'"],
        ['Main', '1', "'open"],
      ),
    };

    test('accepts each kind and flags other shapes with server wording', () {
      for (final MapEntry(key: kind, value: (good, bad)) in cases.entries) {
        for (final text in good) {
          expect(kindProblem(spec(kind), text), isNull, reason: '$kind $text');
        }
        for (final text in bad) {
          expect(
            kindProblem(spec(kind), text),
            isNotNull,
            reason: '$kind $text',
          );
        }
      }
      expect(
        kindProblem(spec('point'), '5'),
        'X should be a point with two numbers, like (2.0, 1.0).',
      );
      expect(kindProblem(spec('point'), '   '), isNull);
      expect(kindProblem(spec('unknown'), 'anything'), isNull);
    });
  });

  group('scenario presets', () {
    test('only complete scenarios are offered', () {
      final scenarios = playgroundScenarios({'playground': playground});
      expect(scenarios.map((item) => item.id), [
        'hit_right_after_start',
        'negative_coordinates',
      ]);
      expect(playgroundScenarios(const {}), isEmpty);
    });

    testWidgets('choosing a scenario fills every field without running', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      final calls = <String>[];
      await tester.pumpWidget(dialogFor(calls: calls));

      expect(find.text('Start from'), findsOneWidget);
      expect(find.text('Instructions example'), findsOneWidget);
      expect(find.text('Broken'), findsNothing);

      await choose(tester, 'Hit right after start');
      expect(fieldText(tester, 'start'), '(0.0, 0.0)');
      expect(fieldText(tester, 'goal'), '(5.0, 5.0)');
      expect(
        find.byKey(const Key('playground-scenario-description')),
        findsOneWidget,
      );
      expect(calls, isEmpty);

      await run(tester);
      expect(calls, ['(0.0, 0.0), (0.5, 0.5), (5.0, 5.0)']);
    });

    testWidgets('editing a field switches to Custom; the example comes back', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      await tester.pumpWidget(dialogFor());
      await tester.enterText(
        find.byKey(const Key('playground-field-hit')),
        '(9, 9)',
      );
      await tester.pumpAndSettle();
      expect(find.text('Custom (your own values)'), findsOneWidget);
      // The scenario dropdown replaces the separate example button.
      expect(find.byKey(const Key('playground-use-example')), findsNothing);

      await choose(tester, 'Instructions example');
      expect(fieldText(tester, 'hit'), '(4.0, 3.5)');
      expect(find.text('Custom (your own values)'), findsNothing);
    });

    testWidgets('typing a scenario value by hand selects that scenario', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      await tester.pumpWidget(dialogFor());
      await tester.enterText(
        find.byKey(const Key('playground-field-start')),
        '(-4.0, -2.0)',
      );
      await tester.enterText(
        find.byKey(const Key('playground-field-hit')),
        '(-2.0, -1.0)',
      );
      await tester.enterText(
        find.byKey(const Key('playground-field-goal')),
        '(4.0, 2.0)',
      );
      await tester.pumpAndSettle();
      expect(find.text('Negative coordinates'), findsOneWidget);
    });

    testWidgets('assignments without scenarios keep the example button', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      await tester.pumpWidget(
        dialogFor(settings: {'parameters': playground['parameters']}),
      );
      expect(find.byKey(const Key('playground-scenario')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('playground-field-hit')),
        '(9, 9)',
      );
      await tester.pump();
      expect(find.byKey(const Key('playground-use-example')), findsOneWidget);
    });
  });

  group('instant field feedback', () {
    testWidgets(
      'a wrong shape is flagged while typing but never blocks a run',
      (WidgetTester tester) async {
        useTallWindow(tester);
        final calls = <String>[];
        await tester.pumpWidget(dialogFor(calls: calls));
        await tester.enterText(
          find.byKey(const Key('playground-field-hit')),
          '2',
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Hit point should be a point with two numbers, like (2.0, 1.0).',
          ),
          findsOneWidget,
        );

        final button = tester.widget<FilledButton>(
          find.byKey(const Key('playground-run-button')),
        );
        expect(button.onPressed, isNotNull);
        await run(tester);
        expect(calls, hasLength(1));
      },
    );

    testWidgets('the server answer replaces the instant check', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      await tester.pumpWidget(
        dialogFor(
          runner: (_, __, ___) async {
            throw const PlaygroundInputException(
              'Server says no.',
              fieldErrors: {1: 'Server message for the hit point.'},
            );
          },
        ),
      );
      await tester.enterText(
        find.byKey(const Key('playground-field-hit')),
        '2',
      );
      await tester.pumpAndSettle();
      await run(tester);
      expect(find.text('Server message for the hit point.'), findsOneWidget);
    });
  });

  group('run history', () {
    testWidgets('keeps the last three runs and marks changed inputs', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      var latest = <PlaygroundRun>[];
      await tester.pumpWidget(
        dialogFor(onHistoryChanged: (runs) => latest = runs),
      );

      await run(tester);
      expect(find.byKey(const Key('playground-history')), findsNothing);

      await choose(tester, 'Hit right after start');
      await run(tester);
      expect(find.byKey(const Key('playground-history')), findsOneWidget);
      expect(find.text('Latest: Hit right after start'), findsOneWidget);
      expect(find.text('Instructions example'), findsWidgets);

      await tester.enterText(
        find.byKey(const Key('playground-field-goal')),
        '(6, 6)',
      );
      await tester.pumpAndSettle();
      await run(tester);
      await choose(tester, 'Negative coordinates');
      await run(tester);

      expect(latest, hasLength(maxPlaygroundRuns));
      expect(latest.map((run) => run.label), [
        'Negative coordinates',
        'Custom',
        'Hit right after start',
      ]);
      expect(latest.first.inputs.first.key, 'Start');
      expect(latest.first.inputs.first.value, '(-4.0, -2.0)');

      // The changed start value in the latest column is highlighted.
      final highlighted = tester
          .widgetList<Container>(
            find.ancestor(
              of: find.text('(-4.0, -2.0)').last,
              matching: find.byType(Container),
            ),
          )
          .any((box) => box.color != null);
      expect(highlighted, isTrue);
    });

    testWidgets('history passed in from the workspace is shown on reopen', (
      WidgetTester tester,
    ) async {
      useTallWindow(tester);
      final earlier = [
        PlaygroundRun(
          label: 'Custom',
          inputs: const [MapEntry('Start', '(1, 1)')],
          values: const [
            PlaygroundValueDto(label: 'Total', value: 3.0, display: '3.0'),
          ],
        ),
        PlaygroundRun(
          label: 'Instructions example',
          inputs: const [MapEntry('Start', '(2, 1)')],
          values: const [
            PlaygroundValueDto(label: 'Total', value: 4.0, display: '4.0'),
          ],
        ),
      ];
      await tester.pumpWidget(dialogFor(history: earlier));
      expect(find.byKey(const Key('playground-history')), findsOneWidget);
      expect(find.text('Latest: Custom'), findsOneWidget);
    });
  });

  testWidgets('Ctrl+Enter runs the function from a field', (
    WidgetTester tester,
  ) async {
    useTallWindow(tester);
    final calls = <String>[];
    await tester.pumpWidget(dialogFor(calls: calls));
    await tester.tap(find.byKey(const Key('playground-field-start')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
  });

  testWidgets('presets, feedback, and history fit a 360 pixel phone', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(dialogFor());
    await tester.ensureVisible(find.byKey(const Key('playground-run-button')));
    await run(tester);
    await tester.ensureVisible(find.byKey(const Key('playground-scenario')));
    await choose(tester, 'Negative coordinates');
    await tester.ensureVisible(find.byKey(const Key('playground-run-button')));
    await run(tester);
    expect(find.byKey(const Key('playground-history')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
