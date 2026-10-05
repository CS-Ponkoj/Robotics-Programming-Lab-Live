import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/models/playground_diagram.dart';
import 'package:iuse_demo/models/playground_result_dto.dart';
import 'package:iuse_demo/widgets/playground_diagram.dart';
import 'package:iuse_demo/widgets/playground_dialog.dart';

// Copies of the assignment simulation_config blocks (backend/assignments).
const bugRouteConfig = {
  'enabled': true,
  'provider': 'diagram',
  'diagram': {
    'view': 'route',
    'caption': 'Drawn to scale from your inputs.',
    'points': [
      {'id': 'S', 'arg': 0},
      {'id': 'H', 'arg': 1},
      {'id': 'C', 'arg': 2},
      {'id': 'L', 'arg': 3},
      {'id': 'G', 'arg': 4},
    ],
    'paths': [
      {'points': ['S', 'H'], 'value': 0},
      {'points': ['H', 'C', 'L'], 'value': 1},
      {'points': ['L', 'G'], 'value': 2},
    ],
    'legend_values': [3],
    'checks': [
      {'type': 'sum', 'parts': [0, 1, 2], 'total': 3},
    ],
  },
};

const elevatorConfig = {
  'enabled': true,
  'provider': 'diagram',
  'diagram': {
    'view': 'route',
    'points': [
      {'id': 'S', 'arg': 7},
      {'id': 'M', 'arg': 11, 'each': true},
      {'id': 'E_m', 'arg': 9},
      {'id': 'E_s', 'arg': 10},
    ],
    'paths': [
      {'points': ['S', 'M*', 'E_m'], 'value': 0},
      {
        'points': ['S', 'E_s'],
        'value': 1,
        'style': 'dashed',
        'note': 'includes the detour allowance',
      },
    ],
    'legend_values': [2, 3, 4, 5, 6, 7],
    'checks': [
      {
        'type': 'min_label',
        'candidates': [4, 5],
        'labels': ['Main Elevator', 'Service Elevator'],
        'label': 6,
        'best': 7,
        'tie_index': 1,
      },
    ],
  },
};

const vfhConfig = {
  'enabled': true,
  'provider': 'diagram',
  'diagram': {
    'view': 'polar',
    'readings': {'arg': 0},
    'arcs': [
      {'from_arg': 1, 'to_arg': 2, 'label': 'Sectors to fill'},
    ],
    'rays': [
      {
        'arg': 3,
        'half_width_arg': 4,
        'label': 'Goal direction and search window',
        'style': 'dashed',
      },
      {'arg': 5, 'label': 'Probe angle'},
      {'value': 3, 'label': 'Your optimal angle', 'style': 'bold'},
    ],
    'legend_values': [0, 1, 2, 4],
  },
};

const bugParameters = ['start', 'hit', 'corner', 'leave', 'goal'];

PlaygroundValueDto value(String label, Object? raw, [String? display]) =>
    PlaygroundValueDto(label: label, value: raw, display: display ?? '$raw');

PlaygroundResultDto bugResult({
  List<dynamic>? arguments,
  double total = 11.0,
  bool success = true,
}) {
  return PlaygroundResultDto(
    success: success,
    call: 'calculate_bug2_route(...)',
    expectedReturnCount: 4,
    returnCount: success ? 4 : null,
    arguments: arguments ??
        [
          [2, 1],
          [4, 3.5],
          [4, 6],
          [6, 6],
          [8, 9],
        ],
    values: success
        ? [
            value('Approach distance', 3.0, '3.0'),
            value('Boundary-following distance', 4.5, '4.5'),
            value('Departure distance', 3.5, '3.5'),
            value('Complete route distance', total, '$total'),
          ]
        : const [],
    error: success ? '' : 'ZeroDivisionError at line 3',
  );
}

PlaygroundResultDto elevatorResult({
  List<dynamic> waypoints = const [
    [7.5, 4.5],
    [8.5, 4.5],
  ],
  double main = 139.0,
  double service = 147.0,
  String label = 'Main Elevator',
  double best = 139.0,
}) {
  return PlaygroundResultDto(
    success: true,
    call: 'evaluate_elevator_routes(...)',
    expectedReturnCount: 8,
    returnCount: 8,
    arguments: [
      1, 1, 30, 10, 15, 20, 5,
      [5, 5],
      [25, 30],
      [10, 5],
      [6, 15],
      waypoints,
    ],
    values: [
      value('Main entry route', 5.1),
      value('Service entry route', 13.2),
      value('Main destination route', 29.2),
      value('Service destination route', 24.2),
      value('Main complete time', main),
      value('Service complete time', service),
      value('Best route label', label, "'$label'"),
      value('Best route time', best),
    ],
  );
}

