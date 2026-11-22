import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/models/assignment_progress.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/screens/assignment_workspace.dart';
import 'package:iuse_demo/screens/course_content_page.dart';
import 'package:iuse_demo/widgets/landing_page_header.dart';
export 'package:iuse_demo/widgets/landing_page_header.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/state/app_learning_progress.dart';
import 'package:iuse_demo/state/current_session.dart';
import 'package:iuse_demo/state/learning_progress_store.dart';
import 'package:iuse_demo/state/feedback_page_tracker.dart';
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/app_blocks.dart';
import 'package:http/http.dart' as http;

const landingPageBackgroundColor = AppColors.pageBackground;
const _assignmentListTimeout = Duration(seconds: 15);

class AssignmentListPage extends StatefulWidget {
  const AssignmentListPage({
    super.key,
    required this.user,
    required this.onLogout,
  });

  final AuthenticatedUser user;
  final Future<void> Function() onLogout;

  @override
  State<AssignmentListPage> createState() => _AssignmentListPageState();
}

Future<List<AssignmentDto>> fetchAssignments() async {
  const newUri = "$apiBaseUrl/assignments/";
  final response = await http
      .get(
        Uri.parse(newUri),
        headers: AuthApi.authorizedHeaders(),
      )
      .timeout(_assignmentListTimeout);
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body)['assignments'] as List;
    return data.map((e) => AssignmentDto.fromJson(e)).toList();
  } else {
    throw Exception("failed to load assignments");
  }
}

/// The three home-page panels.
enum HomePanel { assignments, oldAssignments, contents, oldContents }

class _AssignmentListPageState extends State<AssignmentListPage> {
  late Future<List<AssignmentDto>> assignments;
  HomePanel _panel = HomePanel.assignments;

  @override
  void initState() {
    super.initState();
    assignments = fetchAssignments();
  }

  void _retryAssignments() {
    setState(() {
      assignments = fetchAssignments();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    feedbackPages.homeLabel = switch (_panel) {
      HomePanel.assignments => 'Home: Assignments',
      HomePanel.oldAssignments => 'Home: Old assignments',
      HomePanel.contents => 'Home: Contents',
      HomePanel.oldContents => 'Home: Old contents',
    };

    PillTabData panelTab(
        HomePanel panel, String keyName, IconData icon, String label) {
      final selected = _panel == panel ||
          (panel == HomePanel.assignments &&
              _panel == HomePanel.oldAssignments) ||
          (panel == HomePanel.contents && _panel == HomePanel.oldContents);
      return PillTabData(
        key: Key(keyName),
        label: label,
        icon: icon,
        selected: selected,
        onTap: () => setState(() => _panel = panel),
      );
    }

    return LandingPageFrame(
      user: widget.user,
      onLogout: widget.onLogout,
      onHome: () => setState(() => _panel = HomePanel.assignments),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Center(
              child: PillTabBar(tabs: [
                panelTab(HomePanel.assignments, 'open-assignments',
                    LucideIcons.codeXml, 'Assignments'),
                panelTab(HomePanel.contents, 'open-course-contents',
                    LucideIcons.bookOpen, 'Contents'),
              ]),
            ),
          ),
          Expanded(
              child: _panel == HomePanel.contents ||
                      _panel == HomePanel.oldContents
                  ? CourseCatalogPage(
                      key: ValueKey(_panel),
                      user: widget.user,
                      onLogout: widget.onLogout,
                      embedded: true,
                      oldTopics: _panel == HomePanel.oldContents,
                      onToggleOld: () => setState(() => _panel =
                          _panel == HomePanel.oldContents
                              ? HomePanel.contents
                              : HomePanel.oldContents))
                  : FutureBuilder<List<AssignmentDto>>(
                      future: assignments,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return LandingPageContent(
                            child:
                                AssignmentLoadError(onRetry: _retryAssignments),
                          );
                        }
                        if (!snap.hasData) {
                          return const LandingPageContent(
                            child: AssignmentLoadingState(),
                          );
                        }
                        final old = _panel == HomePanel.oldAssignments;
                        final list = snap.data!
                            .where((a) => a.isOld == old)
                            .toList()
                          ..sort((a, b) => a.id.compareTo(b.id));
                        return LandingPageContent(
                          child: AssignmentCollection(
                            assignments: list,
                            oldAssignments: old,
                            oldCount:
                                snap.data!.where((a) => a.isOld).length,
                            onToggleOld: () => setState(() => _panel = old
                                ? HomePanel.assignments
                                : HomePanel.oldAssignments),
                            theme: theme,
                            onReturn: () {
                              // Rebuild when coming back so progress and scores refresh.
                              setState(() {});
                            },
                          ),
                        );
                      },
                    )),
        ],
      ),
    );
  }
}

