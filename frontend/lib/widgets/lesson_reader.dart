import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parseFragment;
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/lesson_animation.dart';
import 'package:iuse_demo/widgets/lesson_code_block.dart';
import 'package:iuse_demo/widgets/lesson_interactives.dart';
import 'package:iuse_demo/widgets/page_outline.dart';
import 'package:iuse_demo/widgets/quick_check.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Adds navigation to authored headings, without rewriting lesson content.
class LessonReader extends StatefulWidget {
  const LessonReader({
    super.key,
    required this.html,
    this.outline = true,
    this.pageOutline,
  });
  final String html;

  /// Show the "On this page" list when the page has several headings.
  final bool outline;

  /// When given, the headings go to this side outline instead of the
  /// "On this page" list, and each heading can be scrolled to and tracked.
  final PageOutline? pageOutline;

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
  if (element.classes.contains('lesson-goals')) {
    return {
      'margin': '0.2em 0 1.2em 0',
      'padding': '12px 16px',
      'background-color': _hex(AppColors.learningSurface),
      'border-radius': '12px',
    };
  }
  if (element.classes.contains('section-meta')) {
    return {
      'margin': '-0.2em 0 1em 0',
      'font-size': '0.82em',
      'color': _hex(AppColors.inkMuted),
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
        // Inline code reads as a soft tinted chip, in the same bundled font
        // as the code blocks.
        'font-family': 'Lotion, Courier-New, monospace',
        'font-size': '0.92em',
        'color': _hex(AppColors.brandDeep),
        'background-color': _hex(AppColors.brandTint),
      },
    _ => null,
  };
}

/// Lesson elements drawn as widgets: code blocks with a copy button,
/// interactive tools, and animations that start as a still image.
Widget? lessonWidgets(dom.Element element) {
  if (element.localName == 'pre') return LessonCodeBlock(code: element.text);
  final tool = element.attributes['data-interactive'];
  if (tool == 'quick-check') {
    return QuickCheck.fromAttribute(element.attributes['data-check']);
  }
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
  final Map<String, GlobalKey> _headingKeys = {};

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant LessonReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html ||
        oldWidget.pageOutline != widget.pageOutline) {
      _prepare();
    }
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
    _addSectionGuides(document);
    // List main sections only, unless a page has too few of them to navigate.
    final main = all.where((heading) => heading.level == 2).toList();
    _headings = main.length >= 2 ? main : all;
    _html = document.outerHtml;
    final outline = widget.pageOutline;
    if (outline != null) {
      final entries = [
        for (final heading in all)
          PageOutlineEntry(
            id: heading.id,
            title: heading.title,
            level: heading.level,
            key: _headingKeys.putIfAbsent(heading.id, GlobalKey.new),
          ),
      ];
      // Not during build: the outline's listeners rebuild other widgets.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) outline.setEntries(entries);
      });
    }
  }

  /// Under each main heading, "Section 2 of 8 · about 4 min"; before each
  /// next main heading, a button to it. References are not a section.
  static void _addSectionGuides(dom.DocumentFragment document) {
    bool isReferences(dom.Element heading) =>
        heading.text.trim().toLowerCase() == 'references';
    final headings = document
        .querySelectorAll('h2')
        .where((heading) =>
            heading.text.trim().isNotEmpty && !isReferences(heading))
        .toList();
    if (headings.length < 2) return;
    final wordPattern = RegExp(r'[A-Za-z0-9]+');
    for (final (index, heading) in headings.indexed) {
      var words = 0;
      for (var node = heading.nextElementSibling;
          node != null && node.localName != 'h2';
          node = node.nextElementSibling) {
        words += wordPattern.allMatches(node.text).length;
      }
      final minutes = (words / 200).ceil().clamp(1, 120);
      final meta = dom.Element.tag('p')
        ..classes.add('section-meta')
        ..text = 'Section ${index + 1} of ${headings.length} · '
            'about $minutes min';
      final siblings = heading.parentNode!.nodes;
      siblings.insert(siblings.indexOf(heading) + 1, meta);
      if (index == 0) continue;
      final next = dom.Element.tag('div')
        ..attributes['data-interactive'] = 'next-section'
        ..attributes['data-target'] = heading.id
        ..attributes['data-title'] = heading.text.trim();
      heading.parentNode!.insertBefore(next, heading);
    }
  }

  /// The end-of-section button that moves on to the next main heading.
  Widget? _nextSection(dom.Element element) {
    if (element.attributes['data-interactive'] != 'next-section') return null;
    final target = element.attributes['data-target'] ?? '';
    final title = element.attributes['data-title'] ?? '';
    if (target.isEmpty) return null;
    return Padding(
      key: Key('lesson-next-$target'),
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Finished this section?',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 14)),
          OutlinedButton.icon(
            onPressed: () => _jumpTo(target),
            icon: const Icon(LucideIcons.arrowDown, size: 18),
            label: Text('Next: $title'),
          ),
        ],
      ),
    );
  }

  void _jumpTo(String id) {
    final key = _headingKeys[id];
    final target = key?.currentContext;
    if (widget.pageOutline != null && target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _htmlKey.currentState?.scrollToAnchor(id);
  }

  /// With a side outline, headings are drawn here so each has a key to
  /// scroll to; the look matches [lessonStyles].
  Widget? _heading(dom.Element element) {
    final key = _headingKeys[element.id];
    if (widget.pageOutline == null || key == null) return null;
    final level = element.localName == 'h3' ? 3 : 2;
    final text = Text(
      element.text.trim(),
      style: TextStyle(
        fontSize: 17 * (level == 2 ? 1.45 : 1.2),
        fontWeight: FontWeight.w700,
        height: level == 2 ? 1.3 : 1.35,
        color: AppColors.ink,
      ),
    );
    return Padding(
      key: key,
      padding: EdgeInsets.only(
        top: level == 2 ? 27 : 23,
        bottom: level == 2 ? 9 : 8,
      ),
      child: Semantics(
        header: true,
        child: level == 2
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.only(bottom: 5),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: text,
              )
            : text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = _headings.any((heading) => heading.level == 2) &&
        _headings.any((heading) => heading.level == 3);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.outline &&
          widget.pageOutline == null &&
          _headings.length > 1) ...[
        Material(
            color: AppColors.learningSurface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              key: const Key('lesson-outline'),
              leading: const Icon(LucideIcons.list),
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
                    leading: const Icon(LucideIcons.arrowDown, size: 18),
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
        customWidgetBuilder: (element) =>
            _nextSection(element) ??
            (widget.pageOutline == null ? null : _heading(element)) ??
            lessonWidgets(element),
      ),
    ]);
  }
}
