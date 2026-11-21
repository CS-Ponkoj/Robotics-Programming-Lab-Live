import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/widgets/lesson_code_block.dart';

List<TextSpan> _flat(List<TextSpan> spans) => [
      for (final span in spans) ...[
        if (span.text != null) span,
        ..._flat((span.children ?? const []).cast<TextSpan>()),
      ],
    ];

void main() {
  test('Python keywords, strings, numbers and comments get their colours', () {
    final spans = _flat(highlightPython(
        "def build_node():\n    node = rclpy.create_node('demo')  # make it\n    return 10"));
    TextSpan find(String text) => spans.firstWhere((s) => s.text!.contains(text));
    expect(find('def').style?.color, LessonCodeColors.definition);
    expect(find('def').style?.fontStyle, FontStyle.italic);
    expect(find('return').style?.color, LessonCodeColors.keyword);
    expect(find("'demo'").style?.color, LessonCodeColors.string);
    expect(find('10').style?.color, LessonCodeColors.number);
    expect(find('# make it').style?.color, LessonCodeColors.comment);
    // Highlighting never loses or reorders characters.
    expect(spans.map((s) => s.text).join(),
        "def build_node():\n    node = rclpy.create_node('demo')  # make it\n    return 10");
  });

  testWidgets('code card shows window dots, one number per line and copies',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: LessonCodeBlock(code: 'import rclpy\n\nprint(1)'))));
    expect(find.text('1\n2\n3'), findsOneWidget);
    expect(find.byKey(const Key('lesson-code-copy')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