class AssignmentLoadingState extends StatelessWidget {
  const AssignmentLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                  child: Text(
                'Loading assignments…',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              )),
            ],
          ),
        ),
        const AssignmentSkeletonCard(),
        const AssignmentSkeletonCard(),
        const AssignmentSkeletonCard(),
      ],
    );
  }
}

class AssignmentSkeletonCard extends StatelessWidget {
  const AssignmentSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final placeholderColor =
        Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget placeholder({required double width, required double height}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: placeholderColor,
          borderRadius: BorderRadius.circular(999),
        ),
      );
    }

    return AppSurface(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(AppSpacing.lg),
      radius: AppRadii.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          placeholder(width: 260, height: 18),
          const SizedBox(height: 14),
          placeholder(width: 420, height: 12),
          const SizedBox(height: 28),
          placeholder(width: 110, height: 32),
        ],
      ),
    );
  }
}

class AssignmentLoadError extends StatelessWidget {
  final VoidCallback onRetry;

  const AssignmentLoadError({
    super.key,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  LucideIcons.cloudOff,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Assignments are unavailable',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Check the connection and try loading the assignments again.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(LucideIcons.refreshCw),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AssignmentCollection extends StatelessWidget {
  final List<AssignmentDto> assignments;
  final ThemeData theme;
  final VoidCallback onReturn;

  /// The Old assignments panel: earlier test assignments, still usable, but
  /// outside the learning path and its progress.
  final bool oldAssignments;

  const AssignmentCollection({
    super.key,
    required this.assignments,
    required this.theme,
    required this.onReturn,
    this.oldAssignments = false,
    this.oldCount = 0,
    this.onToggleOld,
  });

  /// How many old assignments the last tile opens (0 hides it).
  final int oldCount;

  /// Opens the old list from the current one, and returns from it.
  final VoidCallback? onToggleOld;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useGrid = constraints.maxWidth >= 900 &&
            MediaQuery.textScalerOf(context).scale(16) <= 20;
        final assignmentDelegate = SliverChildBuilderDelegate(
          (context, index) => AssignmentCard(
            a: assignments[index],
            theme: theme,
            onReturn: onReturn,
            fillHeight: useGrid,
          ),
          childCount: assignments.length,
        );
        final next = nextAssignmentFor(assignments);
        final pythonCount =
            assignments.where((a) => !isRos2Assignment(a)).length;
        final rosCount = assignments.length - pythonCount;

        return CustomScrollView(
          // The old and current lists each start at the top.
          key: ValueKey(oldAssignments),
          slivers: [
            if (oldAssignments)
              SliverPadding(
                padding: const EdgeInsets.only(top: 20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (onToggleOld != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 20, 4),
                          child: BackToCurrentLink(
                            key: const Key('back-to-assignments'),
                            label: 'Back to assignments',
                            onTap: onToggleOld!,
                          ),
                        ),
                      const OldAssignmentsNote(),
                    ],
                  ),
                ),
              )
            else
            SliverPadding(
              padding: const EdgeInsets.only(top: 28),
              sliver: SliverToBoxAdapter(
                child: ProgressSummary(
                  totalAssignments: assignments.length,
                  assignmentIds: {for (final item in assignments) item.id},
                  nextAssignment: next,
                  onOpenNext: next == null
                      ? null
                      : () => openAssignment(context, next, onReturn),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        oldAssignments
                            ? 'Old assignments'
                            : 'Coding assignments',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (pythonCount > 0)
                          '$pythonCount Python ${pythonCount == 1 ? 'challenge' : 'challenges'}',
                        if (rosCount > 0)
                          '$rosCount ROS 2 ${rosCount == 1 ? 'challenge' : 'challenges'}',
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (useGrid)
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 8),
                sliver: SliverGrid(
                  key: const Key('assignment-grid'),
                  delegate: assignmentDelegate,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 272,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 8),
                sliver: SliverList(
                  key: const Key('assignment-list'),
                  delegate: assignmentDelegate,
                ),
              ),
            if (learningProgress.lessonToResume case final resume?
                when !oldAssignments && currentSession != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: KeepReadingTile(
                    topicId: resume.key,
                    progress: resume.value,
                    onReturn: onReturn,
                  ),
                ),
              ),
            if (!oldAssignments && oldCount > 0 && onToggleOld != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: OldCollectionTile(
                    key: const Key('open-old-assignments'),
                    icon: LucideIcons.archive,
                    title: 'Old assignments',
                    subtitle: '$oldCount earlier '
                        '${oldCount == 1 ? 'assignment' : 'assignments'}, '
                        'still open for practice',
                    onTap: onToggleOld!,
                  ),
                ),
              ),
            // Room below the last card for the floating Feedback button.
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        );
      },
    );
  }
}

