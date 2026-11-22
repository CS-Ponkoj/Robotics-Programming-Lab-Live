import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/main.dart' as app;
import 'package:iuse_demo/theme/app_theme.dart';

Future<Rect> _showAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (context, child) => app.bottomRightSnackBars(context, child!),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Saved.'))),
          child: const Text('Show'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Show'));
  await tester.pumpAndSettle();
  // The visible card, inside the SnackBar's margins.
  return tester.getRect(find
      .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
      .first);
}

void main() {
  testWidgets('notifications sit in the bottom-right corner on desktops',
      (tester) async {
    final rect = await _showAt(tester, const Size(1400, 800));
    expect(rect.right, closeTo(1400 - 16, 1));
    expect(rect.width, closeTo(420, 1));
    expect(rect.bottom, closeTo(800 - 16, 1));
  });

  testWidgets('phones show them full width above the Feedback button',
      (tester) async {
    final rect = await _showAt(tester, const Size(390, 844));
    expect(rect.left, closeTo(16, 1));
    expect(rect.bottom, closeTo(844 - 64, 1));
  });
}
