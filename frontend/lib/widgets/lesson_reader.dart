import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parseFragment;
import 'package:iuse_demo/theme/app_theme.dart';

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
    _ => null,
  };
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
      ),
    ]);
  }
}