/// The course lesson read most recently, with how far it got and what
/// comes next. Opens the topic where the student left off.
class KeepReadingTile extends StatelessWidget {
  const KeepReadingTile({
    super.key,
    required this.topicId,
    required this.progress,
    required this.onReturn,
  });

  final String topicId;
  final TopicProgress progress;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = currentSession;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text('Keep reading', style: theme.textTheme.titleLarge),
        ),
        AppSurface(
          key: const Key('keep-reading-tile'),
          padding: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            onTap: session == null
                ? null
                : () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(
                      builder: (_) => CourseTopicPage(
                        topicId: topicId,
                        user: session.user,
                        onLogout: session.onLogout,
                      ),
                    ))
                    .then((_) => onReturn()),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(children: [
                const IconTile(icon: LucideIcons.bookOpen, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${progress.title} · Lesson',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (progress.nextHeading.isNotEmpty)
                        Text(
                          'Next: ${progress.nextHeading}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress.lessonPercent / 100,
                      minHeight: 6,
                      color: AppColors.brand,
                      backgroundColor: AppColors.neutralContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${progress.lessonPercent}%',
                    style: theme.textTheme.labelMedium),
                const SizedBox(width: 4),
                const Icon(LucideIcons.chevronRight, size: 18),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

/// Explains the Old assignments panel above its cards.
class OldAssignmentsNote extends StatelessWidget {
  const OldAssignmentsNote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        key: const Key('old-assignments-note'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.archive, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'These are the earlier test assignments. You can still open, '
                'run, and practise them; they are not part of your current '
                'learning path.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LandingPageFrame extends StatelessWidget {
  final Widget body;
  final AuthenticatedUser user;
  final Future<void> Function() onLogout;
  final VoidCallback? onHome;

  const LandingPageFrame({
    super.key,
    required this.body,
    required this.user,
    required this.onLogout,
    this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('landing-page-scaffold'),
      appBar: LandingPageHeader(user: user, onLogout: onLogout, onHome: onHome),
      backgroundColor: landingPageBackgroundColor,
      body: LearningBackdrop(child: body),
    );
  }
}

bool isRos2Assignment(AssignmentDto a) => a.language.contains('ros2');

/// The first unfinished assignment, preferring work already in progress.
AssignmentDto? nextAssignmentFor(List<AssignmentDto> assignments) {
  final unfinished = assignments
      .where((a) => (learningProgress.bestScores[a.id] ?? 0) < 100)
      .toList();
  if (unfinished.isEmpty) return null;
  return unfinished.firstWhere(
    (a) => learningProgress.hasAttempted(a.id),
    orElse: () => unfinished.first,
  );
}

void openAssignment(
  BuildContext context,
  AssignmentDto a,
  VoidCallback onReturn,
) {
  Navigator.push(
    context,
    MaterialPageRoute(
      settings: RouteSettings(arguments: FeedbackPage(a.title)),
      builder: (_) => MyHomePage(
        title: a.title,
        id: a.id,
        displayNumber: a.displayNumber,
      ),
    ),
  ).then((_) {
    // Rebuild when the learner returns so the latest score is visible.
    onReturn();
  });
}

String assignmentDisplayTitle(AssignmentDto a) {
  final prefix = 'Assignment ${a.id}:';
  return a.title.startsWith(prefix)
      ? a.title.substring(prefix.length).trim()
      : a.title;
}

class ProgressSummary extends StatelessWidget {
  final int totalAssignments;

  /// When given, only these assignments count as completed, so finished old
  /// assignments never inflate the current learning path.
  final Set<int>? assignmentIds;
  final AssignmentDto? nextAssignment;
  final VoidCallback? onOpenNext;

  const ProgressSummary({
    super.key,
    required this.totalAssignments,
    this.assignmentIds,
    this.nextAssignment,
    this.onOpenNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ids = assignmentIds;
    final completedAssignments = learningProgress.bestScores.entries
        .where((entry) =>
            entry.value == 100 && (ids == null || ids.contains(entry.key)))
        .length
        .clamp(0, totalAssignments);
    final progress =
        totalAssignments == 0 ? 0.0 : completedAssignments / totalAssignments;
    final percentage = (progress * 100).round();
    // Nothing completed yet is a starting point, not a failing grade.
    final progressColor = completedAssignments == 0
        ? AppColors.brand
        : performanceColor(percentage);
    final allDone =
        totalAssignments > 0 && completedAssignments == totalAssignments;

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'YOUR LEARNING PATH',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.brand,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          allDone
              ? 'Every assignment complete. Great work!'
              : completedAssignments == 0
                  ? 'Start building your robotics skills'
                  : 'Keep building your robotics skills',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$percentage%',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: progressColor,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '$completedAssignments of $totalAssignments assignments completed',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: LinearProgressIndicator(
            value: progress,
            color: progressColor,
            minHeight: 10,
            backgroundColor: AppColors.neutralContainer,
          ),
        ),
      ],
    );

    final next = nextAssignment;
    final upNext = next == null
        ? null
        : Container(
            key: const Key('up-next-panel'),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.brandTint,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.flag,
                        size: 18, color: AppColors.brandDark),
                    const SizedBox(width: 6),
                    Text(
                      learningProgress.hasAttempted(next.id)
                          ? 'Pick up where you left off'
                          : 'Up next',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: AppColors.brandDark),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Assignment ${next.shownNumber} · ${assignmentDisplayTitle(next)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.brandDeep,
                  ),
                ),
                if (learningProgress.bestScores[next.id] case final best?
                    when learningProgress.hasAttempted(next.id)) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    ScoreRing(
                      key: const Key('up-next-score-ring'),
                      score: best,
                      color: performanceColor(best),
                      size: 56,
                      stroke: 5,
                      label: 'best',
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (learningProgress.checkSummaries[next.id]
                              case final checks?) ...[
                            ChecksMeter(
                              passed: checks.passed,
                              total: checks.total,
                              width: 110,
                            ),
                            if (checks.nextFailing.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text.rich(
                                key: const Key('up-next-fix'),
                                TextSpan(children: [
                                  const TextSpan(
                                    text: 'Next to fix: ',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  TextSpan(text: checks.nextFailing),
                                ]),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: AppColors.brandDeep),
                              ),
                            ],
                          ] else
                            Text(
                              '${learningProgress.attemptCounts[next.id] ?? 0} '
                              'runs so far',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.brandDeep),
                            ),
                        ],
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('up-next-button'),
                  onPressed: onOpenNext,
                  icon: const Icon(LucideIcons.play, size: 20),
                  label: Text(learningProgress.hasAttempted(next.id)
                      ? 'Continue learning'
                      : 'Begin'),
                ),
              ],
            ),
          );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      // About 5% shorter than uniform padding, for a less bulky card.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg - 5,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: appCardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (upNext == null) return summary;
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [summary, const SizedBox(height: 20), upNext],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 3, child: summary),
              const SizedBox(width: 28),
              Expanded(flex: 2, child: upNext),
            ],
          );
        },
      ),
    );
  }
}

