import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/parser.dart' show parseFragment;
import 'package:iuse_demo/theme/app_theme.dart';

/// Adds navigation to authored headings, without rewriting lesson content.
class LessonReader extends StatefulWidget {
  const LessonReader({super.key, required this.html});
  final String html;

  @override
  State<LessonReader> createState() => _LessonReaderState();
}

class _LessonReaderState extends State<LessonReader> {
  final _htmlKey = GlobalKey<HtmlWidgetState>();
  late String _html;
  late List<({String id, String title})> _headings;

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
    _headings = [];
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
      _headings.add((id: heading.id, title: title));
    }
    _html = document.outerHtml;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_headings.length > 1) ...[
        Material(
            color: AppColors.learningSurface,
            borderRadius: BorderRadius.circular(12),
            child: ExpansionTile(
              key: const Key('lesson-outline'),
              leading: const Icon(Icons.format_list_bulleted_rounded),
              title: const Text('On this page'),
              subtitle: Text('${_headings.length} sections · jump to a topic'),
              children: [
                for (final heading in _headings)
                  ListTile(
                    title: Text(heading.title),
                    leading: const Icon(Icons.arrow_downward_rounded, size: 18),
                    onTap: () =>
                        _htmlKey.currentState?.scrollToAnchor(heading.id),
                  ),
              ],
            )),
        const SizedBox(height: 16),
      ],
      Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: HtmlWidget(
              _html,
              key: _htmlKey,
              textStyle: theme.textTheme.bodyLarge,
              customStylesBuilder: (element) => switch (element.localName) {
                'p' || 'li' => {'line-height': '1.65'},
                'h1' || 'h2' || 'h3' => {'line-height': '1.3'},
                _ => null,
              },
            ),
          )),
    ]);
  }
}