PlaygroundResultDto vfhResult({Object? readings, Object? optimal = 90}) {
  return PlaygroundResultDto(
    success: true,
    call: 'analyze_vfh(...)',
    expectedReturnCount: 5,
    returnCount: 5,
    arguments: [
      readings ?? {'0': 10, '359': 9, '1': 8, '370': 6},
      3,
      357,
      90,
      10,
      45,
    ],
    values: [
      value('Complete LIDAR sectors', 360),
      value('Inclusive search window', 21),
      value('Inverse-square density', 0.01),
      value('Optimal sector angle', optimal),
      value('Optimal sector density', 0.0069),
    ],
  );
}

void main() {
  group('diagram data', () {
    test('only assignments that declare a diagram get one', () {
      final result = bugResult();
      expect(buildPlaygroundDiagram(null, result), isNull);
      expect(buildPlaygroundDiagram(const {'enabled': false}, result), isNull);
      expect(
        buildPlaygroundDiagram(
          const {'enabled': false, 'diagram': {'view': 'route'}},
          result,
        ),
        isNull,
      );
      expect(
        buildPlaygroundDiagram(
          const {'enabled': true, 'diagram': {'view': '3d'}},
          result,
        ),
        isNull,
      );
    });

    test('route paths use the student inputs and returned values only', () {
      final diagram = buildPlaygroundDiagram(
        bugRouteConfig,
        bugResult(total: 11.0),
        parameterNames: bugParameters,
      )!;

      expect(diagram.problem, isNull);
      expect(diagram.points.map((p) => p.id), ['S', 'H', 'C', 'L', 'G']);
      expect(diagram.paths.map((p) => p.points.map((q) => q.id).join()),
          ['SH', 'HCL', 'LG']);
      expect(diagram.paths.map((p) => p.valueText), ['3.0', '4.5', '3.5']);
      expect(diagram.paths.map((p) => p.shortText), ['3.0', '4.5', '3.5']);
      expect(diagram.legend.last.label, 'Complete route distance');
      expect(diagram.legend.last.valueText, '11.0');
      expect(diagram.hints, isEmpty);
      expect(diagram.description, contains('S at (2.0, 1.0)'));
      expect(diagram.description, contains('you returned 4.5'));
    });

    test('a total that is not the sum of the parts earns a gentle hint', () {
      final diagram = buildPlaygroundDiagram(
        bugRouteConfig,
        bugResult(total: 12.5),
        parameterNames: bugParameters,
      )!;

      expect(diagram.hints, hasLength(1));
      expect(diagram.hints.single, contains('(12.5) is not approach distance'));
      expect(diagram.hints.single, contains('(11.0)'));
    });

    test('a failed run still draws the inputs, without values or hints', () {
      final diagram = buildPlaygroundDiagram(
        bugRouteConfig,
        bugResult(success: false),
        parameterNames: bugParameters,
      )!;

      expect(diagram.problem, isNull);
      expect(diagram.paths, hasLength(3));
      expect(diagram.paths.every((p) => p.valueText == null), isTrue);
      expect(diagram.hints, isEmpty);
    });

    test('inputs that cannot be drawn explain what to fix', () {
      String? problemFor(List<dynamic> arguments) => buildPlaygroundDiagram(
            bugRouteConfig,
            bugResult(arguments: arguments),
            parameterNames: bugParameters,
          )!
              .problem;

      expect(
        problemFor([
          [2, 1],
          'up',
          [4, 6],
          [6, 6],
          [8, 9],
        ]),
        contains('hit should be a pair of numbers'),
      );
      expect(
        problemFor([
          [2, 1, 0],
          [4, 3],
          [4, 6],
          [6, 6],
          [8, 9],
        ]),
        contains('start should be a pair'),
      );
      expect(
        problemFor([
          [2e7, 1],
          [4, 3],
          [4, 6],
          [6, 6],
          [8, 9],
        ]),
        contains('start should be a pair'),
      );
      expect(
        problemFor([
          [2, 1],
          [4, 3],
        ]),
        contains('enter a value for corner'),
      );
      expect(
        problemFor([
          [true, 1],
          [4, 3],
          [4, 6],
          [6, 6],
          [8, 9],
        ]),
        contains('start should be a pair'),
      );
    });

    test('waypoint lists expand into numbered points', () {
      final diagram = buildPlaygroundDiagram(elevatorConfig, elevatorResult())!;
      expect(diagram.points.map((p) => p.id), ['S', 'M1', 'M2', 'E_m', 'E_s']);
      expect(diagram.paths.first.points.map((p) => p.id), ['S', 'M1', 'M2', 'E_m']);
      expect(diagram.paths.last.dashed, isTrue);
      expect(diagram.legend[1].note, 'includes the detour allowance');
      expect(diagram.hints, isEmpty);

      // Map labels are rounded; the legend keeps Python's full value.
      final precise = buildPlaygroundDiagram(
        elevatorConfig,
        PlaygroundResultDto(
          success: true,
          call: 'f()',
          arguments: elevatorResult().arguments,
          values: [value('Main entry route', 5.130648586880582, '5.130648586880582')],
        ),
      )!;
      expect(precise.paths.first.shortText, '5.1306');
      expect(precise.legend.first.valueText, '5.130648586880582');

      final direct = buildPlaygroundDiagram(
        elevatorConfig,
        elevatorResult(waypoints: const []),
      )!;
      expect(direct.paths.first.points.map((p) => p.id), ['S', 'E_m']);

      final broken = buildPlaygroundDiagram(
        elevatorConfig,
        elevatorResult(waypoints: const [7.5]),
      )!;
      expect(broken.problem, contains('should be a pair of numbers'));
    });

    test('label and best-time hints compare only the student values', () {
      final wrongLabel = buildPlaygroundDiagram(
        elevatorConfig,
        elevatorResult(label: 'Service Elevator'),
      )!;
      expect(wrongLabel.hints.single,
          contains('smaller complete time belongs to "Main Elevator"'));

      final tie = buildPlaygroundDiagram(
        elevatorConfig,
        elevatorResult(main: 140, service: 140, best: 140),
      )!;
      expect(tie.hints.single, contains('tie-break rule picks "Service Elevator"'));

      final wrongBest = buildPlaygroundDiagram(
        elevatorConfig,
        elevatorResult(best: 147),
      )!;
      expect(wrongBest.hints.single, contains('does not match your smaller'));
    });

    test('polar view draws only supplied readings and the student angle', () {
      final diagram = buildPlaygroundDiagram(vfhConfig, vfhResult())!;

      expect(diagram.problem, isNull);
      // 370 degrees normalises to 10; readings are sorted by angle.
      expect(diagram.readings.map((r) => r.angle), [0, 1, 10, 359]);
      expect(diagram.readings, hasLength(4));
      expect(diagram.arcs.single.from, 3);
      expect(diagram.arcs.single.to, 357);
      expect(diagram.legend.first.note, '3 to 357 degrees');
      expect(diagram.legend[1].note, '90 degrees, plus or minus 10');
      expect(diagram.rays.map((r) => r.angle), [90, 45, 90]);
      expect(diagram.rays.first.halfWidth, 10);
      expect(diagram.rays.last.style, 'bold');
      expect(diagram.description, contains('4 supplied readings'));
      expect(diagram.description, contains('Your optimal angle: you returned 90'));

      final pairs = buildPlaygroundDiagram(
        vfhConfig,
        vfhResult(readings: [
          [0, 10],
          [90, 8],
        ]),
      )!;
      expect(pairs.readings.map((r) => r.distance), [10, 8]);
    });

    test('polar view explains unusable readings and angles', () {
      expect(
        buildPlaygroundDiagram(vfhConfig, vfhResult(readings: {'0': -1}))!.problem,
        contains('positive distance'),
      );
      expect(
        buildPlaygroundDiagram(vfhConfig, vfhResult(readings: {'north': 3}))!.problem,
        contains('numeric angle'),
      );
      expect(
        buildPlaygroundDiagram(vfhConfig, vfhResult(readings: const {}))!.problem,
        contains('at least one reading'),
      );
      expect(
        buildPlaygroundDiagram(vfhConfig, vfhResult(readings: 5))!.problem,
        contains('should map angles to distances'),
      );

      final notNumber = buildPlaygroundDiagram(
        vfhConfig,
        vfhResult(optimal: 'ninety'),
      )!;
      expect(notNumber.problem, isNull);
      expect(notNumber.rays, hasLength(2));
      expect(
        notNumber.legend.firstWhere((e) => e.label == 'Your optimal angle').note,
        'not a number, so not drawn',
      );
    });

    test('number helpers stay readable', () {
      expect(formatDiagramNumber(11), '11.0');
      expect(formatDiagramNumber(3.333333333), '3.3333');
      expect(formatDiagramNumber(0.5), '0.5');
      expect(formatDiagramAngle(90), '90');
      expect(formatDiagramAngle(12.5), '12.5');
      expect(niceDiagramStep(0.3), closeTo(0.5, 1e-12));
      expect(niceDiagramStep(1.2), 2);
      expect(niceDiagramStep(7), 10);
      expect(niceDiagramStep(0), 1);
    });
  });

  group('diagram widget', () {
    Widget host(Widget child, {double width = 800}) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: SingleChildScrollView(child: child),
              ),
            ),
          ),
        );

    testWidgets('route and polar diagrams paint with a screen-reader summary', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      final route = buildPlaygroundDiagram(
        bugRouteConfig,
        bugResult(total: 12.5),
        parameterNames: bugParameters,
      )!;
      await tester.pumpWidget(host(PlaygroundDiagram(data: route)));

      expect(find.byKey(const Key('playground-diagram-canvas')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Route diagram. Points: S at')), findsOneWidget);
      expect(find.textContaining('you returned 11.0'), findsNothing);
      expect(find.textContaining('you returned 12.5'), findsOneWidget);
      expect(find.byKey(const Key('playground-diagram-hint')), findsOneWidget);
      expect(tester.takeException(), isNull);

      final polar = buildPlaygroundDiagram(vfhConfig, vfhResult())!;
      await tester.pumpWidget(host(PlaygroundDiagram(data: polar)));
      expect(find.bySemanticsLabel(RegExp('Polar diagram with 4')), findsOneWidget);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('a problem replaces the canvas with guidance', (
      WidgetTester tester,
    ) async {
      final diagram = buildPlaygroundDiagram(
        bugRouteConfig,
        bugResult(arguments: const [1, 2]),
        parameterNames: bugParameters,
      )!;
      await tester.pumpWidget(host(PlaygroundDiagram(data: diagram)));

      expect(find.byKey(const Key('playground-diagram-problem')), findsOneWidget);
      expect(find.byKey(const Key('playground-diagram-canvas')), findsNothing);
      expect(find.textContaining('start should be a pair of numbers'), findsOneWidget);
    });

    testWidgets('diagrams fit a 360 pixel phone without overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final data in [
        buildPlaygroundDiagram(elevatorConfig, elevatorResult(label: 'Service Elevator'))!,
        buildPlaygroundDiagram(vfhConfig, vfhResult())!,
      ]) {
        await tester.pumpWidget(host(PlaygroundDiagram(data: data), width: 296));
        expect(tester.takeException(), isNull);
        final size = tester.getSize(find.byKey(const Key('playground-diagram-canvas')));
        expect(size.width, lessThanOrEqualTo(296));
        expect(size.width, size.height);
      }
    });

    testWidgets('coincident and tiny-range points still paint', (
      WidgetTester tester,
    ) async {
      final same = buildPlaygroundDiagram(
        bugRouteConfig,
        bugResult(arguments: const [
          [1, 1],
          [1, 1],
          [1, 1],
          [1, 1],
          [1, 1],
        ]),
      )!;
      await tester.pumpWidget(host(PlaygroundDiagram(data: same)));
      expect(tester.takeException(), isNull);

      final tiny = buildPlaygroundDiagram(
        bugRouteConfig,
        bugResult(arguments: const [
          [0, 0],
          [0.0001, 0],
          [0.0001, 0.0002],
          [0.0003, 0.0002],
          [0.0004, 0.0004],
        ]),
      )!;
      await tester.pumpWidget(host(PlaygroundDiagram(data: tiny)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Try inputs shows the diagram under the returned values', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaygroundDialog(
              assignmentId: 1,
              functionName: 'calculate_bug2_route',
              code: 'def calculate_bug2_route(start, hit, corner, leave, goal):\n'
                  '    return 0.0, 0.0, 0.0, 0.0',
              simulationConfig: bugRouteConfig,
              runner: (_, __, ___) async => bugResult(),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('playground-run-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playground-values')), findsOneWidget);
      expect(find.byKey(const Key('playground-diagram')), findsOneWidget);
      expect(find.text('Drawn to scale from your inputs.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('assignments without a diagram show no diagram', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaygroundDialog(
              assignmentId: 1,
              functionName: 'calculate_bug2_route',
              code: 'def calculate_bug2_route(a):\n    return 1',
              runner: (_, __, ___) async => bugResult(),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('playground-run-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playground-diagram')), findsNothing);
    });
  });

  test('playground results parse echoed arguments', () {
    final parsed = PlaygroundResultDto.fromJson({
      'success': true,
      'call': 'f()',
      'arguments': [
        [1, 2],
        {'0': 10},
      ],
    });
    expect(parsed.arguments, [
      [1, 2],
      {'0': 10},
    ]);
    expect(
      PlaygroundResultDto.fromJson({'success': true, 'call': 'f()'}).arguments,
      isEmpty,
    );
  });
}
