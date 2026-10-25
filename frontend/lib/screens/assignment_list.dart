import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/models/assignment_progress.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/screens/assignment_workspace.dart';
import 'package:iuse_demo/screens/course_content_page.dart';
import 'package:iuse_demo/widgets/landing_page_header.dart';
export 'package:iuse_demo/widgets/landing_page_header.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/state/app_learning_progress.dart';
import 'package:iuse_demo/state/feedback_page_tracker.dart';
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/theme/app_theme.dart';
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

class _AssignmentListPageState extends State<AssignmentListPage> {
  late Future<List<AssignmentDto>> assignments;
  bool _showContents = false;

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
    feedbackPages.homeLabel =
        _showContents ? 'Home: Contents' : 'Home: Assignments';

    return LandingPageFrame(
      user: widget.user,
      onLogout: widget.onLogout,
      onHome: () => setState(() => _showContents = false),
      body: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            shape: const Border(bottom: BorderSide(color: AppColors.border)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    key: const Key('open-assignments'),
                    selected: !_showContents,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _showContents = false),
                    avatar: Icon(Icons.code_rounded,
                        color: !_showContents
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.primary,
                        size: 18),
                    label: Text('Assignments',
                        style: TextStyle(
                            color: !_showContents
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.primary)),
                    selectedColor: theme.colorScheme.primary,
                    side: BorderSide.none,
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    key: const Key('open-course-contents'),
                    selected: _showContents,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _showContents = true),
                    avatar: Icon(Icons.menu_book_rounded,
                        size: 18,
                        color: _showContents
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.primary),
                    label: Text('Contents',
                        style: TextStyle(
                            color: _showContents
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.primary)),
                    selectedColor: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
              child: _showContents
                  ? CourseCatalogPage(
                      user: widget.user,
                      onLogout: widget.onLogout,
                      embedded: true)
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
                        final list = snap.data!
                          ..sort((a, b) => a.id.compareTo(b.id));
                        return LandingPageContent(
                          child: AssignmentCollection(
                            assignments: list,
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
              Text(
                'Loading assignments…',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
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
                  Icons.cloud_off_rounded,
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
                icon: const Icon(Icons.refresh_rounded),
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

  const AssignmentCollection({
    super.key,
    required this.assignments,
    required this.theme,
    required this.onReturn,
  });

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
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(top: 28),
              sliver: SliverToBoxAdapter(
                child: ProgressSummary(
                  totalAssignments: assignments.length,
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
                    Text('Coding assignments',
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
                padding: const EdgeInsets.only(bottom: 32),
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
                padding: const EdgeInsets.only(bottom: 32),
                sliver: SliverList(
                  key: const Key('assignment-list'),
                  delegate: assignmentDelegate,
                ),
              ),
          ],
        );
      },
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
      builder: (_) => MyHomePage(title: a.title, id: a.id),
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
  final AssignmentDto? nextAssignment;
  final VoidCallback? onOpenNext;

  const ProgressSummary({
    super.key,
    required this.totalAssignments,
    this.nextAssignment,
    this.onOpenNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completedAssignments = learningProgress.bestScores.values
        .where((accuracy) => accuracy == 100)
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
                    const Icon(Icons.flag_rounded,
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
                  'Assignment ${next.id} · ${assignmentDisplayTitle(next)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.brandDeep,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('up-next-button'),
                  onPressed: onOpenNext,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
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
                      builder: (_) => MyHomePage(title: a.title, id: a.id),
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
    final statusBackground = progressState == AssignmentProgressState.completed
        ? AppColors.successContainer
        : progressState == AssignmentProgressState.inProgress
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest;

    final ros2 = isRos2Assignment(a);
    final completed = progressState == AssignmentProgressState.completed;
    // On phones the track tag moves into the status row so titles keep the
    // full card width.
    final compact = MediaQuery.sizeOf(context).width < 600;
    final trackTag = Container(
      key: const Key('assignment-track-tag'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ros2
            ? theme.colorScheme.secondaryContainer
            : AppColors.neutralContainer,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        ros2 ? 'ROS 2' : 'Python',
        style: theme.textTheme.labelSmall?.copyWith(
          color: ros2
              ? theme.colorScheme.onSecondaryContainer
              : AppColors.inkMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: completed
              ? AppColors.success.withValues(alpha: 0.45)
              : AppColors.border,
        ),
        boxShadow: appCardShadow,
      ),
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
                    a.id.toString().padLeft(2, '0'),
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
                  trackTag,
                ],
              ],
            ),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: statusBackground,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            switch (progressState) {
                              AssignmentProgressState.completed =>
                                Icons.check_circle_rounded,
                              AssignmentProgressState.attempted =>
                                Icons.science_outlined,
                              AssignmentProgressState.inProgress =>
                                Icons.edit_outlined,
                              AssignmentProgressState.notStarted =>
                                Icons.schedule_rounded,
                            },
                            size: 16,
                            color: statusColor,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            statusText,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasAccuracy)
                      Container(
                        key: const Key('best-score-badge'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.neutralContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                            'Best score: ${learningProgress.bestScores[a.id] ?? score}%',
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: performanceColor(
                                    learningProgress.bestScores[a.id] ??
                                        score!),
                                fontWeight: FontWeight.w700)),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: AppColors.neutralContainer,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(
                          'Attempted: ${learningProgress.attemptCounts[a.id] ?? 0}',
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700)),
                    ),
                    if (hasAccuracy)
                      Container(
                        key: const Key('latest-score-badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                              scoreColor.withValues(alpha: 0.12), Colors.white),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Last score: ${lastAttemptAccuracy[a.id]}%',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scoreColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (solutionRevealed)
                      Container(
                        key: const Key('solution-viewed-badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.visibility_rounded,
                              size: 16,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Solution viewed',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
                final button = FilledButton.icon(
                  onPressed: () => _openAssignment(context),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
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
                      Align(alignment: Alignment.centerLeft, child: status),
                      const SizedBox(height: 16),
                      button,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: status),
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
