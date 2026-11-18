import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iuse_demo/main.dart' as app;
import 'package:iuse_demo/models/simulation_trace.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/robot_sim_panel.dart';
import 'package:iuse_demo/widgets/robot_sim_sensors.dart';
import 'package:iuse_demo/widgets/robot_sim_view.dart';
import 'package:iuse_demo/widgets/run_terminal.dart';

/// A small replay: drive 0.7 m toward a wall at 1.2 m, stop, the wall slides
/// away, and the robot drives again.
Map<String, dynamic> replayJson() {
  final frames = <Map<String, dynamic>>[];
  for (var i = 0; i <= 40; i++) {
    final t = i * 0.2;
    final x = t < 3.5 ? 0.2 * t : (t < 4.6 ? 0.7 : 0.7 + 0.2 * (t - 4.6));
    final wall = t < 4.5 ? 1.2 : 2.7;
    frames.add({
      't': t,
      'x': x,
      'y': 0.0,
      'theta': 0.0,
      'linear': (t >= 3.5 && t < 4.6) ? 0.0 : 0.2,
      'angular': 0.0,
      'front': wall - x,
      'ranges': [
        for (var beam = 0; beam < 31; beam++) beam == 15 ? wall - x : null,
      ],
    });
  }
  return {
    'scan': {
      'angle_min_deg': -135.0,
      'angle_increment_deg': 9.0,
      'range_max': 10.0
    },
    'robot_radius': 0.15,
    'walls': [
      [1.2, -3.0, 1.2, 3.0],
    ],
    'frames': frames,
    'events': [
      {'t': 0.0, 'type': 'started'},
      {'t': 3.5, 'type': 'stopped', 'front': 0.5},
      {
        't': 4.5,
        'type': 'wall_moved',
        'walls': [
          [2.7, -3.0, 2.7, 3.0],
        ],
      },
      {'t': 4.6, 'type': 'resumed'},
      {'t': 8.0, 'type': 'finished'},
    ],
    'outcome': 'stopped_and_resumed',
    'duration_seconds': 8.0,
  };
}

Map<String, dynamic> resultJson(
        {Map<String, dynamic>? replay, String error = ''}) =>
    {
      'assignment_version': 3,
      'success': replay != null,
      'error': error,
      'output': 'Simulated 8.0 s: stopped and resumed.',
      'simulation': replay,
    };

