import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/lesson_reader.dart';

void main() {
  testWidgets('outline preserves authored content and jumps to a heading',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: LessonReader(
                    html:
                        '<h2 id="intro">Sensors &amp; robots</h2><p>Readings stay unchanged.</p>'
                        '${List.filled(30, '<p>Robot navigation practice</p>').join()}'
                        '<h2>Safe movement</h2><p>Stop for an obstacle.</p>')))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lesson-outline')), findsOneWidget);
    final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html;
    expect(html, contains('id="intro"'));
    expect(html, contains('Stop for an obstacle.'));
    await tester.tap(find.text('On this page'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Safe movement'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
        tester.getTopLeft(find.text('Safe movement').last).dy, lessThan(600));
  });
  testWidgets('heading-free content is not given a fake outline',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: LessonReader(html: '<p>All original lesson text.</p>'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lesson-outline')), findsNothing);
    expect(find.text('All original lesson text.', findRichText: true),
        findsOneWidget);
  });
}
