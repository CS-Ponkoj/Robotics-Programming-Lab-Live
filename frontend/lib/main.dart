import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/darcula.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/screens/assignment_list.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:highlight/languages/python.dart';

// In-memory store for last accuracies (AssignmentList reads this)
Map<int, int> lastAttemptAccuracy = {};
Set<int> solutionRevealedAssignments = {};

void main() {
  runApp(const MyApp());
}

Future<AssignmentDto> fetchAssignment(int id) async {
  final resp = await http.get(Uri.parse("$apiBaseUrl/assignments/$id"));
  if (resp.statusCode == 200) {
    return AssignmentDto.fromJson(jsonDecode(resp.body));
  }
  throw Exception("Failed to load assignment $id");
}

Future<UnittestFeedbackDto> fetchUnittestFeedback(int id, String code) async {
  if (code.isEmpty) {
    return UnittestFeedbackDto(
      id: -1,
      pass: false,
      execSuccess: false,
      codeOutput: "",
      codeExecResult: "",
      testedVals: [],
      unittestFeedback: [],
      unittestPassResults: [],
      hint: "",
    );
  }
  final resp = await http.post(
    Uri.parse("$apiBaseUrl/grade/$id"),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'code': code}),
  );
  if (resp.statusCode == 200) {
    return UnittestFeedbackDto.fromJson(jsonDecode(resp.body));
  }
  throw Exception("Failed to load feedback for $id");
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iuse_demo',
      theme: buildAppTheme(),
      home: const AssignmentListPage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title, required this.id});
  final String title;
  final int id;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late Future<AssignmentDto> _assignment;
  late Future<UnittestFeedbackDto> _feedback;
  late CodeController _controller;
  String _code = "";
  bool _enableFeedback = true;
  bool _submitted = false;
  bool _isRunning = false;
  bool _init = true;
  int _selectedWorkspaceTab = 0;

  @override
  void initState() {
    super.initState();
    _controller =
        CodeController(language: python, params: EditorParams(tabSpaces: 4));
    _assignment = fetchAssignment(widget.id);
    _feedback = fetchUnittestFeedback(widget.id, "");
  }

  void _runTests() {
    setState(() {
      _submitted = true;
      _isRunning = true;
      _feedback = fetchUnittestFeedback(widget.id, _code);
    });

    _feedback.then(
      (feedback) {
        final passed = feedback.unittestFeedback
            .asMap()
            .entries
            .where((entry) =>
                entry.key < feedback.unittestPassResults.length &&
                feedback.unittestPassResults[entry.key])
            .length;
        final total = feedback.unittestPassResults.length;

        if (!mounted) {
          return;
        }
        setState(() {
          if (total > 0) {
            lastAttemptAccuracy[widget.id] = ((passed / total) * 100).round();
          }
          _isRunning = false;
        });
      },
      onError: (_) {
        if (mounted) {
          setState(() => _isRunning = false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final useDesktopLayout = MediaQuery.sizeOf(context).width >= 900;
    final submissionStatus = lastAttemptAccuracy.containsKey(widget.id)
        ? 'Last score: ${lastAttemptAccuracy[widget.id]}%'
        : _submitted
            ? 'Submission sent'
            : 'Not submitted';
    final assignmentStatus = solutionRevealedAssignments.contains(widget.id)
        ? '$submissionStatus • Solution viewed'
        : submissionStatus;
    final appBar = AssignmentPageHeader(
      title: widget.title,
      assignmentId: widget.id,
      status: assignmentStatus,
      feedbackEnabled: _enableFeedback,
      onBack: () => Navigator.pop(context),
      onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
      onFeedbackChanged: (value) {
        setState(() => _enableFeedback = value);
      },
    );

    return Scaffold(
      appBar: appBar,
      body: Column(children: [
        if (!useDesktopLayout)
          AssignmentWorkspaceNavigation(
            selectedIndex: _selectedWorkspaceTab,
            onDestinationSelected: (index) {
              setState(() => _selectedWorkspaceTab = index);
            },
          ),
        Expanded(
          child: Row(children: [
            // ─── Left: code editor ─────────────────────────
            if (useDesktopLayout || _selectedWorkspaceTab == 0)
              Expanded(
                flex: 1,
                child: Container(
                  key: const Key('assignment-editor-panel'),
                  color: Theme.of(context).colorScheme.secondaryFixedDim,
                  child: Column(children: [
                    AssignmentEditorToolbar(
                      isRunning: _isRunning,
                      onRun: _runTests,
                    ),
                    Expanded(
                      child: FutureBuilder<AssignmentDto>(
                        future: _assignment,
                        builder: (ctx, snap) {
                          if (snap.hasData) {
                            if (_init) {
                              _code = snap.data!.code;
                              _controller.text = _code;
                              _init = false;
                            }
                            return CodeTheme(
                              data: CodeThemeData(styles: darculaTheme),
                              child: CodeField(
                                controller: _controller,
                                expands: true,
                                minLines: null,
                                onChanged: (_) => _code = _controller.fullText,
                              ),
                            );
                          }
                          if (snap.hasError) {
                            return const Center(child: Text("Error"));
                          }
                          return const Center(
                              child: CircularProgressIndicator());
                        },
                      ),
                    ),
                  ]),
                ),
              ),

            // ─── Right: scenario + feedback ────────────────
            if (useDesktopLayout)
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            if (useDesktopLayout || _selectedWorkspaceTab != 0)
              Expanded(
                flex: 1,
                child: Column(children: [
                  // scenario half
                  if (useDesktopLayout || _selectedWorkspaceTab == 1)
                    Expanded(
                      flex: 1,
                      child: Column(children: [
                        const AssignmentPanelHeader(
                          icon: Icons.menu_book_rounded,
                          title: 'Instructions',
                          subtitle: 'Review the scenario and task',
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            key: const Key('assignment-instructions-panel'),
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: FutureBuilder<AssignmentDto>(
                              future: _assignment,
                              builder: (ctx, snap) {
                                if (snap.hasData) {
                                  return AssignmentInstructions(
                                    assignmentId: widget.id,
                                    html: snap.data!.htmlDesc
                                        .replaceAll(
                                          "http://localhost:5000",
                                          apiBaseUrl,
                                        )
                                        .replaceAll(
                                          "http://127.0.0.1:5000",
                                          apiBaseUrl,
                                        ),
                                    solutionRevealed:
                                        solutionRevealedAssignments.contains(
                                      widget.id,
                                    ),
                                    onSolutionRevealed: () {
                                      setState(() {
                                        solutionRevealedAssignments.add(
                                          widget.id,
                                        );
                                      });
                                    },
                                  );
                                }
                                if (snap.hasError) {
                                  return const Text("Error loading scenario");
                                }
                                return const Center(
                                    child: CircularProgressIndicator());
                              },
                            ),
                          ),
                        ),
                      ]),
                    ),

                  // feedback half
                  if (useDesktopLayout || _selectedWorkspaceTab == 2)
                    Expanded(
                      flex: 1,
                      child: Column(
                          key: const Key('assignment-results-panel'),
                          children: [
                            const AssignmentPanelHeader(
                              icon: Icons.fact_check_rounded,
                              title: 'Results',
                              subtitle: 'Review test outcomes and feedback',
                            ),
                            Expanded(
                              child: _submitted
                                  ? FutureBuilder<UnittestFeedbackDto>(
                                      future: _feedback,
                                      builder: (ctx, snap) {
                                        if (snap.connectionState ==
                                            ConnectionState.waiting) {
                                          return const Center(
                                              child:
                                                  CircularProgressIndicator());
                                        }
                                        if (snap.hasError) {
                                          return const Center(
                                              child:
                                                  Text("Error running tests"));
                                        }
                                        if (snap.hasData) {
                                          // **HERE** we now call your `Feedback` widget
                                          return _enableFeedback
                                              ? Feedback(data: snap.data!)
                                              : NoFeedback(data: snap.data!);
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    )
                                  : const _EmptyResultsState(),
                            ),
                          ]),
                    ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class AssignmentInstructions extends StatelessWidget {
  const AssignmentInstructions({
    super.key,
    required this.html,
    this.assignmentId = 1,
    this.solutionRevealed = false,
    this.onSolutionRevealed,
  });

  final String html;
  final int assignmentId;
  final bool solutionRevealed;
  final VoidCallback? onSolutionRevealed;

  @override
  Widget build(BuildContext context) {
    final sections = AssignmentInstructionSections.fromHtml(html);
    final maintainedSolutionHtml = workedSolutionHtmlFor(assignmentId);
    final solutionHtml = maintainedSolutionHtml.isNotEmpty
        ? maintainedSolutionHtml
        : sections.solution;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InstructionSectionCard(
          key: const Key('instruction-scenario-section'),
          icon: Icons.explore_outlined,
          title: 'Scenario',
          subtitle: 'Understand the environment and objective',
          html: sections.scenario,
        ),
        if (sections.task.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _InstructionSectionCard(
            key: const Key('instruction-task-section'),
            icon: Icons.task_alt_rounded,
            title: 'Your task',
            subtitle: 'What your solution needs to calculate',
            html: sections.task,
          ),
        ],
        if (sections.support.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _InstructionSectionCard(
            key: const Key('instruction-support-section'),
            icon: Icons.tips_and_updates_outlined,
            title: 'Helpful information',
            subtitle: 'Given data, hints, and assumptions',
            html: sections.support,
          ),
        ],
        if (solutionHtml.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _SolutionSection(
            html: solutionHtml,
            revealed: solutionRevealed,
            onReveal: onSolutionRevealed,
          ),
        ],
      ],
    );
  }
}

String workedSolutionHtmlFor(int assignmentId) {
  return switch (assignmentId) {
    1 => '''
      <p><strong>1. Reach the obstacle</strong></p>
      <p>The robot travels diagonally from (2, 1) to the hit point (4, 3), so the distance is <strong>√((4 − 2)² + (3 − 1)²) = √8 ≈ 2.828 units</strong>.</p>
      <p><strong>2. Follow the obstacle boundary</strong></p>
      <p>The clockwise boundary route covers three sides of 3 units each, for <strong>9 units</strong>.</p>
      <p><strong>3. Continue to the goal</strong></p>
      <p>The distance from the leave point (4, 6) to the goal (8, 9) is <strong>√((8 − 4)² + (9 − 6)²) = 5 units</strong>.</p>
      <p><strong>Total path</strong>: √8 + 9 + 5 = <strong>16.82842712474619 units</strong>.</p>
    ''',
    2 => '''
      <p><strong>1. Reach the obstacle</strong></p>
      <p>The robot travels 4 units from O(0,0) to point A(4,-1) using the assignment's simplified path model.</p>
      <p><strong>2. Follow the obstacle boundary</strong></p>
      <p>The right-turn route A → D → C → B covers three edges of 2 units each, for 6 units.</p>
      <p><strong>3. Continue to the goal</strong></p>
      <p>The assignment model uses 4 units from the obstacle to G(10,0).</p>
      <p><strong>Total path</strong>: 4 + 6 + 4 = <strong>14 units</strong>.</p>
    ''',
    3 => '''
      <p><strong>1. Compare paths to the elevators</strong></p>
      <ul>
        <li>Main elevator path: approximately <strong>14.39 m</strong>.</li>
        <li>Service elevator path: approximately <strong>10.05 m</strong>.</li>
      </ul>
      <p><strong>2. Include elevator wait and travel time</strong></p>
      <ul>
        <li>Main elevator total: approximately <strong>119.39 seconds</strong>.</li>
        <li>Service elevator total: approximately <strong>120.05 seconds</strong>.</li>
      </ul>
      <p>The <strong>Main Elevator</strong> is the optimal choice because its faster travel time narrowly offsets its longer walking path and wait.</p>
      <p>The dynamic-obstacle detour must be included in both approach-time calculations before making the comparison.</p>
    ''',
    4 => '''
      <p><strong>1. Build the polar histogram</strong></p>
      <p>For each sector, compute obstacle density with the inverse-square relationship: <strong>density = 1 / distance²</strong>.</p>
      <p><strong>2. Search around the goal direction</strong></p>
      <p>Compare the sectors from 80° through 100° and select the lowest-density direction closest to the 90° goal heading.</p>
      <p><strong>Result</strong></p>
      <p>The selected sector is <strong>90°</strong>, with an obstacle-density value of approximately <strong>0.006944</strong>.</p>
    ''',
    _ => '',
  };
}

class AssignmentInstructionSections {
  const AssignmentInstructionSections({
    required this.scenario,
    required this.task,
    required this.support,
    required this.solution,
  });

  final String scenario;
  final String task;
  final String support;
  final String solution;

  static final RegExp _sectionHeading = RegExp(
    r'<p><strong(?:\s[^>]*)?>\s*(Scenario|Given Data|Task|Questions?|Hints?|Assumptions?|Solution):?\s*</strong></p>',
    caseSensitive: false,
  );

  factory AssignmentInstructionSections.fromHtml(String html) {
    final matches = _sectionHeading.allMatches(html).toList();
    if (matches.isEmpty) {
      return AssignmentInstructionSections(
        scenario: html,
        task: '',
        support: '',
        solution: '',
      );
    }

    final buffers = <String, StringBuffer>{
      'scenario': StringBuffer(html.substring(0, matches.first.start)),
      'task': StringBuffer(),
      'support': StringBuffer(),
      'solution': StringBuffer(),
    };

    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final heading = match.group(1)!.toLowerCase();
      final end =
          index + 1 < matches.length ? matches[index + 1].start : html.length;
      final content = html.substring(match.end, end);
      final destination = switch (heading) {
        'scenario' => 'scenario',
        'task' || 'question' || 'questions' => 'task',
        'solution' => 'solution',
        _ => 'support',
      };

      if (buffers[destination]!.isNotEmpty) {
        buffers[destination]!
            .write('<p><strong>${match.group(1)}</strong></p>');
      }
      buffers[destination]!.write(content);
    }

    return AssignmentInstructionSections(
      scenario: buffers['scenario']!.toString(),
      task: buffers['task']!.toString(),
      support: buffers['support']!.toString(),
      solution: buffers['solution']!.toString(),
    );
  }
}

class _InstructionSectionCard extends StatelessWidget {
  const _InstructionSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.html,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String html;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      label: '$title instruction section',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            HtmlWidget(
              html,
              textStyle: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'roboto-serif',
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SolutionSection extends StatelessWidget {
  const _SolutionSection({
    required this.html,
    required this.revealed,
    this.onReveal,
  });

  final String html;
  final bool revealed;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const Key('instruction-solution-section'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: revealed
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.visibility_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Worked solution',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Solution viewed',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                HtmlWidget(
                  html,
                  textStyle: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'roboto-serif',
                    height: 1.55,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Worked solution',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Hidden until you choose to reveal it',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.tonalIcon(
                  key: const Key('reveal-solution-button'),
                  onPressed: onReveal,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Reveal worked solution'),
                ),
              ],
            ),
    );
  }
}

class AssignmentPanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const AssignmentPanelHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(
              icon,
              color: theme.colorScheme.onPrimaryContainer,
              size: 19,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AssignmentEditorToolbar extends StatelessWidget {
  final bool isRunning;
  final VoidCallback onRun;

  const AssignmentEditorToolbar({
    super.key,
    required this.isRunning,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(
              Icons.code_rounded,
              color: theme.colorScheme.onPrimaryContainer,
              size: 19,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Python editor',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Edit the starter code, then run the tests',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Semantics(
            label: isRunning
                ? 'Assignment tests are running'
                : 'Run assignment tests',
            button: true,
            enabled: !isRunning,
            child: Tooltip(
              message: 'Run assignment tests',
              child: FilledButton.icon(
                key: const Key('run-tests-button'),
                onPressed: isRunning ? null : onRun,
                icon: isRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(isRunning ? 'Running…' : 'Run tests'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AssignmentPageHeader extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final int assignmentId;
  final String status;
  final bool feedbackEnabled;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final ValueChanged<bool> onFeedbackChanged;

  const AssignmentPageHeader({
    super.key,
    required this.title,
    required this.assignmentId,
    required this.status,
    required this.feedbackEnabled,
    required this.onBack,
    required this.onHome,
    required this.onFeedbackChanged,
  });

  String get _displayTitle {
    final prefix = 'Assignment $assignmentId:';
    return title.startsWith(prefix)
        ? title.substring(prefix.length).trim()
        : title;
  }

  @override
  Size get preferredSize => const Size.fromHeight(76);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showFeedbackLabel = MediaQuery.sizeOf(context).width >= 600;

    return AppBar(
      toolbarHeight: preferredSize.height,
      automaticallyImplyLeading: false,
      backgroundColor: theme.colorScheme.primary,
      leadingWidth: 64,
      leading: IconButton(
        tooltip: 'Back to assignments',
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Text(
              assignmentId.toString().padLeft(2, '0'),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  status,
                  maxLines: 1,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.76),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (showFeedbackLabel)
          TextButton.icon(
            key: const Key('assignment-home-button'),
            onPressed: onHome,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onPrimary,
            ),
            icon: const Icon(Icons.home_rounded, size: 20),
            label: const Text('Home'),
          )
        else
          IconButton(
            key: const Key('assignment-home-button'),
            tooltip: 'Home',
            onPressed: onHome,
            icon: const Icon(Icons.home_rounded),
          ),
        const SizedBox(width: AppSpacing.xs),
        Semantics(
          label: 'Guided feedback',
          toggled: feedbackEnabled,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lightbulb_outline_rounded, size: 18),
              if (showFeedbackLabel) ...[
                const SizedBox(width: AppSpacing.sm),
                const Text('Guided feedback'),
              ],
              Switch(
                value: feedbackEnabled,
                onChanged: onFeedbackChanged,
                activeColor: theme.colorScheme.primary,
                activeTrackColor:
                    theme.colorScheme.onPrimary.withValues(alpha: 0.9),
                inactiveThumbColor:
                    theme.colorScheme.onPrimary.withValues(alpha: 0.7),
                inactiveTrackColor:
                    theme.colorScheme.onPrimary.withValues(alpha: 0.2),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
        ),
      ],
    );
  }
}

class AssignmentWorkspaceNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const AssignmentWorkspaceNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      key: const Key('assignment-workspace-navigation'),
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.code_rounded),
          label: 'Code',
        ),
        NavigationDestination(
          icon: Icon(Icons.menu_book_rounded),
          label: 'Instructions',
        ),
        NavigationDestination(
          icon: Icon(Icons.fact_check_rounded),
          label: 'Results',
        ),
      ],
    );
  }
}

class _EmptyResultsState extends StatelessWidget {
  const _EmptyResultsState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      label: 'No test results yet. Run assignment tests to see feedback.',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_circle_outline_rounded,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Ready when you are',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Run your code to see test results and feedback.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoFeedback extends StatelessWidget {
  const NoFeedback({super.key, required this.data});

  final UnittestFeedbackDto data;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TerminalOutput(data: data),
          if (data.hint.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _HintCallout(hint: data.hint),
          ],
        ],
      ),
    );
  }
}

class Feedback extends StatelessWidget {
  const Feedback({super.key, required this.data});

  final UnittestFeedbackDto data;

  @override
  Widget build(BuildContext context) {
    final passed = data.unittestPassResults.where((result) => result).length;
    final failed = data.unittestPassResults.length - passed;
    final total = passed + failed;
    final accuracy = total > 0 ? (passed / total) * 100 : 0.0;
    final vars = data.testedVals.map((value) => value.toString()).toList();

    final resultCards = data.unittestFeedback.asMap().entries.map((entry) {
      final feedback = entry.value;
      final didPass = entry.key < data.unittestPassResults.length &&
          data.unittestPassResults[entry.key];
      var first = feedback;
      var highlighted = '';
      var last = '';

      for (final value in vars) {
        if (feedback.contains(value)) {
          final index = feedback.indexOf(value);
          first = feedback.substring(0, index);
          highlighted = value;
          last = feedback.substring(index + value.length);
          break;
        }
      }

      return _TestResultCard(
        passed: didPass,
        first: first,
        highlighted: highlighted,
        last: last,
      );
    }).toList();

    return SingleChildScrollView(
      key: const Key('feedback-scroll-view'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ResultSummary(
            passed: passed,
            failed: failed,
            accuracy: accuracy,
          ),
          const SizedBox(height: AppSpacing.md),
          _TerminalOutput(data: data),
          if (data.hint.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _HintCallout(hint: data.hint),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Test details',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (resultCards.isEmpty)
            Text(
              'No individual test details were returned.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          else
            ...resultCards.expand(
              (card) => [card, const SizedBox(height: AppSpacing.sm)],
            ),
        ],
      ),
    );
  }
}

class LegacyFeedback extends StatelessWidget {
  const LegacyFeedback({super.key, required this.data});
  final UnittestFeedbackDto data;
  @override
  Widget build(BuildContext context) {
    int passed = 0, failed = 0;
    for (final result in data.unittestPassResults) {
      if (result) {
        passed++;
      } else {
        failed++;
      }
    }
    final total = passed + failed;
    final accuracy = total > 0 ? (passed / total) * 100 : 0.0;

    List<String> vars = data.testedVals.map((v) => v.toString()).toList();
    final feedbackLines = data.unittestFeedback.cast<String>();

    final feedbackWidgets = feedbackLines.asMap().entries.map((entry) {
      final e = entry.value;
      final check = entry.key < data.unittestPassResults.length &&
          data.unittestPassResults[entry.key];
      String first = e, second = "", third = "";
      for (var v in vars) {
        if (e.contains(v)) {
          final idx = e.indexOf(v);
          first = e.substring(0, idx);
          second = v;
          third = e.substring(idx + v.length);
          break;
        }
      }
      return Container(
        padding: const EdgeInsets.all(5),
        width: MediaQuery.of(context).size.width * 0.45,
        child: Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(5.0),
            child: Row(
              children: [
                Icon(check ? Icons.check : Icons.cancel,
                    color: check ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    softWrap: true,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: first,
                          style: TextStyle(
                            fontFamily: "Courier-New",
                            color: Theme.of(context)
                                .colorScheme
                                .onTertiaryContainer,
                          ),
                        ),
                        TextSpan(
                          text: second,
                          style: const TextStyle(
                            fontFamily: "Courier-New",
                            color: Colors.pink,
                          ),
                        ),
                        TextSpan(
                          text: third,
                          style: TextStyle(
                            fontFamily: "Courier-New",
                            color: Theme.of(context)
                                .colorScheme
                                .onTertiaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // summary row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 4),
                Text("Passed: $passed",
                    style: const TextStyle(color: Colors.green)),
                const SizedBox(width: 16),
                Icon(Icons.cancel, color: Colors.red),
                const SizedBox(width: 4),
                Text("Failed: $failed",
                    style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),

          // accuracy bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                "🎯 Accuracy: ${accuracy.toStringAsFixed(1)}%",
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey),
              ),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                duration: const Duration(seconds: 1),
                curve: Curves.easeOut,
                tween: Tween(begin: 0.0, end: accuracy / 100),
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  color: Colors.green,
                  backgroundColor: Colors.green.withValues(alpha: 0.3),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // terminal output / error
          data.execSuccess
              ? Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      "Terminal Output:",
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge!
                          .copyWith(fontFamily: "roboto-mono"),
                    ),
                  ),
                  Card(
                    color: const Color.fromARGB(100, 43, 74, 93),
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Text("> ${data.codeOutput}",
                          style: const TextStyle(
                              fontFamily: "Courier-New", fontSize: 12)),
                    ),
                  )
                ])
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text("There was an error running the code:"),
                  ),
                  Card(
                    color: Theme.of(context).colorScheme.secondary,
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Text("> ${data.codeExecResult}",
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSecondary,
                              fontFamily: "Courier-New",
                              fontSize: 12)),
                    ),
                  )
                ]),

          if (data.hint.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                  color: Colors.amber.shade100,
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        const Icon(Icons.lightbulb,
                            color: Colors.amber, size: 24),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text("AI Hint: ${data.hint}",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87))),
                      ]))),
            ),
          ],

          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text("Unittest Feedback",
                style: TextStyle(
                    fontFamily: "roboto-mono",
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
          Card(
            color: Theme.of(context).colorScheme.secondary,
            child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(children: feedbackWidgets)),
          ),
        ],
      ),
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({
    required this.passed,
    required this.failed,
    required this.accuracy,
  });

  final int passed;
  final int failed;
  final double accuracy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allPassed = failed == 0 && passed > 0;
    final statusColor = allPassed ? AppColors.success : theme.colorScheme.error;
    final statusBackground = allPassed
        ? AppColors.successContainer
        : theme.colorScheme.errorContainer;

    return Semantics(
      container: true,
      label:
          'Test score ${accuracy.toStringAsFixed(0)} percent. $passed passed and $failed failed.',
      child: Container(
        key: const Key('result-summary'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: statusBackground,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  allPassed
                      ? Icons.verified_rounded
                      : Icons.troubleshoot_rounded,
                  color: statusColor,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    allPassed
                        ? 'All tests passed'
                        : 'Keep refining your solution',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${accuracy.toStringAsFixed(0)}%',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            LinearProgressIndicator(
              value: accuracy / 100,
              color: statusColor,
              backgroundColor:
                  theme.colorScheme.surface.withValues(alpha: 0.72),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _ResultCount(
                  icon: Icons.check_rounded,
                  label: 'Passed: $passed',
                  color: AppColors.success,
                ),
                _ResultCount(
                  icon: Icons.close_rounded,
                  label: 'Failed: $failed',
                  color: theme.colorScheme.error,
                ),
                _ResultCount(
                  icon: Icons.analytics_outlined,
                  label: 'Accuracy: ${accuracy.toStringAsFixed(1)}%',
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCount extends StatelessWidget {
  const _ResultCount({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
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

class _TerminalOutput extends StatelessWidget {
  const _TerminalOutput({required this.data});

  final UnittestFeedbackDto data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final output = data.execSuccess ? data.codeOutput : data.codeExecResult;

    return Semantics(
      container: true,
      label: data.execSuccess ? 'Terminal output' : 'Code execution error',
      child: Container(
        key: const Key('terminal-output'),
        decoration: BoxDecoration(
          color: const Color(0xFF17242B),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    data.execSuccess
                        ? Icons.terminal_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: data.execSuccess
                        ? const Color(0xFF90D8B5)
                        : const Color(0xFFFFB4AB),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    data.execSuccess ? 'Terminal output' : 'Execution error',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.12)),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SelectableText(
                '> ${output.isEmpty ? 'No output returned.' : output}',
                style: const TextStyle(
                  color: Color(0xFFE3EDF2),
                  fontFamily: 'roboto-mono',
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintCallout extends StatelessWidget {
  const _HintCallout({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const Key('guided-hint'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5D9),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: const Color(0xFFE7C968)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            color: Colors.amber.shade900,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guided hint',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.brown.shade900,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  hint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.brown.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TestResultCard extends StatelessWidget {
  const _TestResultCard({
    required this.passed,
    required this.first,
    required this.highlighted,
    required this.last,
  });

  final bool passed;
  final String first;
  final String highlighted;
  final String last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = passed ? AppColors.success : theme.colorScheme.error;

    return Semantics(
      container: true,
      label: passed ? 'Test passed' : 'Test needs attention',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                passed ? Icons.check_rounded : Icons.close_rounded,
                size: 18,
                color: statusColor,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    passed ? 'Passed' : 'Needs attention',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  RichText(
                    softWrap: true,
                    text: TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontFamily: 'roboto-mono',
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(text: first),
                        TextSpan(
                          text: highlighted,
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(text: last),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EnableSwitch extends StatefulWidget {
  const EnableSwitch({required this.onChange});
  final Function onChange;
  @override
  State<EnableSwitch> createState() => _EnableSwitchState();
}

class _EnableSwitchState extends State<EnableSwitch> {
  bool light = true;
  @override
  Widget build(BuildContext context) {
    return Switch(
      value: light,
      activeColor: Colors.red,
      onChanged: (bool value) {
        setState(() => light = value);
        widget.onChange(value);
      },
    );
  }
}
