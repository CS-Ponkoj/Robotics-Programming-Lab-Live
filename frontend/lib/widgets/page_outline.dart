import 'package:flutter/material.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// One line of a page outline: a lesson heading or a quiz question.
@immutable
class PageOutlineEntry {
  const PageOutlineEntry({
    required this.id,
    required this.title,
    required this.key,
    this.level = 2,
    this.done = false,
  });

  final String id;
  final String title;

  /// 2 for a main heading, 3 for a subheading (drawn indented).
  final int level;

  /// The widget the entry scrolls to.
  final GlobalKey key;

  /// Shown with a tick, for example an answered quiz question.
  final bool done;
}

/// The headings of the page being read, and which one is on screen, like the
/// outline beside a Google Doc.
class PageOutline extends ChangeNotifier {
  List<PageOutlineEntry> _entries = const [];
  String? _active;

  List<PageOutlineEntry> get entries => _entries;
  String? get active => _active;

  void setEntries(List<PageOutlineEntry> entries) {
    bool same(PageOutlineEntry a, PageOutlineEntry b) =>
        a.id == b.id &&
        a.title == b.title &&
        a.level == b.level &&
        a.done == b.done &&
        a.key == b.key;
    if (entries.length == _entries.length &&
        [for (var i = 0; i < entries.length; i++) same(entries[i], _entries[i])]
            .every((match) => match)) {
      return;
    }
    _entries = List.unmodifiable(entries);
    if (!_entries.any((entry) => entry.id == _active)) {
      _active = _entries.isEmpty ? null : _entries.first.id;
    }
    notifyListeners();
  }

  void _setActive(String? id) {
    if (id == _active) return;
    _active = id;
    notifyListeners();
  }

  /// Scrolls the entry to the top of the reading area.
  Future<void> jumpTo(PageOutlineEntry entry) async {
    _setActive(entry.id);
    final target = entry.key.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  /// Marks the last entry whose top has passed [topY] (a global y) as the one
  /// being read; at the end of the page, the last entry.
  void syncWithScroll(double topY, {bool atEnd = false}) {
    if (_entries.isEmpty) return;
    if (atEnd) {
      _setActive(_entries.last.id);
      return;
    }
    String? current;
    for (final entry in _entries) {
      final box = entry.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= topY + 140) {
        current = entry.id;
      } else {
        break;
      }
    }
    _setActive(current ?? _entries.first.id);
  }
}

/// The outline column: a title with a collapse button, then the entries.
class PageOutlinePanel extends StatelessWidget {
  const PageOutlinePanel({
    super.key,
    required this.outline,
    required this.title,
    required this.onCollapse,
  });

  final PageOutline outline;

  /// "Outline" for headings, "Questions" for a quiz.
  final String title;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('page-outline-panel'),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: ListenableBuilder(
        listenable: outline,
        builder: (context, _) {
          final indent = outline.entries.any((e) => e.level == 2) &&
              outline.entries.any((e) => e.level == 3);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
                child: Row(children: [
                  Icon(LucideIcons.listTree,
                      size: 18, color: AppColors.brandDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandDark,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('outline-collapse'),
                    tooltip: 'Hide outline',
                    onPressed: onCollapse,
                    icon: const Icon(LucideIcons.panelLeftClose, size: 20),
                  ),
                ]),
              ),
              Expanded(
                child: ListView(
                  // Room at the end so the last items scroll clear of the
                  // floating Feedback button in the bottom-left corner.
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                  children: [
                    for (final entry in outline.entries)
                      _OutlineItem(
                        key: Key('outline-item-${entry.id}'),
                        entry: entry,
                        active: entry.id == outline.active,
                        indent: indent && entry.level == 3,
                        onTap: () => outline.jumpTo(entry),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OutlineItem extends StatelessWidget {
  const _OutlineItem({
    super.key,
    required this.entry,
    required this.active,
    required this.indent,
    required this.onTap,
  });

  final PageOutlineEntry entry;
  final bool active;
  final bool indent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final main = entry.level <= 2;
    final color = active ? AppColors.brandDark : AppColors.inkMuted;
    return Semantics(
      selected: active,
      button: true,
      child: Material(
        color: active ? AppColors.brandTint : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.fromLTRB(indent ? 26 : 10, 8, 10, 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: active ? AppColors.brand : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: (main
                            ? theme.textTheme.bodyMedium
                            : theme.textTheme.bodySmall)
                        ?.copyWith(
                      color: active ? color : AppColors.ink,
                      fontWeight: active
                          ? FontWeight.w700
                          : (main ? FontWeight.w600 : FontWeight.w400),
                      height: 1.35,
                    ),
                  ),
                ),
                if (entry.done) ...[
                  const SizedBox(width: 6),
                  const Icon(LucideIcons.circleCheck,
                      size: 16, color: AppColors.success),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The collapsed outline: one button that opens it again.
class PageOutlineOpenButton extends StatelessWidget {
  const PageOutlineOpenButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: const BorderSide(color: AppColors.border),
      ),
      child: IconButton(
        key: const Key('outline-open'),
        tooltip: 'Show outline',
        onPressed: onPressed,
        icon: Icon(LucideIcons.listTree, color: AppColors.brandDark),
      ),
    );
  }
}