Widget host(Widget child,
    {Size size = const Size(520, 900), bool reduceMotion = false}) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: reduceMotion),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('simulation model', () {
    test('parses a replay and follows the wall as it moves', () {
      final result =
          SimulationResultDto.fromJson(resultJson(replay: replayJson()));
      final replay = result.replay!;
      expect(result.success, isTrue);
      expect(replay.frames, hasLength(41));
      expect(replay.frames.first.ranges.first, isNull);
      expect(replay.frameAt(3.55).t, closeTo(3.4, 1e-9));
      expect(replay.wallsAt(1.0).single.first, 1.2);
      expect(replay.wallsAt(5.0).single.first, 2.7);
      expect(replay.summary, contains('stopped 0.50 m from the wall at 3.5 s'));
      expect(replay.summary, contains('drove again'));
    });

    test('a failed node has no replay and keeps its error', () {
      final result = SimulationResultDto.fromJson(
          resultJson(error: 'Your node stopped with an error:\nNameError'));
      expect(result.success, isFalse);
      expect(result.replay, isNull);
      expect(result.error, contains('NameError'));
      expect(() => SimulationResultDto.fromJson({'success': true}),
          throwsFormatException);
    });

    test('each outcome is explained in plain words', () {
      String summary(String outcome) =>
          SimulationReplay.fromJson({...replayJson(), 'outcome': outcome})!
              .summary;
      expect(summary('collided'), contains('hit the wall'));
      expect(summary('never_moved'), contains('never moved'));
      expect(summary('kept_driving'), contains('still driving'));
    });

    test('a crash after a stop does not claim the robot never stopped', () {
      final json = replayJson();
      final events = [
        ...(json['events'] as List),
        {'t': 6.2, 'type': 'collided'},
      ];
      final replay = SimulationReplay.fromJson(
          {...json, 'events': events, 'outcome': 'collided'})!;
      expect(replay.summary, isNot(contains('without stopping')));
      expect(
        replay.summary,
        'The robot stopped 0.50 m from the wall at 3.5 s, drove again after '
        'the wall moved away, then hit the wall at 6.2 s.',
      );

      final straight = SimulationReplay.fromJson({
        ...json,
        'events': [
          {'t': 0.0, 'type': 'started'},
          {'t': 2.1, 'type': 'collided'},
        ],
        'outcome': 'collided',
      })!;
      expect(straight.summary,
          'The robot hit the wall at 2.1 s without stopping.');
    });

    test('terminal shows the error with the student line and a summary', () {
      final failed = buildSimulationTerminalLines(
        SimulationResultDto.fromJson(resultJson(
          error:
              'Your node stopped with an error:\ncontroller.py, line 27, in build_node\n'
              '    undefined_name\nNameError: name is not defined',
        )),
        'controller.py',
      );
      expect(failed.first.kind, TerminalLineKind.command);
      expect(failed.where((line) => line.line == 27), hasLength(1));
      expect(failed.last.text, contains('NameError'));
      final passed = buildSimulationTerminalLines(
        SimulationResultDto.fromJson(resultJson(replay: replayJson())),
        'controller.py',
      );
      expect(passed.last.kind, TerminalLineKind.info);
      expect(passed.last.text, contains('drove again'));
    });
  });

  group('replay view', () {
    testWidgets('plays, pauses, scrubs, and reports what the robot did',
        (tester) async {
      tester.view.physicalSize = const Size(520, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final replay = SimulationReplay.fromJson(replayJson())!;
      await tester.pumpWidget(host(RobotSimView(replay: replay)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byTooltip('Pause replay'), findsOneWidget);
      expect(find.byKey(const ValueKey('robot-sim-telemetry')), findsOneWidget);
      expect(find.bySemanticsLabel('linear.x 0.20 m/s'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Ahead \d')), findsOneWidget);
      expect(find.byKey(const ValueKey('robot-sim-summary')), findsOneWidget);
      expect(
        find.bySemanticsLabel(
            RegExp('Robot simulation replay. The robot stopped')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('robot-sim-play')));
      await tester.pump();
      expect(find.byTooltip('Play replay'), findsOneWidget);

      // Drag the slider most of the way: the robot is stopped there.
      final slider = find.byKey(const ValueKey('robot-sim-scrub'));
      await tester.drag(slider, Offset(tester.getSize(slider).width * 0.4, 0));
      await tester.pump();
      expect(find.byTooltip('Play replay'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('robot-sim-restart')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Time 8.0 seconds'), findsOneWidget);
      expect(find.textContaining('Drove again'), findsOneWidget);
    });

    testWidgets('reduced motion shows the final position without playing',
        (tester) async {
      tester.view.physicalSize = const Size(520, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final replay = SimulationReplay.fromJson(replayJson())!;
      await tester
          .pumpWidget(host(RobotSimView(replay: replay), reduceMotion: true));
      await tester.pump();
      expect(find.byTooltip('Play replay'), findsOneWidget);
      expect(find.bySemanticsLabel('Time 8.0 seconds'), findsOneWidget);
    });

    testWidgets('switches to the LiDAR, chart, and ranges views',
        (tester) async {
      tester.view.physicalSize = const Size(520, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final replay = SimulationReplay.fromJson(replayJson())!;
      await tester.pumpWidget(host(RobotSimView(replay: replay)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('robot-sim-canvas')), findsOneWidget);

      await tester.tap(find.text('LiDAR'));
      await tester.pump();
      expect(find.byKey(const ValueKey('robot-sim-lidar')), findsOneWidget);
      expect(find.byKey(const ValueKey('robot-sim-canvas')), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^LiDAR scan .*Closest reading')),
          findsOneWidget);
      expect(find.text('[45] ahead'), findsOneWidget);

      await tester.tap(find.text('Charts'));
      await tester.pump();
      expect(find.byKey(const ValueKey('robot-sim-charts')), findsOneWidget);

      await tester.tap(find.text('Ranges'));
      await tester.pump();
      expect(find.byKey(const ValueKey('robot-sim-ranges')), findsOneWidget);
      expect(find.text('ranges[45]'), findsOneWidget);
      expect(find.text('ranges[0]'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('summarises the scan by side and nearest reading', () {
      final replay = SimulationReplay.fromJson(replayJson())!;
      final frame = SimulationFrame(
        t: 0,
        x: 0,
        y: 0,
        theta: 0,
        linear: 0,
        angular: 0,
        ranges: [
          for (var beam = 0; beam < 31; beam++)
            beam == 2 ? 0.9 : (beam == 15 ? 1.4 : (beam == 28 ? 2.0 : null)),
        ],
      );
      final summary = ScanSummary.of(replay, frame);
      expect(summary.right, 0.9);
      expect(summary.ahead, 1.4);
      expect(summary.left, 2.0);
      expect(summary.closest, 0.9);
      expect(summary.closestAngle, -117);
      expect(summary.closestIndex, 6);
      expect(sourceIndex(replay, 15), 45);
    });

    testWidgets('the docked divider resizes with the arrow keys',
        (tester) async {
      var fraction = kSimDockDefault;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SimDockDivider(
              fraction: fraction,
              columnHeight: 900,
              onChanged: (value) => setState(() => fraction = value),
            ),
          ),
        ),
      ));
      Focus.of(tester.element(find.byKey(const Key('robot-sim-dock-divider'))))
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(fraction, closeTo(kSimDockDefault + 0.05, 1e-9));
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
      }
      await tester.pump();
      expect(fraction, kSimDockMin);
    });

    testWidgets('fits a 320 px phone without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final replay = SimulationReplay.fromJson(replayJson())!;
      await tester.pumpWidget(
          host(RobotSimView(replay: replay), size: const Size(320, 800)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('robot-sim-canvas')), findsOneWidget);
    });
  });

  group('workspace', () {
    MockClient client({
      required Map<String, dynamic> simulationConfig,
      required List<String> simulated,
      Completer<http.Response>? simulateResponse,
    }) {
      return MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/assignments/7') {
          return http.Response(
            jsonEncode({
              'id': 7,
              'title': 'Assignment 7: Stop Before the Wall',
              'description': 'Wall stop.',
              'assignment_html': '<p>Stop before the wall.</p>',
              'starter_code': 'def build_node():\n    return None\n',
              'language': 'python-ros2',
              'vals': <String, dynamic>{},
              'simulation_config': simulationConfig,
            }),
            200,
          );
        }
        if (request.url.path == '/assignments/7/simulate') {
          simulated.add(request.body);
          if (simulateResponse != null) return simulateResponse.future;
          return http.Response(
              jsonEncode(resultJson(replay: replayJson())), 200);
        }
        return http.Response('{}', 404);
      });
    }

    Widget workspace({Size size = const Size(1400, 1000)}) => MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: const app.MyHomePage(title: 'Assignment 7', id: 7),
          ),
        );

    void useScreen(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    void clearProgress() {
      final progress = app.learningProgress;
      progress.latestScores.clear();
      progress.bestScores.clear();
      progress.attemptCounts.clear();
      progress.codeDrafts.clear();
      progress.codeDraftVersions.clear();
      progress.submissionIds.clear();
      progress.unsyncedDrafts.clear();
      progress.revealedSolutions.clear();
    }

    testWidgets('Simulate appears only for a ros2_2d simulation',
        (tester) async {
      final simulated = <String>[];
      final mock =
          client(simulationConfig: {'enabled': false}, simulated: simulated);
      addTearDown(mock.close);
      addTearDown(clearProgress);
      await http.runWithClient(() async {
        await tester.pumpWidget(workspace());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('simulate-button')), findsNothing);
        expect(find.byKey(const Key('robot-sim-panel')), findsNothing);
        expect(find.byKey(const Key('run-tests-button')), findsOneWidget);
      }, () => mock);
    });

    testWidgets('the square panel opens as its own window and replays',
        (tester) async {
      useScreen(tester, const Size(1400, 1000));
      final simulated = <String>[];
      final pending = Completer<http.Response>();
      final mock = client(
        simulationConfig: {'enabled': true, 'provider': 'ros2_2d'},
        simulated: simulated,
        simulateResponse: pending,
      );
      addTearDown(mock.close);
      addTearDown(clearProgress);
      await http.runWithClient(() async {
        await tester.pumpWidget(workspace());
        await tester.pumpAndSettle();
        final panel = find.byKey(const Key('robot-sim-panel'));
        expect(panel, findsOneWidget);
        // Its own window at the top right, with a drag grip, collapsed to
        // its header so it does not cover the instructions before a run.
        expect(find.byKey(const Key('robot-sim-grip')), findsOneWidget);
        expect(tester.getRect(panel).right, closeTo(1400 - 24, 2));
        expect(tester.getSize(panel).height, 48);
        expect(find.text('Watch your robot'), findsNothing);
        expect(find.text('Ready'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('simulate-button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(simulated, hasLength(1));
        expect(jsonDecode(simulated.single)['code'], contains('build_node'));
        expect(find.text('Running your node on the robot…'), findsOneWidget);
        // Simulate opens the window: header and view switch above a square.
        expect(tester.getSize(panel).width,
            closeTo(tester.getSize(panel).height - 92, 1));
        expect(find.text('Running'), findsOneWidget);
        // Results stays closed: it holds test results only.
        expect(find.byKey(const Key('assignment-results-panel')), findsNothing);
        final button = tester.widget(find.byKey(const Key('simulate-button')));
        expect(
          button is IconButton
              ? button.onPressed
              : (button as ButtonStyleButton).onPressed,
          isNull,
        );

        pending.complete(
            http.Response(jsonEncode(resultJson(replay: replayJson())), 200));
        await tester.pumpAndSettle();
        expect(
            find.descendant(
                of: panel,
                matching: find.byKey(const ValueKey('robot-sim-view'))),
            findsOneWidget);
        final canvas =
            tester.getSize(find.byKey(const ValueKey('robot-sim-canvas')));
        expect(canvas.width, closeTo(canvas.height, 1)); // square
        expect(find.textContaining('drove again after the wall moved away'),
            findsWidgets);

        // Collapse to the header and live readings, then expand again.
        await tester.tap(find.byKey(const Key('robot-sim-collapse')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('robot-sim-view')), findsNothing);
        expect(find.byKey(const ValueKey('robot-sim-strip')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp(r'^linear\.x ')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('robot-sim-collapse')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('robot-sim-view')), findsOneWidget);
      }, () => mock);
    });

    testWidgets('the window moves, resizes, docks, and opens full screen',
        (tester) async {
      useScreen(tester, const Size(1400, 1000));
      final simulated = <String>[];
      final mock = client(
        simulationConfig: {'enabled': true, 'provider': 'ros2_2d'},
        simulated: simulated,
      );
      addTearDown(mock.close);
      addTearDown(clearProgress);
      await http.runWithClient(() async {
        await tester.pumpWidget(workspace());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('simulate-button')));
        await tester.pumpAndSettle();
        final panel = find.byKey(const Key('robot-sim-panel'));
        final instructions =
            find.byKey(const Key('assignment-instructions-panel'));
        final floatingInstructionsTop = tester.getRect(instructions).top;
        final before = tester.getRect(panel).topLeft;
        await tester.drag(
            find.byKey(const Key('robot-sim-grip')), const Offset(-160, 60));
        await tester.pumpAndSettle();
        // The drag moves the window (less Flutter's small drag threshold).
        final moved = tester.getRect(panel).topLeft - before;
        expect(moved.dx, lessThan(-100));
        expect(moved.dy, greaterThan(30));
        final width = tester.getSize(panel).width;
        await tester.drag(
            find.byKey(const Key('robot-sim-resize')), const Offset(80, 80));
        await tester.pumpAndSettle();
        expect(tester.getSize(panel).width, greaterThan(width));

        await tester.tap(find.byKey(const Key('robot-sim-fullscreen')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('robot-sim-close')), findsOneWidget);
        expect(find.byKey(const ValueKey('robot-sim-summary')), findsWidgets);
        await tester.tap(find.byKey(const Key('robot-sim-close')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('robot-sim-close')), findsNothing);

        // Dock above the instructions, then pop out again.
        await tester.tap(find.byKey(const Key('robot-sim-pop-out')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('robot-sim-grip')), findsNothing);
        expect(tester.getRect(panel).bottom,
            lessThanOrEqualTo(tester.getRect(instructions).top + 1));
        expect(tester.getRect(instructions).top,
            greaterThan(floatingInstructionsTop));
        // Docked in a wide, short space: the picture sits beside the
        // readings and stays square.
        final dockedCanvas =
            tester.getSize(find.byKey(const ValueKey('robot-sim-canvas')));
        expect(dockedCanvas.width, closeTo(dockedCanvas.height, 1));
        expect(
            tester
                .getRect(find.byKey(const ValueKey('robot-sim-canvas')))
                .right,
            lessThan(tester
                .getRect(find.byKey(const ValueKey('robot-sim-view-switch')))
                .left));
        // The divider shares the column with the instructions.
        final divider = find.byKey(const Key('robot-sim-dock-divider'));
        final dockedHeight = tester.getSize(panel).height;
        await tester.drag(divider, const Offset(0, 120));
        await tester.pumpAndSettle();
        expect(tester.getSize(panel).height, greaterThan(dockedHeight + 60));
        await tester.drag(divider, const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(tester.getSize(panel).height, lessThan(dockedHeight));
        expect(tester.getRect(instructions).height, greaterThan(400));
        await tester.tap(find.byKey(const Key('robot-sim-pop-out')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('robot-sim-grip')), findsOneWidget);
        expect(tester.getRect(instructions).top,
            closeTo(floatingInstructionsTop, 1));
      }, () => mock);
    });

    testWidgets('phones get a Simulation tab', (tester) async {
      useScreen(tester, const Size(390, 844));
      final simulated = <String>[];
      final mock = client(
        simulationConfig: {'enabled': true, 'provider': 'ros2_2d'},
        simulated: simulated,
      );
      addTearDown(mock.close);
      addTearDown(clearProgress);
      await http.runWithClient(() async {
        await tester.pumpWidget(workspace(size: const Size(390, 844)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('robot-sim-panel')), findsNothing);
        await tester.tap(find.byKey(const Key('simulate-button')));
        await tester.pumpAndSettle();
        // Simulate jumps to the Simulation tab and shows the replay.
        expect(find.byKey(const Key('robot-sim-panel')), findsOneWidget);
        expect(find.byKey(const ValueKey('robot-sim-view')), findsOneWidget);
        expect(find.byKey(const Key('robot-sim-pop-out')), findsNothing);
        await tester.tap(find.text('Code'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('robot-sim-panel')), findsNothing);
        await tester.tap(find.text('Simulation').last);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('robot-sim-view')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, () => mock);
    });

    testWidgets('a node that fails shows its error instead of a replay',
        (tester) async {
      useScreen(tester, const Size(1400, 1000));
      final simulated = <String>[];
      final pending = Completer<http.Response>();
      final mock = client(
        simulationConfig: {'enabled': true, 'provider': 'ros2_2d'},
        simulated: simulated,
        simulateResponse: pending,
      );
      addTearDown(mock.close);
      addTearDown(clearProgress);
      await http.runWithClient(() async {
        await tester.pumpWidget(workspace());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('simulate-button')));
        await tester.pump();
        pending.complete(http.Response(
            jsonEncode(resultJson(
                error:
                    'build_node() returned None or something that is not a ROS node.')),
            200));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('simulation-error')), findsOneWidget);
        expect(find.textContaining('build_node() returned None'), findsWidgets);
        // The chip says there is no replay rather than "Replay".
        expect(find.text('No replay'), findsOneWidget);
        expect(find.text('Replay'), findsNothing);
      }, () => mock);
    });
  });
}
