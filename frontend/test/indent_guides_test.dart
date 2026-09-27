import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/editor/indent_guides.dart';

void main() {
  test('indentation depth counts spaces and tabs without altering text', () {
    expect(indentationDepth('def route():'), 0);
    expect(indentationDepth('    if clear:'), 1);
    expect(indentationDepth('        return True'), 2);
    expect(indentationDepth('\treturn True'), 1);
  });

  testWidgets('editor mounts a noninteractive guide layer', (tester) async {
    final controller = CodeController(text: 'first\n    second');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 100,
          child: EditorIndentGuides(
            controller: controller,
            fontSize: 16,
            color: Colors.white,
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    ));

    expect(find.byKey(const Key('editor-indent-guides')), findsOneWidget);
    expect(find.byType(IgnorePointer), findsWidgets);
    expect(controller.text, 'first\n    second');
  });
}
