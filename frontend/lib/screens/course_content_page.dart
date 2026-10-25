import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iuse_demo/state/feedback_page_tracker.dart';
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/services/course_content_api.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/widgets/landing_page_header.dart';
import 'package:iuse_demo/widgets/lesson_reader.dart';

/// Names the unanswered quiz questions by their 1-based display numbers,
/// for example "Answer questions 2, 5 and 9 before submitting."
String unansweredQuizMessage(List<int> numbers) {
  if (numbers.length == 1) {
    return 'Answer question ${numbers.single} before submitting.';
  }
  final leading = numbers.sublist(0, numbers.length - 1).join(', ');
  return 'Answer questions $leading and ${numbers.last} before submitting.';
}

/// Course reading and quizzes are separate from graded coding assignments.
class CourseCatalogPage extends StatefulWidget {
  const CourseCatalogPage({
    super.key,
    required this.user,
    required this.onLogout,
    this.embedded = false,
  });
  final bool embedded;
  final AuthenticatedUser user;
  final Future<void> Function() onLogout;

  @override
  State<CourseCatalogPage> createState() => _CourseCatalogPageState();
}

class _CourseCatalogPageState extends State<CourseCatalogPage> {
  late Future<List<Map<String, dynamic>>> _topics = CourseContentApi.topics();

