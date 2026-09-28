import 'package:flutter/material.dart';
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/services/course_content_api.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/widgets/landing_page_header.dart';
import 'package:iuse_demo/widgets/lesson_reader.dart';

/// Course reading and quizzes are separate from graded coding assignments.
class CourseCatalogPage extends StatefulWidget {
  const CourseCatalogPage(
      {super.key,
      required this.user,
      required this.onLogout,
      this.embedded = false});
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
              sessionExpired: snapshot.error is ContentSessionExpired);
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
                Text('Learn the ideas, then practice them',
                    style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Six robotics topics with lessons, exercises, and submitted quizzes. '
                  'Quiz scores are saved separately from coding assignment scores.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                LayoutBuilder(builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 850
                      ? 3
                      : constraints.maxWidth >= 520
                          ? 2
                          : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 16) / columns;
                  return Column(children: [
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
                                child: Card(
                                  color: learningCardSurface(i),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    key:
                                        Key('content-topic-${topics[i]['id']}'),
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => CourseTopicPage(
                                            topicId: topics[i]['id'] as String,
                                            user: widget.user,
                                            onLogout: widget.onLogout,
                                          ),
                                        ),
                                      );
                                      if (mounted) _retry();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CircleAvatar(
                                            child: Text(
                                                '${i + 1}'.padLeft(2, '0')),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(topics[i]['title'] as String,
                                              style:
                                                  theme.textTheme.titleLarge),
                                          const SizedBox(height: 8),
                                          Text(topics[i]['summary'] as String),
                                          const Spacer(),
                                          const SizedBox(height: 16),
                                          _QuizProgress(topic: topics[i]),
                                          const SizedBox(height: 16),
                                          Text('Open content →',
                                              style: TextStyle(
                                                  color:
                                                      theme.colorScheme.primary,
                                                  fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        )),
                      ),
                  ]);
                }),
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
          onHome: () =>
              Navigator.of(context).popUntil((route) => route.isFirst)),
      body: body,
    );
  }
}

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
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: badgeColor),
              const SizedBox(width: 7),
            ],
            Flexible(
                child: Text(label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: badgeColor, fontWeight: FontWeight.w700))),
          ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(count == 0 ? 'Quiz: Not attempted' : 'Quiz submitted',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          key: Key('quiz-progress-${topic['id']}'),
          value: (latest ?? 0).clamp(0, 100) / 100,
          color: color,
          semanticsLabel: 'Latest quiz score for ${topic['title']}',
          semanticsValue: latest == null ? 'Not attempted' : '$latest%',
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          badge('Attempted: $count', neutral, icon: Icons.science_outlined),
          badge('Best score: ${best == null ? '—' : '$best%'}',
              best == null ? neutral : performanceColor(best)),
          badge('Last score: ${latest == null ? '—' : '$latest%'}',
              latest == null ? neutral : color),
        ]),
        if (progress['temporary'] == true)
          const Text('Temporary demo progress'),
      ],
    );
  }
}

class CourseTopicPage extends StatefulWidget {
  const CourseTopicPage(
      {super.key,
      required this.topicId,
      required this.user,
      required this.onLogout});
  final String topicId;
  final AuthenticatedUser user;
  final Future<void> Function() onLogout;

  @override
  State<CourseTopicPage> createState() => _CourseTopicPageState();
}

class _CourseTopicPageState extends State<CourseTopicPage> {
  late Future<Map<String, dynamic>> _topic =
      CourseContentApi.topic(widget.topicId);
  String _kind = 'lesson';
  String? _sectionId;

