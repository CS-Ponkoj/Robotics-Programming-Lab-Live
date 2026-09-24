import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/languages/python.dart';
import 'package:iuse_demo/editor/editor_tools.dart';
import 'package:iuse_demo/models/assignment_dto.dart';

void main() {
  test('Tab indents every selected line without replacing the selection', () {
    final controller = CodeController(
      language: python,
      text: 'first = 1\nsecond = 2',
      params: EditorParams(tabSpaces: 4),
    );
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 20);

    final handled = handleEditorKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.tab,
        logicalKey: LogicalKeyboardKey.tab,
        timeStamp: Duration.zero,
      ),
      controller,
      editorHasFocus: true,
      editable: true,
      pressedKeys: {LogicalKeyboardKey.tab},
    );

    expect(handled, isTrue);
    expect(controller.fullText, '    first = 1\n    second = 2');
  });

  test('Shift+Tab outdents every selected line', () {
    final controller = CodeController(
      language: python,
      text: '    first = 1\n    second = 2',
      params: EditorParams(tabSpaces: 4),
    );
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 28);

    handleEditorKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.tab,
        logicalKey: LogicalKeyboardKey.tab,
        timeStamp: Duration.zero,
      ),
      controller,
      editorHasFocus: true,
      editable: true,
      pressedKeys: {
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.tab,
      },
    );

    expect(controller.fullText, 'first = 1\nsecond = 2');
  });

  test('Control+Y invokes the editor redo history', () async {
    final controller = CodeController(language: python, text: 'value = 1');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 9);
    controller.value = const TextEditingValue(
      text: 'value = 1\nprint(value)',
      selection: TextSelection.collapsed(offset: 22),
    );
    controller.historyController.undo();
    expect(controller.fullText, 'value = 1');

    final handled = handleEditorKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyY,
        logicalKey: LogicalKeyboardKey.keyY,
        timeStamp: Duration.zero,
      ),
      controller,
      editorHasFocus: true,
      editable: true,
      pressedKeys: {
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyY,
      },
    );

    expect(handled, isTrue);
    expect(controller.fullText, 'value = 1\nprint(value)');
  });

  test('Control+S saves only while an editable code file has focus', () {
    const saveEvent = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyS,
      logicalKey: LogicalKeyboardKey.keyS,
      timeStamp: Duration.zero,
    );
    final controlKeys = {
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyS,
    };

    expect(
      isEditorSaveShortcut(
        saveEvent,
        editorHasFocus: true,
        editable: true,
        pressedKeys: controlKeys,
      ),
      isTrue,
    );
    expect(
      isEditorSaveShortcut(
        saveEvent,
        editorHasFocus: false,
        editable: true,
        pressedKeys: controlKeys,
      ),
      isFalse,
    );
    expect(
      isEditorSaveShortcut(
        saveEvent,
        editorHasFocus: true,
        editable: false,
        pressedKeys: controlKeys,
      ),
      isFalse,
    );
    expect(
      isEditorSaveShortcut(
        saveEvent,
        editorHasFocus: true,
        editable: true,
        pressedKeys: {LogicalKeyboardKey.keyS},
      ),
      isFalse,
    );
  });

  test('error line parser uses the last valid Python traceback line', () {
    expect(
      extractPythonErrorLine(
        'File "student.py", line 2\nFile "student.py", line 7',
        8,
      ),
      7,
    );
    expect(extractPythonErrorLine('Timeout', 8), isNull);
    expect(extractPythonErrorLine('line 99', 8), isNull);
  });

  test('completion vocabulary includes starter functions and ROS APIs', () {
    const assignment = AssignmentDto(
      id: 5,
      title: 'ROS',
      description: '',
      htmlDesc: '',
      code:
          'from geometry_msgs.msg import Twist\n\ndef move_robot(speed):\n    pass',
      vals: {},
    );

    final completions = assignmentCompletionWords(assignment);
    expect(completions, containsAll(['move_robot', 'speed', 'Twist', 'rclpy']));
    expect(
      assignmentApiReference(assignment),
      containsAll(
          ['from geometry_msgs.msg import Twist', 'def move_robot(speed)']),
    );
  });
}
