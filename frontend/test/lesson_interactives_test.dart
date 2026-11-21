import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/lesson_interactives.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('formulas match the lesson worked examples', () {
    test('index to direction and back (Section 4.2, Worked example A)', () {
      expect(scanAngle(-0.6, 0.2, 3), closeTo(0.0, 1e-12));
      expect(scanAngle(-0.6, 0.2, 6), closeTo(0.6, 1e-12));
      // (0.33 + 0.6) / 0.2 = 4.65, nearest reading 5.
      expect(scanIndexFor(0.33, -0.6, 0.2, 7), 5);
      // +0.9 gives 7.5, past the last index (6): outside the sweep.
      expect(scanIndexFor(0.9, -0.6, 0.2, 7), isNull);
      expect(scanIndexFor(-0.7, -0.6, 0.2, 7), isNull);
    });

    test('the float32 end of a scan stays inside the sweep', () {
      double f32(double value) =>
          (Float32List(1)..[0] = value)[0].toDouble();
      // The stored angle_max of Worked example A gives about 6.00000015.
      expect(scanIndexFor(f32(0.6), f32(-0.6), f32(0.2), 7), 6);
    });

    test('the lab scan points index 45 straight ahead (Worked example B)', () {
      final min = -135 * math.pi / 180, step = 3 * math.pi / 180;
      expect(scanAngle(min, step, 45), closeTo(0, 1e-12));
      expect(scanAngle(min, step, 90), closeTo(135 * math.pi / 180, 1e-12));
    });

    test('unicycle pose after 3 s at 0.15 m/s and 0.4 rad/s (Figure 8)', () {
      final pose = unicyclePose(0.15, 0.4, 3);
      expect(pose.theta, closeTo(1.2, 1e-12)); // about 69 degrees
      expect(pose.x, closeTo(0.3495, 0.0001));
      expect(pose.y, closeTo(0.2391, 0.0001));
      final straight = unicyclePose(0.15, 0, 3);
      expect(straight.x, closeTo(0.45, 1e-12));
      expect(straight.y, 0);
    });

    test('wheel speeds (Section 5.4 and the math page)', () {
      final curve = wheelSpeeds(0.15, 0.4, 0.30);
      expect(curve.right, closeTo(0.21, 1e-12));
      expect(curve.left, closeTo(0.09, 1e-12));
      final spot = wheelSpeeds(0, 0.4, 0.30);
      expect(spot.right, closeTo(0.06, 1e-12));
      expect(spot.left, closeTo(-0.06, 1e-12));
    });
  });

  testWidgets('scan explorer finds the lab scan middle and rejects outside directions',
      (tester) async {
    await tester.pumpWidget(_host(const ScanIndexExplorer()));
    expect(find.text('Reading [3] points at 0.000 rad (0.0°).'), findsOneWidget);
    expect(find.textContaining('nearest reading [5]'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('try-scan-direction')), '0.9');
    await tester.pump();
    expect(find.textContaining('outside the sweep'), findsOneWidget);
    await tester.tap(find.byKey(const Key('try-scan-lab')));
    await tester.pump();
    expect(find.text('Reading [45] points at 0.000 rad (0.0°).'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('twist viewer reports the pose and the turn direction',
      (tester) async {
    await tester.pumpWidget(_host(const TwistPathViewer()));
    expect(
        find.text('After 3.0 s: x = 0.350 m, y = 0.239 m, heading turned '
            '1.200 rad (68.8°), turning left (counterclockwise).'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wheel calculator updates and explains the motion',
      (tester) async {
    await tester.pumpWidget(_host(const WheelSpeedCalculator()));
    expect(find.textContaining('v_right = 0.210 m/s, v_left = 0.090 m/s'),
        findsOneWidget);
    await tester.enterText(find.byKey(const Key('try-wheel-v')), '0');
    await tester.pump();
    expect(find.textContaining('turns on the spot'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('try-wheel-l')), '0');
    await tester.pump();
    expect(find.textContaining('L must be positive'), findsOneWidget);
  });

  testWidgets('tools fit a phone screen without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final name in ['scan-index', 'twist-path', 'wheel-speeds']) {
      await tester.pumpWidget(_host(lessonInteractive(name)!));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: name);
    }
    expect(lessonInteractive('unknown'), isNull);
  });
}