class LandingPageContent extends StatelessWidget {
  final Widget child;

  const LandingPageContent({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth > 1180 ? 1180.0 : constraints.maxWidth;

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            key: const Key('landing-page-content'),
            width: width,
            height: constraints.maxHeight,
            child: child,
          ),
        );
      },
    );
  }
}

class ListAssignment extends StatelessWidget {
  final AssignmentDto a;
  final ThemeData theme;
  final VoidCallback onReturn;

  const ListAssignment({
    super.key,
    required this.a,
    required this.theme,
    required this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final state = learningProgress.assignmentState(
      a.id,
      assignmentVersion: a.version,
      starterCode: a.code,
      hasServerDraft: a.hasSavedDraft,
    );
    final hasAccuracy = lastAttemptAccuracy.containsKey(a.id);
    final accuracyText = hasAccuracy
        ? '${state.label} • Last score: ${lastAttemptAccuracy[a.id]}%'
        : state.label;
    final accuracyColor = hasAccuracy
        ? performanceColor(lastAttemptAccuracy[a.id]!)
        : theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              a.title,
              style: theme.textTheme.titleLarge!
                  .copyWith(color: theme.colorScheme.onSecondaryFixedVariant),
            ),
            const SizedBox(height: 8),
            Text(
              a.description,
              style: theme.textTheme.bodySmall!
                  .copyWith(color: theme.colorScheme.secondary),
            ),
            const SizedBox(height: 8),
            Text(
              accuracyText,
              style: TextStyle(fontSize: 12, color: accuracyColor),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: MaterialButton(
                color: theme.colorScheme.primaryFixedDim,
                textColor: theme.colorScheme.onTertiaryFixed,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      settings: RouteSettings(arguments: FeedbackPage(a.title)),
                      builder: (_) => MyHomePage(
                        title: a.title,
                        id: a.id,
                        displayNumber: a.displayNumber,
                      ),
                    ),
                  ).then((_) {
                    // when we pop back, call the callback to rebuild
                    onReturn();
                  });
                },
                child: const Text('Go to Assignment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AssignmentCard extends StatelessWidget {
  final AssignmentDto a;
  final ThemeData theme;
  final VoidCallback onReturn;

  const AssignmentCard({
    super.key,
    required this.a,
    required this.theme,
    required this.onReturn,
    this.fillHeight = false,
  });

  /// In the fixed-height grid, pin status and actions to the card bottom.
  final bool fillHeight;

  String get _displayTitle => assignmentDisplayTitle(a);

  void _openAssignment(BuildContext context) =>
      openAssignment(context, a, onReturn);

  @override
  Widget build(BuildContext context) {
    final progressState = learningProgress.assignmentState(
      a.id,
      assignmentVersion: a.version,
      starterCode: a.code,
      hasServerDraft: a.hasSavedDraft,
    );
    final hasAccuracy = lastAttemptAccuracy.containsKey(a.id);
    final score = lastAttemptAccuracy[a.id];
    final scoreColor = hasAccuracy
        ? performanceColor(score!)
        : theme.colorScheme.onSurfaceVariant;
    final solutionRevealed = solutionRevealedAssignments.contains(a.id);
    final statusText = progressState.label;
    final statusColor = progressState == AssignmentProgressState.completed
        ? AppColors.success
        : progressState == AssignmentProgressState.inProgress
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant;

    final ros2 = isRos2Assignment(a);
    final completed = progressState == AssignmentProgressState.completed;
    // On phones the track tag moves into the status row so titles keep the
    // full card width.
    final compact = MediaQuery.sizeOf(context).width < 600;
    final trackTag = StatusPill(
      key: const Key('assignment-track-tag'),
      label: ros2 ? 'ROS 2' : 'Python',
      size: PillSize.small,
      color: ros2 ? theme.colorScheme.secondary : AppColors.inkMuted,
    );

    return AppSurface(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      radius: AppRadii.lg,
      padding: EdgeInsets.zero,
      borderColor:
          completed ? AppColors.success.withValues(alpha: 0.45) : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: completed
                        ? AppColors.successContainer
                        : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    a.shownNumber.toString().padLeft(2, '0'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: completed
                          ? AppColors.success
                          : theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayTitle,
                        maxLines: fillHeight ? 2 : null,
                        overflow: fillHeight ? TextOverflow.ellipsis : null,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 19,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        a.description,
                        maxLines: fillHeight ? 3 : null,
                        overflow: fillHeight ? TextOverflow.ellipsis : null,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      trackTag,
                      // The best score at a glance once there is one.
                      if (hasAccuracy) ...[
                        const SizedBox(height: AppSpacing.sm),
                        ScoreRing(
                          key: const Key('assignment-score-ring'),
                          score: learningProgress.bestScores[a.id] ?? score!,
                          color: performanceColor(
                              learningProgress.bestScores[a.id] ?? score!),
                          size: 54,
                          stroke: 5,
                          label: 'best',
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
            // The latest run's checks, when this device has them.
            if (learningProgress.checkSummaries[a.id] case final checks?) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(left: 60),
                child: ChecksMeter(
                  key: const Key('assignment-checks-meter'),
                  passed: checks.passed,
                  total: checks.total,
                  width: 160,
                ),
              ),
            ],
            if (fillHeight) const Spacer() else const SizedBox(height: 22),
            const Divider(),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final status = Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (compact) trackTag,
                    StatusPill(
                      label: statusText,
                      color: statusColor,
                      icon: switch (progressState) {
                        AssignmentProgressState.completed =>
                          LucideIcons.circleCheck,
                        AssignmentProgressState.attempted =>
                          LucideIcons.flaskConical,
                        AssignmentProgressState.inProgress =>
                          LucideIcons.pencil,
                        AssignmentProgressState.notStarted =>
                          LucideIcons.clock,
                      },
                    ),
                    if (solutionRevealed)
                      StatusPill(
                        key: const Key('solution-viewed-badge'),
                        label: 'Solution viewed',
                        icon: LucideIcons.eye,
                        color: theme.colorScheme.primary,
                      ),
                  ],
                );
                final attempts = learningProgress.attemptCounts[a.id] ?? 0;
                final best = learningProgress.bestScores[a.id] ?? score;
                final muted = theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
                final stats = Text.rich(
                  key: const Key('assignment-stats-line'),
                  TextSpan(style: muted, children: [
                    if (hasAccuracy) ...[
                      const TextSpan(text: 'Best '),
                      TextSpan(
                        text: '$best%',
                        style: TextStyle(
                          color: performanceColor(best!),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const TextSpan(text: '  ·  Last '),
                      TextSpan(
                        text: '$score%',
                        style: TextStyle(
                          color: scoreColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(
                        text: '  ·  $attempts '
                            '${attempts == 1 ? 'attempt' : 'attempts'}',
                      ),
                    ] else
                      const TextSpan(text: 'No attempts yet'),
                  ]),
                );
                final statusBlock = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [status, const SizedBox(height: 6), stats],
                );
                final button = FilledButton.icon(
                  onPressed: () => _openAssignment(context),
                  icon: const Icon(LucideIcons.arrowRight, size: 18),
                  label: Text(progressState == AssignmentProgressState.completed
                      ? 'Review assignment'
                      : progressState == AssignmentProgressState.notStarted
                          ? 'Start assignment'
                          : 'Continue assignment'),
                );

                if (constraints.maxWidth < 440) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                          alignment: Alignment.centerLeft, child: statusBlock),
                      const SizedBox(height: 16),
                      button,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: statusBlock),
                    const SizedBox(width: 16),
                    button,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