  void _retry() =>
      setState(() => _topic = CourseContentApi.topic(widget.topicId));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LandingPageHeader(
          user: widget.user,
          onLogout: widget.onLogout,
          onHome: () =>
              Navigator.of(context).popUntil((route) => route.isFirst)),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _topic,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _LoadError(
                onRetry: _retry,
                sessionExpired: snapshot.error is ContentSessionExpired);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final topic = snapshot.data!;
          final sections = (topic['sections'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          final kinds = ['lesson', 'exercise', 'quiz', 'math']
              .where((kind) => sections.any((s) => s['kind'] == kind))
              .toList();
          final selectedKind = kinds.contains(_kind) ? _kind : kinds.first;
          final visible =
              sections.where((s) => s['kind'] == selectedKind).toList();
          final sectionId = visible.any((s) => s['id'] == _sectionId)
              ? _sectionId!
              : visible.first['id'] as String;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
                    child: Text(topic['title'] as String,
                        style: Theme.of(context).textTheme.headlineMedium),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(topic['summary'] as String),
                  ),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        for (final kind in kinds)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              key: Key('content-tab-$kind'),
                              label: Text(_label(kind)),
                              selected: selectedKind == kind,
                              onSelected: (_) => setState(() {
                                _kind = kind;
                                _sectionId = null;
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (visible.length > 1)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Row(
                        children: [
                          for (final section in visible)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: OutlinedButton(
                                onPressed: () => setState(
                                    () => _sectionId = section['id'] as String),
                                style: sectionId == section['id']
                                    ? OutlinedButton.styleFrom(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer)
                                    : null,
                                child: Text(section['title'] as String),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _CourseSectionView(
                      key: ValueKey('${widget.topicId}/$sectionId'),
                      topicId: widget.topicId,
                      sectionId: sectionId,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _label(String kind) => switch (kind) {
        'lesson' => 'Lesson',
        'exercise' => 'Exercises',
        'quiz' => 'Quiz',
        _ => 'Math practice',
      };
}

class _CourseSectionView extends StatefulWidget {
  const _CourseSectionView({
    super.key,
    required this.topicId,
    required this.sectionId,
  });
  final String topicId;
  final String sectionId;

  @override
  State<_CourseSectionView> createState() => _CourseSectionViewState();
}

class _CourseSectionViewState extends State<_CourseSectionView> {
  late Future<Map<String, dynamic>> _section =
      CourseContentApi.section(widget.topicId, widget.sectionId);
  final Map<String, String> _choices = {};
  Map<String, dynamic>? _result;
  bool _submitting = false;
  String? _quizError;
  Future<List<Map<String, dynamic>>>? _attempts;

  @override
  void initState() {
    super.initState();
    if (widget.sectionId == 'quiz') {
      _attempts = CourseContentApi.quizAttempts(widget.topicId);
    }
  }

  void _retry() => setState(() =>
      _section = CourseContentApi.section(widget.topicId, widget.sectionId));

  Future<void> _submit(Map<String, dynamic> section) async {
    final questions = (section['questions'] as List).cast<Map>();
    if (_choices.length != questions.length) {
      setState(() => _quizError =
          'Answer all ${questions.length} questions before submitting.');
      return;
    }
    setState(() {
      _submitting = true;
      _quizError = null;
    });
    try {
      final result = await CourseContentApi.submitQuiz(
          widget.topicId, section['version'] as String, _choices);
      if (mounted) {
        setState(() {
          _result = result;
          _attempts = CourseContentApi.quizAttempts(widget.topicId);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _quizError =
            'Could not submit the quiz. Your selections are still here; try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _section,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _LoadError(
              onRetry: _retry,
              sessionExpired: snapshot.error is ContentSessionExpired);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final section = snapshot.data!;
        final questions = (section['questions'] as List).cast<Map>();
        final html = (section['html'] as String)
            .replaceAll('/content-assets/', '$apiBaseUrl/content-assets/');
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Card(
              color: theme.colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(section['title'] as String,
                        style: theme.textTheme.titleLarge),
                    if (section['kind'] == 'exercise' ||
                        section['kind'] == 'math') ...[
                      const SizedBox(height: 8),
                      Text(
                          'Self-directed practice — this does not affect your '
                          'graded assignment score.',
                          style: theme.textTheme.bodySmall),
                    ],
                    if (html.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 880),
                          child: LessonReader(
                            html: html,
                            key: const Key('course-section-html'),
                          ),
                        ),
                      ),
                    ],
                    for (final rawQuestion in questions) ...[
                      const SizedBox(height: 18),
                      _quizQuestion(Map<String, dynamic>.from(rawQuestion)),
                    ],
                    if (section['kind'] == 'quiz') ...[
                      const SizedBox(height: 20),
                      if (_quizError != null)
                        Text(_quizError!,
                            style: TextStyle(color: theme.colorScheme.error)),
                      if (_result == null)
                        FilledButton(
                          key: const Key('submit-course-quiz'),
                          onPressed:
                              _submitting ? null : () => _submit(section),
                          child:
                              Text(_submitting ? 'Submitting…' : 'Submit quiz'),
                        )
                      else ...[
                        Text(
                            'Score: ${_result!['score_percent']}% '
                            '(${_result!['correct_count']}/${_result!['total_questions']} correct)',
                            key: const Key('course-quiz-score'),
                            style: theme.textTheme.titleLarge),
                        Text(_result!['saved'] == true
                            ? 'Score saved. This does not change your coding assignment score.'
                            : 'Preview score only. Demo and instructor quiz results are not saved.'),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => setState(() {
                            _choices.clear();
                            _result = null;
                            _quizError = null;
                          }),
                          child: const Text('Try again'),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _attempts,
                        builder: (context, history) {
                          if (history.hasError) {
                            return OutlinedButton(
                              onPressed: () => setState(() => _attempts =
                                  CourseContentApi.quizAttempts(
                                      widget.topicId)),
                              child: const Text('Retry saved scores'),
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
                              Text('Saved scores',
                                  style: theme.textTheme.titleMedium),
                              for (final attempt in history.data!)
                                Text(
                                    '${attempt['score_percent']}% · ${attempt['correct_count']}/${attempt['total_questions']} correct'
                                    '${attempt['quiz_version'] == section['version'] ? '' : ' · earlier quiz version'}'),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _quizQuestion(Map<String, dynamic> question) {
    final id = question['id'] as String;
    final options = (question['options'] as List).cast<Map>();
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((question['prompt'] as String).replaceAll('\n', ' '),
              style: theme.textTheme.titleMedium),
          for (final option in options)
            RadioListTile<String>(
              title: Text('${option['id']}. ${option['text']}'),
              value: option['id'] as String,
              groupValue: _choices[id],
              onChanged: _result != null || _submitting
                  ? null
                  : (value) => setState(() {
                        _choices[id] = value!;
                        _quizError = null;
                      }),
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.menu_book_rounded,
                  size: 40, color: AppColors.brandDark),
              const SizedBox(height: 16),
              Text(
                  sessionExpired
                      ? 'Please sign in again'
                      : 'Course content is unavailable right now.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                  sessionExpired
                      ? 'Your session has expired. Open the account menu, log out, then sign in again. Your saved scores are unchanged.'
                      : 'Check the backend connection and retry. Your saved quiz scores are unchanged.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ])),
      );
}
