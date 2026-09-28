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

    return LandingPageFrame(
      user: widget.user,
      onLogout: widget.onLogout,
      onHome: () => setState(() => _showContents = false),
      body: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
        final useGrid = constraints.maxWidth >= 900;
        final assignmentDelegate = SliverChildBuilderDelegate(
          (context, index) => AssignmentCard(
            a: assignments[index],
            theme: theme,
            onReturn: onReturn,
          ),
          childCount: assignments.length,
        );

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(top: 32),
              sliver: SliverToBoxAdapter(
                child: ProgressSummary(totalAssignments: assignments.length),
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
                    mainAxisExtent: 290,
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
      body: body,
    );
  }
}

class ProgressSummary extends StatelessWidget {
  final int totalAssignments;

  const ProgressSummary({
    super.key,
    required this.totalAssignments,
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
    final progressColor = performanceColor(percentage);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your progress',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$completedAssignments of $totalAssignments assignments completed',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '$percentage%',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: progressColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              color: progressColor,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.8),
            ),
          ),
        ],
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
  });

  String get _displayTitle {
    final prefix = 'Assignment ${a.id}:';
    return a.title.startsWith(prefix)
        ? a.title.substring(prefix.length).trim()
        : a.title;
  }

  void _openAssignment(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyHomePage(title: a.title, id: a.id),
      ),
    ).then((_) {
      // Rebuild when the learner returns so the latest score is visible.
      onReturn();
    });
  }

  @override
  Widget build(BuildContext context) {
    final progressState = learningProgress.assignmentState(
      a.id,
      assignmentVersion: a.version,
      starterCode: a.code,
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      elevation: 0,
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
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
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    a.id.toString().padLeft(2, '0'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
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
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        a.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final status = Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
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
                        key: const Key('latest-score-badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: scoreColor.withValues(alpha: 0.12),
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
                  label: const Text('Start assignment'),
                );

                if (constraints.maxWidth < 520) {
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
                    status,
                    const Spacer(),
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
