import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parseFragment;
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/lesson_animation.dart';
import 'package:iuse_demo/widgets/lesson_interactives.dart';

/// Adds navigation to authored headings, without rewriting lesson content.
class LessonReader extends StatefulWidget {
  const LessonReader({super.key, required this.html});
  final String html;

  @override
  State<LessonReader> createState() => _LessonReaderState();
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Reading styles for generated lesson HTML. Sizes are relative to the
/// 17px body text so they scale with the reader's text-size setting.
Map<String, String>? lessonStyles(dom.Element element) {
  if (element.classes.contains('lesson-note')) {
    return {
      'margin': '1.2em 0',
      'padding': '12px 16px',
      'background-color': _hex(AppColors.learningSurface),
      'border-left': '4px solid ${_hex(AppColors.brand)}',
      'border-radius': '8px',
    };
  }
  if (element.classes.contains('math-expression')) {
    return {
      'font-family': 'Cambria Math, STIX Two Math, Times New Roman, serif',
      'font-style': 'italic',
    };
  }
  return switch (element.localName) {
    'p' => {'margin': '0 0 0.9em 0', 'line-height': '1.7'},
    'h2' => {
        'font-size': '1.45em',
        'font-weight': '700',
        'line-height': '1.3',
        'margin': '1.6em 0 0.55em 0',
        'padding-bottom': '0.3em',
        'border-bottom': '1px solid ${_hex(AppColors.border)}',
        'color': _hex(AppColors.ink),
      },
    'h3' => {
        'font-size': '1.2em',
        'font-weight': '700',
        'line-height': '1.35',
        'margin': '1.35em 0 0.45em 0',
        'color': _hex(AppColors.ink),
      },
    'h4' => {
        'font-size': '1.02em',
        'font-weight': '700',
        'line-height': '1.4',
        'margin': '1.15em 0 0.35em 0',
        'color': _hex(AppColors.brandDark),
      },
    'ul' || 'ol' => {'margin': '0.2em 0 1em 0', 'padding-left': '1.6em'},
    'li' => {'margin-bottom': '0.4em', 'line-height': '1.65'},
    'figure' => {
        'margin': '1.4em 0',
        'padding': '14px',
        'background-color': _hex(AppColors.learningSurface),
        'border-radius': '12px',
        'text-align': 'center',
      },
    'figcaption' => {
        'margin-top': '10px',
        'font-size': '0.88em',
        'line-height': '1.5',
        'color': _hex(AppColors.inkMuted),
        'text-align': 'center',
      },
    'table' => {
        'border-collapse': 'collapse',
        'border-spacing': '0',
        'margin': '0.6em 0 1.2em 0',
      },
    'th' => {
        'padding': '8px 12px',
        'border': '1px solid ${_hex(AppColors.borderStrong)}',
        'background-color': _hex(AppColors.resultsHeader),
        'font-weight': '700',
        'text-align': 'left',
        'vertical-align': 'top',
      },
    'td' => {
        'padding': '8px 12px',
        'border': '1px solid ${_hex(AppColors.borderStrong)}',
        'vertical-align': 'top',
        'line-height': '1.5',
      },
    'a' => {'color': _hex(AppColors.brand)},
    'code' => {
        // The app bundles this font for its code editor.
        'font-family': 'Courier-New, monospace',
        'color': _hex(AppColors.ink),
      },
    _ => null,
  };
}

/// Lesson elements drawn as widgets: code blocks with a copy button,
/// interactive tools, and animations that start as a still image.
Widget? lessonWidgets(dom.Element element) {
  if (element.localName == 'pre') return LessonCodeBlock(code: element.text);
  final tool = element.attributes['data-interactive'];
  if (tool != null) return lessonInteractive(tool);
  final animation = element.attributes['data-animation'];
  final still = element.attributes['src'];
  if (element.localName != 'img' || animation == null || still == null) {
    return null;
  }
  return LessonAnimation(
    stillUrl: still,
    animationUrl: animation,
    description: element.attributes['alt'] ?? 'Lesson animation.',
  );
}

class _LessonReaderState extends State<LessonReader> {
  final _htmlKey = GlobalKey<HtmlWidgetState>();
  late String _html;
  late List<({String id, String title, int level})> _headings;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant LessonReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) _prepare();
  }

  void _prepare() {
    final document = parseFragment(widget.html);
    final usedIds =
        document.querySelectorAll('[id]').map((element) => element.id).toSet();
    final all = <({String id, String title, int level})>[];
    var serial = 0;
    for (final heading in document.querySelectorAll('h1, h2, h3')) {
      final title = heading.text.trim();
      if (title.isEmpty) continue;
      if (heading.id.isEmpty) {
        var id = 'lesson-heading-${serial++}';
        while (usedIds.contains(id)) {
          id = 'lesson-heading-${serial++}';
        }
        heading.id = id;
        usedIds.add(id);
      }
      all.add((
        id: heading.id,
        title: title,
        level: heading.localName == 'h3' ? 3 : 2,
      ));
    }
    // List main sections only, unless a page has too few of them to navigate.
    final main = all.where((heading) => heading.level == 2).toList();
    _headings = main.length >= 2 ? main : all;
    _html = document.outerHtml;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = _headings.any((heading) => heading.level == 2) &&
        _headings.any((heading) => heading.level == 3);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_headings.length > 1) ...[
        Material(
            color: AppColors.learningSurface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              key: const Key('lesson-outline'),
              leading: const Icon(Icons.format_list_bulleted_rounded),
              title: const Text('On this page'),
              subtitle: Text('${_headings.length} sections · jump to a topic'),
              shape: const Border(),
              collapsedShape: const Border(),
              children: [
                for (final heading in _headings)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.only(
                        left: indent && heading.level == 3 ? 40 : 16,
                        right: 16),
                    title: Text(heading.title),
                    leading: const Icon(Icons.arrow_downward_rounded, size: 18),
                    onTap: () =>
                        _htmlKey.currentState?.scrollToAnchor(heading.id),
                  ),
                const SizedBox(height: 8),
              ],
            )),
        const SizedBox(height: 20),
      ],
      HtmlWidget(
        _html,
        key: _htmlKey,
        textStyle: theme.textTheme.bodyLarge
            ?.copyWith(fontSize: 17, height: 1.7, color: AppColors.ink),
        customStylesBuilder: lessonStyles,
        customWidgetBuilder: lessonWidgets,
      ),
    ]);
  }
}

/// A code example that keeps its line breaks, scrolls sideways on narrow
/// screens, and can be copied.
class LessonCodeBlock extends StatefulWidget {
  const LessonCodeBlock({super.key, required this.code});
  final String code;

  @override
  State<LessonCodeBlock> createState() => _LessonCodeBlockState();
}

class _LessonCodeBlockState extends State<LessonCodeBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 6, 0, 16),
      decoration: BoxDecoration(
        color: AppColors.learningSurface,
        border: const Border(
            left: BorderSide(color: AppColors.borderStrong, width: 3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 12, 48, 12),
          child: SelectableText(
            widget.code,
            style: const TextStyle(
              fontFamily: 'Courier-New',
              fontSize: 14,
              height: 1.45,
              color: AppColors.ink,
            ),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: IconButton(
            key: const Key('lesson-code-copy'),
            tooltip: _copied ? 'Copied' : 'Copy code',
            icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 18),
            onPressed: _copy,
          ),
        ),
      ]),
    );
  }
}
