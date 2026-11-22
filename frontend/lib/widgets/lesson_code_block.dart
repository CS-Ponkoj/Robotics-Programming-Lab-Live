import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight_core.dart' show Highlight, Node;
import 'package:highlight/languages/python.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Python highlighting for lesson code (only Python is registered).
final _highlighter = Highlight()..registerLanguage('python', python);

/// Dark editor look for lesson code: window dots, line numbers, a thin
/// border, and Material-Palenight-style colours in the bundled Lotion font.
abstract final class LessonCodeColors {
  static const background = Color(0xFF263238);
  static const border = Color(0xFF37474F);
  static const text = Color(0xFFEEFFFF);
  static const lineNumber = Color(0xFF546E7A);
  static const keyword = Color(0xFF89DDFF);
  static const definition = Color(0xFFC792EA);
  static const function = Color(0xFF82AAFF);
  static const string = Color(0xFFC3E88D);
  static const number = Color(0xFFF78C6C);
  static const parameter = Color(0xFFF07178);
  static const decorator = Color(0xFFFFCB6B);
  static const comment = Color(0xFF697098);
}

const _codeStyle = TextStyle(
  fontFamily: 'Lotion',
  fontFamilyFallback: ['Courier-New'],
  fontSize: 15.5,
  height: 1.55,
  color: LessonCodeColors.text,
);

TextStyle? _styleFor(String? className, String value) => switch (className) {
      'keyword' => TextStyle(
          fontStyle: FontStyle.italic,
          color: const {'def', 'class', 'lambda'}.contains(value.trim())
              ? LessonCodeColors.definition
              : LessonCodeColors.keyword),
      'built_in' => const TextStyle(color: LessonCodeColors.function),
      'title' => const TextStyle(color: LessonCodeColors.function),
      'literal' || 'number' => const TextStyle(color: LessonCodeColors.number),
      'string' => const TextStyle(color: LessonCodeColors.string),
      'params' => const TextStyle(color: LessonCodeColors.parameter),
      'meta' => const TextStyle(color: LessonCodeColors.decorator),
      'comment' => const TextStyle(
          color: LessonCodeColors.comment, fontStyle: FontStyle.italic),
      _ => null,
    };

/// Coloured spans for Python [code]; plain text if highlighting fails.
List<TextSpan> highlightPython(String code) {
  try {
    final nodes = _highlighter.parse(code, language: 'python').nodes ?? [];
    String text(Node node) =>
        node.value ?? (node.children ?? const []).map(text).join();
    List<TextSpan> walk(List<Node> nodes, TextStyle? inherited) => [
          for (final node in nodes)
            if (node.value != null)
              TextSpan(
                  text: node.value,
                  style: _styleFor(node.className, node.value!) ?? inherited)
            else
              TextSpan(
                  children: walk(node.children ?? const [],
                      _styleFor(node.className, text(node)) ?? inherited)),
        ];
    return walk(nodes, null);
  } catch (_) {
    return [TextSpan(text: code)];
  }
}

/// A code example in the lesson: dark editor card with line numbers,
/// highlighting, sideways scrolling on narrow screens, and a copy button.
class LessonCodeBlock extends StatefulWidget {
  const LessonCodeBlock({super.key, required this.code});
  final String code;

  @override
  State<LessonCodeBlock> createState() => _LessonCodeBlockState();
}

class _LessonCodeBlockState extends State<LessonCodeBlock> {
  bool _copied = false;
  late List<TextSpan> _spans = highlightPython(widget.code);

  @override
  void didUpdateWidget(covariant LessonCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) _spans = highlightPython(widget.code);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  Widget _dot(Color color) => Container(
        width: 11,
        height: 11,
        margin: const EdgeInsets.only(right: 7),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  @override
  Widget build(BuildContext context) {
    final lines = '\n'.allMatches(widget.code).length + 1;
    final width = '$lines'.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 6, 0, 16),
      decoration: BoxDecoration(
        color: LessonCodeColors.background,
        border: Border.all(color: LessonCodeColors.border),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 4, 0),
          child: Row(children: [
            ExcludeSemantics(
              child: Row(children: [
                _dot(const Color(0xFFFF5F56)),
                _dot(const Color(0xFFFFBD2E)),
                _dot(const Color(0xFF27C93F)),
              ]),
            ),
            const Spacer(),
            IconButton(
              key: const Key('lesson-code-copy'),
              tooltip: _copied ? 'Copied' : 'Copy code',
              color: Colors.white70,
              icon: Icon(_copied ? LucideIcons.check : LucideIcons.copy,
                  size: 18),
              onPressed: _copy,
            ),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 0, 20, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExcludeSemantics(
              child: Text(
                [for (var i = 1; i <= lines; i++) '$i'.padLeft(width)]
                    .join('\n'),
                textAlign: TextAlign.right,
                style: _codeStyle.copyWith(color: LessonCodeColors.lineNumber),
              ),
            ),
            const SizedBox(width: 18),
            SelectableText.rich(
              TextSpan(style: _codeStyle, children: _spans),
              key: const Key('lesson-code-text'),
            ),
          ]),
        ),
      ]),
    );
  }
}
