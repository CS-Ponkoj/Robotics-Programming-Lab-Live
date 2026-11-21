import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/lesson_animation.dart';
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
  testWidgets('outline lists main sections, or subsections when there are few',
      (tester) async {
    Future<List<String>> outline(String html) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: LessonReader(key: ValueKey(html), html: html)))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('On this page'));
      await tester.pumpAndSettle();
      return tester
          .widgetList<ListTile>(find.byType(ListTile))
          .skip(1) // The "On this page" header is a ListTile too.
          .map((tile) => (tile.title as Text).data!)
          .toList();
    }

    expect(
        await outline(
            '<h2>One</h2><h3>One detail</h3><h2>Two</h2><h4>Label</h4>'),
        ['One', 'Two']);
    expect(await outline('<h2>Title</h2><h3>Part A</h3><h3>Part B</h3>'),
        ['Title', 'Part A', 'Part B']);
  });

  test('lesson styles give tables a header and equations a math face', () {
    final table = lessonStyles(dom.Element.tag('th'));
    expect(table?['background-color'], isNotNull);
    final math =
        lessonStyles(dom.Element.tag('span')..classes.add('math-expression'));
    expect(math?['font-style'], 'italic');
    expect(lessonStyles(dom.Element.tag('div')), isNull);
  });

  testWidgets(
      'code blocks copy, tools appear in place, animations start stopped',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
            body: SingleChildScrollView(
                child: LessonReader(
                    html: '<p>Before</p>'
                        '<pre><code>def build_node():\n    return node</code></pre>'
                        '<div class="lesson-interactive" data-interactive="wheel-speeds"></div>'
                        '<figure class="lesson-animation"><img src="still.png" '
                        'data-animation="moving.gif" alt="A beam sweeps a room." />'
                        '<figcaption>Animation 4.</figcaption></figure>')))));
    await tester.pump();
    expect(find.byKey(const Key('lesson-code-copy')), findsOneWidget);
    expect(find.text('def build_node():\n    return node'), findsOneWidget);
    expect(find.byKey(const Key('try-wheel-speeds')), findsOneWidget);
    final animation =
        tester.widget<LessonAnimation>(find.byType(LessonAnimation));
    expect(animation.stillUrl, 'still.png');
    expect(animation.animationUrl, 'moving.gif');
    expect(find.text('Play animation'), findsOneWidget);
    expect(
        find.bySemanticsLabel(RegExp('A beam sweeps a room. Animation stopped.')),
        findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('lesson-animation-toggle')));
    await tester.tap(find.byKey(const Key('lesson-animation-toggle')));
    await tester.pump();
    expect(find.text('Stop animation'), findsOneWidget);
    expect(
        find.bySemanticsLabel(RegExp('Animation playing.')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lesson-animation-toggle')));
    await tester.pump();
    expect(find.text('Play animation'), findsOneWidget);
  });
}