  void _retry() => setState(() => _topics = CourseContentApi.topics());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = FutureBuilder<List<Map<String, dynamic>>>(
      future: _topics,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _LoadError(
            onRetry: _retry,
            sessionExpired: snapshot.error is ContentSessionExpired,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final topics = snapshot.data!;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'COURSE CONTENTS',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.brand,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Learn the ideas, then practice them',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Six robotics topics with lessons, exercises, and submitted quizzes. '
                  'Quiz scores are saved separately from coding assignment scores.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 850
                        ? 3
                        : constraints.maxWidth >= 520
                            ? 2
                            : 1;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 16) / columns;
                    return Column(
                      children: [
                        for (var row = 0; row < topics.length; row += columns)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = row;
                                      i < row + columns && i < topics.length;
                                      i++) ...[
                                    if (i > row) const SizedBox(width: 16),
                                    SizedBox(
                                      width: width,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            AppRadii.lg,
                                          ),
                                          boxShadow: appCardShadow,
                                        ),
                                        child: Material(
                                          color: theme.colorScheme.surface,
                                          clipBehavior: Clip.antiAlias,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppRadii.lg,
                                            ),
                                            side: const BorderSide(
                                              color: AppColors.border,
                                            ),
                                          ),
                                          child: InkWell(
                                            key: Key(
                                              'content-topic-${topics[i]['id']}',
                                            ),
                                            onTap: () async {
                                              await Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                  settings: RouteSettings(arguments: FeedbackPage('Course topic: ${topics[i]['title'] ?? topics[i]['id']}'),
                                                  ),
                                                  builder: (_) =>
                                                      CourseTopicPage(
                                                    topicId: topics[i]['id']
                                                        as String,
                                                    user: widget.user,
                                                    onLogout: widget.onLogout,
                                                  ),
                                                ),
                                              );
                                              if (mounted) _retry();
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(22),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Container(
                                                        width: 44,
                                                        height: 44,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: AppColors
                                                              .brandTint,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            13,
                                                          ),
                                                        ),
                                                        child: Icon(
                                                          topicIcon(
                                                            topics[i]['id']
                                                                as String,
                                                          ),
                                                          color: AppColors
                                                              .brandDark,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Text(
                                                        'TOPIC ${'${i + 1}'.padLeft(2, '0')}',
                                                        style: theme.textTheme
                                                            .labelMedium
                                                            ?.copyWith(
                                                          color: theme
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                          letterSpacing: 1,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    topics[i]['title']
                                                        as String,
                                                    style: theme
                                                        .textTheme.titleLarge,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    topics[i]['summary']
                                                        as String,
                                                    style: theme
                                                        .textTheme.bodyMedium
                                                        ?.copyWith(
                                                      color: theme.colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  const SizedBox(height: 18),
                                                  const Divider(),
                                                  const SizedBox(height: 16),
                                                  _QuizProgress(
                                                    topic: topics[i],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    'Open content →',
                                                    style: TextStyle(
                                                      color: theme
                                                          .colorScheme.primary,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: LandingPageHeader(
        user: widget.user,
        onLogout: widget.onLogout,
        onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
      ),
      body: body,
    );
  }
}

/// A recognizable icon for each course topic.
IconData topicIcon(String topicId) => switch (topicId) {
      'obstacle-avoidance' => Icons.alt_route_rounded,
      'path-planning' => Icons.route_rounded,
      'sensor-fusion' => Icons.hub_rounded,
      'range-sensors' => Icons.sensors_rounded,
      'locomotion' => Icons.precision_manufacturing_rounded,
      'hybrid-navigation-gps' ||
      'hybrid-navigation-and-gps' =>
        Icons.satellite_alt_rounded,
      _ => Icons.menu_book_rounded,
    };

class _QuizProgress extends StatelessWidget {
  const _QuizProgress({required this.topic});
  final Map<String, dynamic> topic;

  @override
  Widget build(BuildContext context) {
    final progress = topic['quiz_progress'] as Map? ?? {};
    final count = progress['attempt_count'] as int? ?? 0;
    final latest = progress['latest_score'] as num?;
    final best = progress['best_score'] as num?;
    final color = latest == null
        ? Theme.of(context).colorScheme.outline
        : performanceColor(latest);
    final neutral = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget badge(String label, Color badgeColor, {IconData? icon}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: badgeColor),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count == 0 ? 'Quiz: Not attempted' : 'Quiz submitted',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          key: Key('quiz-progress-${topic['id']}'),
          value: (latest ?? 0).clamp(0, 100) / 100,
          color: color,
          minHeight: 8,
          backgroundColor: AppColors.neutralContainer,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          semanticsLabel: 'Latest quiz score for ${topic['title']}',
          semanticsValue: latest == null ? 'Not attempted' : '$latest%',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            badge('Attempted: $count', neutral, icon: Icons.science_outlined),
            badge(
              'Best score: ${best == null ? '—' : '$best%'}',
              best == null ? neutral : performanceColor(best),
            ),
            badge(
              'Last score: ${latest == null ? '—' : '$latest%'}',
              latest == null ? neutral : color,
            ),
          ],
        ),
        if (progress['temporary'] == true) ...[
          const SizedBox(height: 8),
          Text(
            'Temporary demo progress',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}

class CourseTopicPage extends StatefulWidget {
  const CourseTopicPage({
    super.key,
    required this.topicId,
    required this.user,
    required this.onLogout,
  });
  final String topicId;
  final AuthenticatedUser user;
  final Future<void> Function() onLogout;

  @override
  State<CourseTopicPage> createState() => _CourseTopicPageState();
}

class _CourseTopicPageState extends State<CourseTopicPage> {
  late Future<Map<String, dynamic>> _topic = CourseContentApi.topic(
    widget.topicId,
  );
  String _kind = 'lesson';
  String? _sectionId;

  void _retry() =>
      setState(() => _topic = CourseContentApi.topic(widget.topicId));

  void _open(Map<String, dynamic> section) => setState(() {
        _kind = section['kind'] as String;
        _sectionId = section['id'] as String;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LandingPageHeader(
        user: widget.user,
        onLogout: widget.onLogout,
        onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _topic,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _LoadError(
              onRetry: _retry,
              sessionExpired: snapshot.error is ContentSessionExpired,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final topic = snapshot.data!;
          final sections = (topic['sections'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          final kinds = _kindOrder
              .where((kind) => sections.any((s) => s['kind'] == kind))
              .toList();
          final selectedKind = kinds.contains(_kind) ? _kind : kinds.first;
          final visible =
              sections.where((s) => s['kind'] == selectedKind).toList();
          final sectionId = visible.any((s) => s['id'] == _sectionId)
              ? _sectionId!
              : visible.first['id'] as String;
          // Reading order for Previous / Next: lesson, exercises, quiz, math.
          final ordered = [
            for (final kind in kinds)
              ...sections.where((s) => s['kind'] == kind),
          ];
          final position = ordered.indexWhere((s) => s['id'] == sectionId);
          final labels = {
            for (final kind in kinds)
              ..._sectionLabels(
                sections.where((s) => s['kind'] == kind).toList(),
              ),
          };
          return _CourseSectionView(
            key: ValueKey('${widget.topicId}/$sectionId'),
            topicId: widget.topicId,
            sectionId: sectionId,
            title: labels[sectionId] ?? '',
            header: _header(
              context,
              topic,
              kinds,
              selectedKind,
              visible,
              sectionId,
              labels,
            ),
            previous: position > 0 ? ordered[position - 1] : null,
            next: position >= 0 && position < ordered.length - 1
                ? ordered[position + 1]
                : null,
            labels: labels,
            onOpen: _open,
          );
        },
      ),
    );
  }

  Widget _header(
    BuildContext context,
    Map<String, dynamic> topic,
    List<String> kinds,
    String selectedKind,
    List<Map<String, dynamic>> visible,
    String sectionId,
    Map<String, String> labels,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(topicIcon(widget.topicId), size: 18, color: AppColors.brand),
            const SizedBox(width: 8),
            Text(
              'COURSE TOPIC',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.brand,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(topic['title'] as String, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          topic['summary'] as String,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in kinds)
              ChoiceChip(
                key: Key('content-tab-$kind'),
                label: Text(_kindLabel(kind)),
                selected: selectedKind == kind,
                onSelected: (_) => setState(() {
                  _kind = kind;
                  _sectionId = null;
                }),
              ),
          ],
        ),
        // Wrapping keeps the selected exercise visible at every width.
        if (visible.length > 1) ...[
          const SizedBox(height: 10),
          Wrap(
            key: const Key('content-section-picker'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final section in visible)
                ChoiceChip(
                  label: Text(labels[section['id']] ?? ''),
                  showCheckmark: false,
                  selected: sectionId == section['id'],
                  onSelected: (_) =>
                      setState(() => _sectionId = section['id'] as String),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

const _kindOrder = ['lesson', 'exercise', 'quiz', 'math'];

String _kindLabel(String kind) => switch (kind) {
      'lesson' => 'Lesson',
      'exercise' => 'Exercises',
      'quiz' => 'Quiz',
      _ => 'Math practice',
    };

/// Short display names for one kind's sections, without changing their IDs:
/// a prefix every title shares ("Exercises · ") is dropped, and bare numbers
/// read as "Exercise 1".
Map<String, String> _sectionLabels(List<Map<String, dynamic>> sections) {
  if (sections.isEmpty) return {};
  final kind = sections.first['kind'] as String;
  final titles = [for (final s in sections) s['title'] as String];
  final prefix = titles.first.contains(' · ')
      ? '${titles.first.split(' · ').first} · '
      : null;
  final shared = sections.length > 1 &&
      prefix != null &&
      titles.every((title) => title.startsWith(prefix));
  return {
    for (final section in sections)
      section['id'] as String: () {
        if (kind == 'lesson' || kind == 'quiz') return _kindLabel(kind);
        var title = section['title'] as String;
        if (shared) title = title.substring(prefix.length);
        if (RegExp(r'^\d+$').hasMatch(title)) return 'Exercise $title';
        return title.isEmpty
            ? title
            : title[0].toUpperCase() + title.substring(1);
      }(),
  };
}

class _CourseSectionView extends StatefulWidget {
  const _CourseSectionView({
    super.key,
    required this.topicId,
    required this.sectionId,
    required this.title,
    required this.header,
    required this.labels,
    required this.onOpen,
    this.previous,
    this.next,
  });
  final String topicId;
  final String sectionId;
  final String title;
  final Widget header;
  final Map<String, String> labels;
  final Map<String, dynamic>? previous;
  final Map<String, dynamic>? next;
  final void Function(Map<String, dynamic> section) onOpen;

  @override
  State<_CourseSectionView> createState() => _CourseSectionViewState();
}

class _CourseSectionViewState extends State<_CourseSectionView> {
  late Future<Map<String, dynamic>> _section = CourseContentApi.section(
    widget.topicId,
    widget.sectionId,
  );
  final _scroll = ScrollController();
  bool _showTop = false;
  final Map<String, String> _choices = {};
  // Lets an incomplete submission scroll to the first unanswered question.
  final Map<String, GlobalKey> _questionKeys = {};
  Map<String, dynamic>? _result;
  // Per-question marks from the last submit: true = correct. Never the key.
  final Map<String, bool> _marks = {};
  bool _submitting = false;
  String? _quizError;
  Future<List<Map<String, dynamic>>>? _attempts;

  @override
  void initState() {
    super.initState();
    if (widget.sectionId == 'quiz') {
      _attempts = CourseContentApi.quizAttempts(widget.topicId);
    }
    _scroll.addListener(() {
      final show = _scroll.hasClients && _scroll.offset > 900;
      if (show != _showTop) setState(() => _showTop = show);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _retry() => setState(
        () => _section =
            CourseContentApi.section(widget.topicId, widget.sectionId),
      );

  Future<void> _submit(Map<String, dynamic> section) async {
    final questions = (section['questions'] as List).cast<Map>();
    final missing = [
      for (final (index, question) in questions.indexed)
        if (!_choices.containsKey(question['id'])) index + 1,
    ];
    if (missing.isNotEmpty) {
      setState(() => _quizError = unansweredQuizMessage(missing));
      final firstContext =
          _questionKeys['${questions[missing.first - 1]['id']}']
              ?.currentContext;
      if (firstContext != null) {
        unawaited(Scrollable.ensureVisible(
          firstContext,
          duration: const Duration(milliseconds: 300),
          alignment: 0.1,
        ));
      }
      return;
    }
    setState(() {
      _submitting = true;
      _quizError = null;
    });
    try {
      final result = await CourseContentApi.submitQuiz(
        widget.topicId,
        section['version'] as String,
        _choices,
      );
      if (mounted) {
        setState(() {
          _result = result;
          _marks
            ..clear()
            ..addAll(quizResultMarks(result));
          _attempts = CourseContentApi.quizAttempts(widget.topicId);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _quizError =
              'Could not submit the quiz. Your selections are still here; try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Stack(
      children: [
        FutureBuilder<Map<String, dynamic>>(
          future: _section,
          builder: (context, snapshot) {
            final Widget body;
            if (snapshot.hasError) {
              body = _LoadError(
                onRetry: _retry,
                sessionExpired: snapshot.error is ContentSessionExpired,
              );
            } else if (!snapshot.hasData) {
              body = const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            } else {
              body = _content(context, snapshot.data!, narrow);
            }
            return ListView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                narrow ? 16 : 24,
                narrow ? 20 : 28,
                narrow ? 16 : 24,
                // Room below the pager for the back-to-top button.
                88,
              ),
              children: [
                _readingWidth(widget.header),
                const SizedBox(height: 16),
                _readingWidth(body),
                if (snapshot.hasData) ...[
                  const SizedBox(height: 20),
                  _readingWidth(_pager(context)),
                ],
              ],
            );
          },
        ),
        if (_showTop)
          Positioned(
            right: 20,
            bottom: 20,
            child: FloatingActionButton.small(
              key: const Key('back-to-top'),
              tooltip: 'Back to top',
              onPressed: () => _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
              ),
              child: const Icon(Icons.arrow_upward_rounded),
            ),
          ),
      ],
    );
  }

  /// One centered column keeps the header, text, and navigation aligned and
  /// limits lines to a comfortable reading length.
  Widget _readingWidth(Widget child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: child,
        ),
      );

  Widget _content(
    BuildContext context,
    Map<String, dynamic> section,
    bool narrow,
  ) {
    final theme = Theme.of(context);
    final questions = (section['questions'] as List).cast<Map>();
    final html = (section['html'] as String).replaceAll(
      '/content-assets/',
      '$apiBaseUrl/content-assets/',
    );
    final kind = section['kind'] as String;
    final practice = kind == 'exercise' || kind == 'math';
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.all(narrow ? 20 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The chip above already names the lesson and the quiz.
            if (practice) ...[
              Text(widget.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.inkMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Self-directed practice. This does not affect your '
                      'graded assignment score.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 24),
            ],
            if (html.isNotEmpty)
              LessonReader(html: html, key: const Key('course-section-html')),
            if (kind == 'quiz') ..._quiz(context, section, questions),
          ],
        ),
      ),
    );
  }

  List<Widget> _quiz(
    BuildContext context,
    Map<String, dynamic> section,
    List<Map> questions,
  ) {
    final theme = Theme.of(context);
    final answered =
        questions.where((q) => _choices.containsKey(q['id'])).length;
    return [
      Text(
        '${questions.length} questions. Choose one answer for each, then submit.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      for (final (index, rawQuestion) in questions.indexed) ...[
        const SizedBox(height: 16),
        KeyedSubtree(
          key: _questionKeys.putIfAbsent('${rawQuestion['id']}', GlobalKey.new),
          child: _quizQuestion(
            Map<String, dynamic>.from(rawQuestion),
            index + 1,
            questions.length,
          ),
        ),
      ],
      const SizedBox(height: 20),
      if (_quizError != null) ...[
        Text(_quizError!, style: TextStyle(color: theme.colorScheme.error)),
        const SizedBox(height: 8),
      ],
      if (_result == null)
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              key: const Key('submit-course-quiz'),
              onPressed: _submitting ? null : () => _submit(section),
              child: Text(_submitting ? 'Submitting…' : 'Submit quiz'),
            ),
            Text(
              '$answered of ${questions.length} answered',
              key: const Key('quiz-answered-count'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        )
      else ...[
        if (_marks.containsValue(false)) ...[
          Text(
            'Review the questions marked Incorrect, then try again.',
            key: const Key('course-quiz-review-hint'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
        ],
        Text(
          'Score: ${_result!['score_percent']}% '
          '(${_result!['correct_count']}/${_result!['total_questions']} correct)',
          key: const Key('course-quiz-score'),
          style: theme.textTheme.titleLarge,
        ),
        Text(
          _result!['saved'] == true
              ? 'Score saved. This does not change your coding assignment score.'
              : 'Preview score only. Demo and instructor quiz results are not saved.',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => setState(() {
              _choices.clear();
              _marks.clear();
              _result = null;
              _quizError = null;
            }),
            child: const Text('Try again'),
          ),
        ),
      ],
      const SizedBox(height: 16),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _attempts,
        builder: (context, history) {
          if (history.hasError) {
            return Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => setState(
                  () =>
                      _attempts = CourseContentApi.quizAttempts(widget.topicId),
                ),
                child: const Text('Retry saved scores'),
              ),
            );
          }
          if (!history.hasData) {
            return const LinearProgressIndicator();
          }
          if (history.data!.isEmpty) {
            return const Text('No saved quiz scores yet.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Saved scores', style: theme.textTheme.titleMedium),
              for (final attempt in history.data!)
                Text(
                  '${attempt['score_percent']}% · ${attempt['correct_count']}/${attempt['total_questions']} correct'
                  '${attempt['quiz_version'] == section['version'] ? '' : ' · earlier quiz version'}',
                ),
            ],
          );
        },
      ),
    ];
  }

  Widget _pager(BuildContext context) {
    Widget button(Map<String, dynamic>? section, {required bool forward}) {
      if (section == null) return const SizedBox.shrink();
      final label = widget.labels[section['id']] ?? '';
      final text = Text(
        forward ? 'Next: $label' : 'Previous: $label',
        overflow: TextOverflow.ellipsis,
      );
      return forward
          ? FilledButton.tonalIcon(
              key: const Key('next-section'),
              onPressed: () => widget.onOpen(section),
              icon: const Icon(Icons.arrow_forward_rounded),
              iconAlignment: IconAlignment.end,
              label: text,
            )
          : OutlinedButton.icon(
              key: const Key('previous-section'),
              onPressed: () => widget.onOpen(section),
              icon: const Icon(Icons.arrow_back_rounded),
              label: text,
            );
    }

    // Previous stays left and Next stays right. Each may use half the row,
    // or the whole row when it is the only button.
    final both = widget.previous != null && widget.next != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = BoxConstraints(
            maxWidth:
                both ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ConstrainedBox(
                constraints: half,
                child: button(widget.previous, forward: false)),
            ConstrainedBox(
                constraints: half, child: button(widget.next, forward: true)),
          ],
        );
      },
    );
  }

  Widget _quizQuestion(Map<String, dynamic> question, int number, int total) {
    final id = question['id'] as String;
    final options = (question['options'] as List).cast<Map>();
    final theme = Theme.of(context);
    final answered = _choices.containsKey(id);
    final mark = _marks[id];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: answered
              ? AppColors.brand.withValues(alpha: 0.45)
              : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'QUESTION $number OF $total',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.brand,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (mark != null) _QuizMark(number: number, correct: mark),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            question['prompt'] as String,
            style: theme.textTheme.titleMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 4),
          for (final option in options)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              title: Text('${option['id']}. ${option['text']}'),
              value: option['id'] as String,
              groupValue: _choices[id],
              onChanged: _submitting
                  ? null
                  : (value) => setState(() {
                        _choices[id] = value!;
                        _quizError = null;
                        // A changed answer needs a fresh submit to be graded.
                        _marks.remove(id);
                        _result = null;
                      }),
            ),
        ],
      ),
    );
  }
}

/// Correct/Incorrect status for one submitted question. It never shows
/// which option is right.
class _QuizMark extends StatelessWidget {
  const _QuizMark({required this.number, required this.correct});
  final int number;
  final bool correct;

  @override
  Widget build(BuildContext context) {
    final color = correct ? AppColors.success : AppColors.performanceLow;
    return Semantics(
      key: Key('quiz-mark-$number'),
      container: true,
      label: 'Question $number: ${correct ? 'correct' : 'incorrect'}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            correct ? 'Correct' : 'Incorrect',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry, this.sessionExpired = false});
  final VoidCallback onRetry;
  final bool sessionExpired;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.menu_book_rounded,
                size: 40,
                color: AppColors.brandDark,
              ),
              const SizedBox(height: 16),
              Text(
                sessionExpired
                    ? 'Please sign in again'
                    : 'Course content is unavailable right now.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                sessionExpired
                    ? 'Your session has expired. Open the account menu, log out, then sign in again. Your saved scores are unchanged.'
                    : 'Check the backend connection and retry. Your saved quiz scores are unchanged.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
