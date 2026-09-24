import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:iuse_demo/models/assignment_dto.dart';

const pythonCompletionWords = <String>[
  'abs',
  'all',
  'any',
  'bool',
  'dict',
  'enumerate',
  'float',
  'int',
  'len',
  'list',
  'map',
  'max',
  'min',
  'print',
  'range',
  'round',
  'set',
  'str',
  'sum',
  'tuple',
  'zip',
  'math',
  'rclpy',
  'Node',
  'Twist',
  'LaserScan',
  'create_publisher',
  'create_subscription',
  'create_timer',
];

List<String> assignmentCompletionWords(AssignmentDto assignment) {
  final source = <String>[
    assignment.code,
    ...assignment.projectFiles.map((file) => file.content),
  ].join('\n');
  final identifiers = RegExp(r'\b[A-Za-z_]\w*\b')
      .allMatches(source)
      .map((match) => match.group(0)!)
      .where((word) => word.length > 1);
  return {...pythonCompletionWords, ...identifiers}.toList()..sort();
}

List<String> assignmentApiReference(AssignmentDto assignment) {
  final source = <String>[
    assignment.code,
    ...assignment.projectFiles.map((file) => file.content),
  ].join('\n');
  final items = <String>{};
  for (final line in source.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('def ') ||
        trimmed.startsWith('class ') ||
        trimmed.startsWith('import ') ||
        trimmed.startsWith('from ')) {
      items.add(trimmed.replaceFirst(RegExp(r':\s*$'), ''));
    }
  }
  return items.toList()..sort();
}

int? extractPythonErrorLine(String message, int lineCount) {
  final matches = RegExp(r'\bline\s+(\d+)\b', caseSensitive: false)
      .allMatches(message)
      .toList();
  for (final match in matches.reversed) {
    final line = int.tryParse(match.group(1)!);
    if (line != null && line >= 1 && line <= lineCount) {
      return line;
    }
  }
  return null;
}

bool isEditorSaveShortcut(
  KeyEvent event, {
  required bool editorHasFocus,
  required bool editable,
  Set<LogicalKeyboardKey>? pressedKeys,
}) {
  if (!editorHasFocus || !editable || event is! KeyDownEvent) {
    return false;
  }
  final pressed = pressedKeys ?? HardwareKeyboard.instance.logicalKeysPressed;
  final controlOrMeta = pressed.contains(LogicalKeyboardKey.controlLeft) ||
      pressed.contains(LogicalKeyboardKey.controlRight) ||
      pressed.contains(LogicalKeyboardKey.metaLeft) ||
      pressed.contains(LogicalKeyboardKey.metaRight);
  return controlOrMeta && event.logicalKey == LogicalKeyboardKey.keyS;
}

bool handleEditorKeyEvent(
  KeyEvent event,
  CodeController controller, {
  required bool editorHasFocus,
  required bool editable,
  Set<LogicalKeyboardKey>? pressedKeys,
}) {
  if (!editorHasFocus || !editable || event is! KeyDownEvent) {
    return false;
  }
  final pressed = pressedKeys ?? HardwareKeyboard.instance.logicalKeysPressed;
  final controlOrMeta = pressed.contains(LogicalKeyboardKey.controlLeft) ||
      pressed.contains(LogicalKeyboardKey.controlRight) ||
      pressed.contains(LogicalKeyboardKey.metaLeft) ||
      pressed.contains(LogicalKeyboardKey.metaRight);
  if (controlOrMeta && event.logicalKey == LogicalKeyboardKey.keyY) {
    controller.historyController.redo();
    return true;
  }
  if (event.logicalKey != LogicalKeyboardKey.tab) {
    return false;
  }
  if (controller.popupController.shouldShow) {
    return false;
  }
  final shift = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
      pressed.contains(LogicalKeyboardKey.shiftRight);
  if (shift) {
    controller.outdentSelection();
  } else {
    controller.indentSelection();
  }
  return true;
}
