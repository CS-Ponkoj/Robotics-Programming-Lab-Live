import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/darcula.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/services/assignment_api.dart';
import 'package:iuse_demo/services/research_api.dart';
import 'package:iuse_demo/state/app_learning_progress.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:highlight/languages/python.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title, required this.id});
  final String title;
  final int id;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum AssignmentWorkspaceFocus { none, editor, instructions, results }

void setAssignmentEditorContent(
  CodeController controller,
  String content,
) {
  // CodeController keeps a separate full-code model; assigning inherited
  // TextEditingController.text can leave that model on the previous file.
  controller.fullText = content;
}

class _MyHomePageState extends State<MyHomePage> {
  late Future<AssignmentDto> _assignment;
  late Future<UnittestFeedbackDto> _feedback;
  late CodeController _controller;
  String _code = "";
  int? _assignmentVersion;
  bool _enableFeedback = false;
  bool _submitted = false;
  bool _isRunning = false;
  bool _init = true;
  String _submissionId = '';
  String _revealedSolutionHtml = '';
  String? _selectedProjectFilePath;
  bool _selectedProjectFileEditable = true;
  int _selectedWorkspaceTab = 0;
  double _editorWidthFraction = 0.5;
  AssignmentWorkspaceFocus _workspaceFocus = AssignmentWorkspaceFocus.none;
  Timer? _draftSaveTimer;

  @override
  void initState() {
    super.initState();
    _controller = CodeController(
      language: python,
      params: EditorParams(tabSpaces: 4),
    );
    _assignment = fetchAssignment(widget.id);
    unawaited(_trackAssignmentOpened());
    _feedback = fetchUnittestFeedback(widget.id, "");
    _submissionId = learningProgress.submissionIds[widget.id] ?? '';
    if (solutionRevealedAssignments.contains(widget.id) &&
        _submissionId.isNotEmpty) {
      unawaited(_loadPreviouslyRevealedSolution());
    }
  }

  Future<void> _trackAssignmentOpened() async {
    try {
      final assignment = await _assignment;
      researchTracker.setActiveAssignment(widget.id, assignment.version);
      await researchTracker.trackEvent(
        'assignment_opened',
        assignmentId: widget.id,
        assignmentVersion: assignment.version,
        eventData: const {'source': 'assignment_catalog'},
      );
    } on Object {
      // Research capture never changes assignment loading behavior.
    }
  }

  Future<void> _trackWorkspaceEvent(
    String eventType,
    Map<String, dynamic> eventData,
  ) async {
    try {
      final assignment = await _assignment;
      await researchTracker.trackEvent(
        eventType,
        assignmentId: widget.id,
        assignmentVersion: assignment.version,
        eventData: eventData,
      );
    } on Object {
      // Research capture never changes assignment interaction behavior.
    }
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    researchTracker.clearActiveAssignment(widget.id);
    if (!_init && _assignmentVersion != null) {
      unawaited(
        learningProgress.saveDraft(widget.id, _assignmentVersion!, _code),
      );
    }
    _controller.dispose();
    super.dispose();
  }

  void _saveDraft(String code) {
    _code = code;
    final assignmentVersion = _assignmentVersion;
    if (assignmentVersion == null) {
      return;
    }
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(
        learningProgress.saveDraft(widget.id, assignmentVersion, code),
      ),
    );
  }

  void _selectProjectFile(AssignmentProjectFile file) {
    if (_selectedProjectFileEditable) {
      _saveDraft(_controller.fullText);
    }
    setState(() {
      _selectedProjectFilePath = file.path;
      _selectedProjectFileEditable = file.editable;
      setAssignmentEditorContent(
        _controller,
        file.editable ? _code : file.content,
      );
    });
    unawaited(
      _trackWorkspaceEvent('workspace_file_selected', {
        'path': file.path,
        'editable': file.editable,
      }),
    );
  }

  void _runTests() {
    setState(() {
      _submitted = true;
      _isRunning = true;
      _feedback = fetchUnittestFeedback(
        widget.id,
        _code,
        useAiTutor: _enableFeedback,
      );
    });

    _feedback.then(
      (feedback) {
        final passed = feedback.unittestFeedback
            .asMap()
            .entries
            .where(
              (entry) =>
                  entry.key < feedback.unittestPassResults.length &&
                  feedback.unittestPassResults[entry.key],
            )
            .length;
        final total = feedback.unittestPassResults.length;

        if (!mounted) {
          return;
        }
        final score = total > 0 ? ((passed / total) * 100).round() : 0;
        setState(() {
          lastAttemptAccuracy[widget.id] = score;
          _submissionId = feedback.submissionId;
          _isRunning = false;
        });
        unawaited(
          learningProgress.recordSubmission(widget.id, feedback.submissionId),
        );
        unawaited(learningProgress.recordAttempt(widget.id, score));
      },
      onError: (_) {
        if (mounted) {
          setState(() => _isRunning = false);
        }
      },
    );
  }

  Future<void> _loadPreviouslyRevealedSolution() async {
    try {
      final html = await fetchWorkedSolution(widget.id, _submissionId);
      if (mounted) {
        setState(() => _revealedSolutionHtml = html);
      }
    } on Object {
      // The assignment may have advanced to a new version. The learner can
      // run that version once and explicitly reveal it again.
      solutionRevealedAssignments.remove(widget.id);
      await learningProgress.clearSolutionReveal(widget.id);
      if (mounted) {
        setState(() => _revealedSolutionHtml = '');
      }
    }
  }

  Future<void> _revealSolution() async {
    try {
      final html = await fetchWorkedSolution(widget.id, _submissionId);
      if (!mounted) {
        return;
      }
      setState(() {
        _revealedSolutionHtml = html;
        solutionRevealedAssignments.add(widget.id);
      });
      await learningProgress.recordSolutionReveal(widget.id);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _toggleWorkspaceFocus(AssignmentWorkspaceFocus target) {
    setState(() {
      _workspaceFocus =
          _workspaceFocus == target ? AssignmentWorkspaceFocus.none : target;
    });
  }

  void _resizeWorkspace(double horizontalDelta) {
    final workspaceWidth = MediaQuery.sizeOf(context).width;
    setState(() {
      _editorWidthFraction =
          (_editorWidthFraction + horizontalDelta / workspaceWidth).clamp(
        0.3,
        0.7,
      );
    });
  }

  void _showWorkspacePanel(
    AssignmentWorkspaceFocus target, {
    required bool useDesktopLayout,
  }) {
    setState(() {
      if (useDesktopLayout) {
        _workspaceFocus = target;
      } else {
        _selectedWorkspaceTab = switch (target) {
          AssignmentWorkspaceFocus.editor => 0,
          AssignmentWorkspaceFocus.instructions => 1,
          AssignmentWorkspaceFocus.results => 2,
          AssignmentWorkspaceFocus.none => _selectedWorkspaceTab,
        };
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final useDesktopLayout = MediaQuery.sizeOf(context).width >= 900;
    final showEditor = useDesktopLayout
        ? _workspaceFocus == AssignmentWorkspaceFocus.none ||
            _workspaceFocus == AssignmentWorkspaceFocus.editor
        : _selectedWorkspaceTab == 0;
    final showInstructions = useDesktopLayout
        ? _workspaceFocus == AssignmentWorkspaceFocus.none ||
            _workspaceFocus == AssignmentWorkspaceFocus.instructions
        : _selectedWorkspaceTab == 1;
    final showResults = useDesktopLayout
        ? _workspaceFocus == AssignmentWorkspaceFocus.none ||
            _workspaceFocus == AssignmentWorkspaceFocus.results
        : _selectedWorkspaceTab == 2;
    final showResizeHandle =
        useDesktopLayout && _workspaceFocus == AssignmentWorkspaceFocus.none;
    final progressState = learningProgress.assignmentState(widget.id);
    final submissionStatus = lastAttemptAccuracy.containsKey(widget.id)
        ? '${progressState.label} • Last score: ${lastAttemptAccuracy[widget.id]}%'
        : progressState.label;
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
        unawaited(_trackWorkspaceEvent('ai_tutor_toggled', {'enabled': value}));
      },
    );

    return Focus(
      autofocus: true,
      includeSemantics: false,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
            if (!_isRunning) {
              _runTests();
            }
          },
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
            if (!_isRunning) {
              _runTests();
            }
          },
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_workspaceFocus != AssignmentWorkspaceFocus.none) {
              setState(() => _workspaceFocus = AssignmentWorkspaceFocus.none);
            }
          },
          const SingleActivator(LogicalKeyboardKey.digit1, alt: true): () =>
              _showWorkspacePanel(
                AssignmentWorkspaceFocus.editor,
                useDesktopLayout: useDesktopLayout,
              ),
          const SingleActivator(LogicalKeyboardKey.digit2, alt: true): () =>
              _showWorkspacePanel(
                AssignmentWorkspaceFocus.instructions,
                useDesktopLayout: useDesktopLayout,
              ),
          const SingleActivator(LogicalKeyboardKey.digit3, alt: true): () =>
              _showWorkspacePanel(
                AssignmentWorkspaceFocus.results,
                useDesktopLayout: useDesktopLayout,
              ),
        },
        child: FocusTraversalGroup(
          child: Scaffold(
            appBar: appBar,
            body: Column(
              children: [
                if (!useDesktopLayout)
                  AssignmentWorkspaceNavigation(
                    selectedIndex: _selectedWorkspaceTab,
                    onDestinationSelected: (index) {
                      setState(() => _selectedWorkspaceTab = index);
                      unawaited(
                        _trackWorkspaceEvent('workspace_tab_changed', {
                          'tab_index': index,
                        }),
                      );
                    },
                  ),
                Expanded(
                  child: Row(
                    children: [
                      // ─── Left: code editor ─────────────────────────
                      if (showEditor)
                        Expanded(
                          flex: showResizeHandle
                              ? (_editorWidthFraction * 1000).round()
                              : 1,
                          child: Container(
                            key: const Key('assignment-editor-panel'),
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryFixedDim,
                            child: Column(
                              children: [
                                AssignmentEditorToolbar(
                                  isRunning: _isRunning,
                                  onRun: _runTests,
                                  isFocused: _workspaceFocus ==
                                      AssignmentWorkspaceFocus.editor,
                                  onFocusToggle: useDesktopLayout
                                      ? () => _toggleWorkspaceFocus(
                                            AssignmentWorkspaceFocus.editor,
                                          )
                                      : null,
                                ),
                                Expanded(
                                  child: FutureBuilder<AssignmentDto>(
                                    future: _assignment,
                                    builder: (ctx, snap) {
                                      if (snap.hasData) {
                                        if (_init) {
                                          _assignmentVersion =
                                              snap.data!.version;
                                          _code = learningProgress.draftFor(
                                                widget.id,
                                                snap.data!.version,
                                              ) ??
                                              snap.data!.code;
                                          _selectedProjectFilePath =
                                              snap.data!.editableFilePath;
                                          _selectedProjectFileEditable = true;
                                          setAssignmentEditorContent(
                                            _controller,
                                            _code,
                                          );
                                          _init = false;
                                        }
                                        return AssignmentProjectWorkspace(
                                          files: snap.data!.projectFiles,
                                          selectedPath:
                                              _selectedProjectFilePath,
                                          selectedFileEditable:
                                              _selectedProjectFileEditable,
                                          controller: _controller,
                                          onFileSelected: _selectProjectFile,
                                          onChanged: () {
                                            if (_selectedProjectFileEditable) {
                                              _saveDraft(_controller.fullText);
                                            }
                                          },
                                        );
                                      }
                                      if (snap.hasError) {
                                        return const Center(
                                          child: Text("Error"),
                                        );
                                      }
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // ─── Right: scenario + feedback ────────────────
                      if (showResizeHandle)
                        WorkspaceResizeHandle(
                          editorFraction: _editorWidthFraction,
                          onDragUpdate: _resizeWorkspace,
                        ),
                      if (showInstructions || showResults)
                        Expanded(
                          flex: showResizeHandle
                              ? ((1 - _editorWidthFraction) * 1000).round()
                              : 1,
                          child: Column(
                            children: [
                              // scenario half
                              if (showInstructions)
                                Expanded(
                                  flex: 1,
                                  child: Column(
                                    children: [
                                      AssignmentPanelHeader(
                                        icon: Icons.menu_book_rounded,
                                        title: 'Instructions',
                                        subtitle:
                                            'Review the scenario and task',
                                        isFocused: _workspaceFocus ==
                                            AssignmentWorkspaceFocus
                                                .instructions,
                                        onFocusToggle: useDesktopLayout
                                            ? () => _toggleWorkspaceFocus(
                                                  AssignmentWorkspaceFocus
                                                      .instructions,
                                                )
                                            : null,
                                      ),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          key: const Key(
                                            'assignment-instructions-panel',
                                          ),
                                          padding: const EdgeInsets.all(
                                            AppSpacing.md,
                                          ),
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
                                                  solutionHtml:
                                                      _revealedSolutionHtml
                                                              .isNotEmpty
                                                          ? _revealedSolutionHtml
                                                          : snap.data!
                                                              .solutionHtml,
                                                  hasSolution:
                                                      snap.data!.hasSolution,
                                                  solutionRevealed:
                                                      solutionRevealedAssignments
                                                          .contains(widget.id),
                                                  canRevealSolution:
                                                      learningProgress
                                                          .hasAttempted(
                                                    widget.id,
                                                  ),
                                                  onSolutionRevealed: () =>
                                                      unawaited(
                                                    _revealSolution(),
                                                  ),
                                                );
                                              }
                                              if (snap.hasError) {
                                                return const Text(
                                                  "Error loading scenario",
                                                );
                                              }
                                              return const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              // feedback half
                              if (showResults)
                                Expanded(
                                  flex: 1,
                                  child: Column(
                                    key: const Key('assignment-results-panel'),
                                    children: [
                                      AssignmentPanelHeader(
                                        icon: Icons.fact_check_rounded,
                                        title: 'Results',
                                        subtitle:
                                            'Review test outcomes and feedback',
                                        isFocused: _workspaceFocus ==
                                            AssignmentWorkspaceFocus.results,
                                        onFocusToggle: useDesktopLayout
                                            ? () => _toggleWorkspaceFocus(
                                                  AssignmentWorkspaceFocus
                                                      .results,
                                                )
                                            : null,
                                      ),
                                      Expanded(
                                        child: _submitted
                                            ? FutureBuilder<
                                                UnittestFeedbackDto>(
                                                future: _feedback,
                                                builder: (ctx, snap) {
                                                  if (snap.connectionState ==
                                                      ConnectionState.waiting) {
                                                    return const SecureGraderLoadingState();
                                                  }
                                                  if (snap.hasError) {
                                                    return TestRunErrorState(
                                                      onRetry: _runTests,
                                                    );
                                                  }
                                                  if (snap.hasData) {
                                                    return Feedback(
                                                      data: snap.data!,
                                                      aiTutorEnabled:
                                                          _enableFeedback,
                                                    );
                                                  }
                                                  return const SizedBox
                                                      .shrink();
                                                },
                                              )
                                            : const _EmptyResultsState(),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AssignmentInstructions extends StatelessWidget {
  const AssignmentInstructions({
    super.key,
    required this.html,
    this.assignmentId = 1,
    this.solutionHtml = '',
    this.hasSolution = false,
    this.solutionRevealed = false,
    this.canRevealSolution = true,
    this.onSolutionRevealed,
  });

  final String html;
  final int assignmentId;
  final String solutionHtml;
  final bool hasSolution;
  final bool solutionRevealed;
  final bool canRevealSolution;
  final VoidCallback? onSolutionRevealed;

  @override
  Widget build(BuildContext context) {
    final sections = AssignmentInstructionSections.fromHtml(html);
    final displayedSolutionHtml =
        solutionHtml.isNotEmpty ? solutionHtml : sections.solution;

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
        if (hasSolution || displayedSolutionHtml.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _SolutionSection(
            html: displayedSolutionHtml,
            revealed: solutionRevealed,
            canReveal: canRevealSolution,
            onReveal: onSolutionRevealed,
          ),
        ],
      ],
    );
  }
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
        buffers[destination]!.write(
          '<p><strong>${match.group(1)}</strong></p>',
        );
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
    required this.canReveal,
    this.onReveal,
  });

  final String html;
  final bool revealed;
  final bool canReveal;
  final VoidCallback? onReveal;

  Future<void> _requestReveal(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.visibility_outlined),
        title: const Text('Reveal worked solution?'),
        content: const Text(
          'The full answer will be shown and this assignment will be marked '
          'as Solution viewed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            key: const Key('confirm-solution-reveal-button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reveal solution'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onReveal?.call();
    }
  }

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
                            canReveal
                                ? 'Hidden until you choose to reveal it'
                                : 'Run the tests once to unlock the solution',
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
                  onPressed: canReveal ? () => _requestReveal(context) : null,
                  icon: Icon(
                    canReveal ? Icons.visibility_outlined : Icons.lock_outline,
                  ),
                  label: Text(
                    canReveal
                        ? 'Reveal worked solution'
                        : 'Complete one test run first',
                  ),
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
  final bool isFocused;
  final VoidCallback? onFocusToggle;

  const AssignmentPanelHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.isFocused = false,
    this.onFocusToggle,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          if (onFocusToggle != null)
            IconButton(
              key: Key('focus-${title.toLowerCase()}-button'),
              tooltip: isFocused ? 'Restore workspace' : 'Focus $title',
              onPressed: onFocusToggle,
              icon: Icon(
                isFocused
                    ? Icons.close_fullscreen_rounded
                    : Icons.open_in_full_rounded,
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
  final bool isFocused;
  final VoidCallback? onFocusToggle;

  const AssignmentEditorToolbar({
    super.key,
    required this.isRunning,
    required this.onRun,
    this.isFocused = false,
    this.onFocusToggle,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          if (onFocusToggle != null) ...[
            IconButton(
              key: const Key('focus-editor-button'),
              tooltip: isFocused ? 'Restore workspace' : 'Focus code editor',
              onPressed: onFocusToggle,
              icon: Icon(
                isFocused
                    ? Icons.close_fullscreen_rounded
                    : Icons.open_in_full_rounded,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          const SizedBox(width: AppSpacing.md),
          Semantics(
            label: isRunning
                ? 'Assignment tests are running'
                : 'Run assignment tests. Keyboard shortcut Control Enter',
            button: true,
            enabled: !isRunning,
            child: Tooltip(
              message: 'Run assignment tests (Ctrl+Enter)',
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

class AssignmentProjectWorkspace extends StatelessWidget {
  const AssignmentProjectWorkspace({
    super.key,
    required this.files,
    required this.selectedPath,
    required this.selectedFileEditable,
    required this.controller,
    required this.onFileSelected,
    required this.onChanged,
  });

  final List<AssignmentProjectFile> files;
  final String? selectedPath;
  final bool selectedFileEditable;
  final CodeController controller;
  final ValueChanged<AssignmentProjectFile> onFileSelected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final editor = Column(
      children: [
        if (files.isNotEmpty)
          ProjectFileStatusBar(
            path: selectedPath ?? files.first.path,
            editable: selectedFileEditable,
          ),
        Expanded(
          child: Semantics(
            label: selectedFileEditable
                ? 'Editable Python code file'
                : 'Read-only project file',
            textField: true,
            readOnly: !selectedFileEditable,
            child: CodeTheme(
              data: CodeThemeData(styles: darculaTheme),
              child: CodeField(
                key: const Key('assignment-code-field'),
                controller: controller,
                expands: true,
                minLines: null,
                readOnly: !selectedFileEditable,
                onChanged: (_) => onChanged(),
              ),
            ),
          ),
        ),
      ],
    );
    if (files.isEmpty) {
      return editor;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final explorer = AssignmentProjectExplorer(
          files: files,
          selectedPath: selectedPath,
          onFileSelected: onFileSelected,
        );
        if (constraints.maxWidth < 620) {
          return Column(
            children: [
              SizedBox(height: 180, child: explorer),
              Expanded(child: editor),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 250, child: explorer),
            VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(child: editor),
          ],
        );
      },
    );
  }
}

class AssignmentProjectExplorer extends StatelessWidget {
  const AssignmentProjectExplorer({
    super.key,
    required this.files,
    required this.selectedPath,
    required this.onFileSelected,
  });

  final List<AssignmentProjectFile> files;
  final String? selectedPath;
  final ValueChanged<AssignmentProjectFile> onFileSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'PROJECT FILES',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const Key('assignment-project-file-tree'),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                final selected = file.path == selectedPath;
                final segments = file.path.split('/');
                final name = segments.last;
                final depth = (segments.length - 1).clamp(0, 4);
                return Semantics(
                  label:
                      '${file.path}, ${file.editable ? 'editable' : 'read only'}',
                  button: true,
                  selected: selected,
                  child: Padding(
                    padding: EdgeInsets.only(left: depth * 8.0),
                    child: ListTile(
                      key: Key('project-file-${file.path}'),
                      dense: true,
                      selected: selected,
                      selectedTileColor: theme.colorScheme.primaryContainer,
                      leading: Icon(
                        _fileIcon(name),
                        size: 18,
                        color: selected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: selected ? FontWeight.w700 : null,
                        ),
                      ),
                      trailing: Icon(
                        file.editable
                            ? Icons.edit_outlined
                            : Icons.lock_outline,
                        size: 16,
                        color: file.editable
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      onTap: () => onFileSelected(file),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static IconData _fileIcon(String name) {
    if (name.endsWith('.py')) {
      return Icons.code_rounded;
    }
    if (name.endsWith('.xml')) {
      return Icons.data_object_rounded;
    }
    if (name.endsWith('.cfg')) {
      return Icons.tune_rounded;
    }
    return Icons.insert_drive_file_outlined;
  }
}

class ProjectFileStatusBar extends StatelessWidget {
  const ProjectFileStatusBar({
    super.key,
    required this.path,
    required this.editable,
  });

  final String path;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('project-file-status-bar'),
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(editable ? Icons.edit_outlined : Icons.lock_outline, size: 15),
          const SizedBox(width: AppSpacing.xs),
          Text(
            editable ? 'Editable' : 'Read only',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class WorkspaceResizeHandle extends StatelessWidget {
  const WorkspaceResizeHandle({
    super.key,
    required this.editorFraction,
    required this.onDragUpdate,
  });

  final double editorFraction;
  final ValueChanged<double> onDragUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Resize code editor',
      value: '${(editorFraction * 100).round()} percent',
      increasedValue:
          '${((editorFraction + 0.05).clamp(0.3, 0.7) * 100).round()} percent',
      decreasedValue:
          '${((editorFraction - 0.05).clamp(0.3, 0.7) * 100).round()} percent',
      onIncrease: () => onDragUpdate(50),
      onDecrease: () => onDragUpdate(-50),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          key: const Key('workspace-resize-handle'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => onDragUpdate(details.delta.dx),
          child: Container(
            width: 12,
            color: theme.colorScheme.surface,
            alignment: Alignment.center,
            child: Container(
              width: 2,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
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
          label: 'AI tutoring',
          toggled: feedbackEnabled,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lightbulb_outline_rounded, size: 18),
              if (showFeedbackLabel) ...[
                const SizedBox(width: AppSpacing.sm),
                const Text('AI tutoring'),
              ],
              Switch(
                value: feedbackEnabled,
                onChanged: onFeedbackChanged,
                activeColor: theme.colorScheme.primary,
                activeTrackColor: theme.colorScheme.onPrimary.withValues(
                  alpha: 0.9,
                ),
                inactiveThumbColor: theme.colorScheme.onPrimary.withValues(
                  alpha: 0.7,
                ),
                inactiveTrackColor: theme.colorScheme.onPrimary.withValues(
                  alpha: 0.2,
                ),
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
        NavigationDestination(icon: Icon(Icons.code_rounded), label: 'Code'),
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

class TestRunErrorState extends StatelessWidget {
  const TestRunErrorState({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      key: const Key('test-run-error-state'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Grading service unavailable',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Your code was not graded. Confirm that the backend is running '
                'at $apiBaseUrl, then try again.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                key: const Key('retry-test-run-button'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry test run'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SecureGraderLoadingState extends StatelessWidget {
  const SecureGraderLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('secure-grader-loading-state'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Starting secure grader…',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'The first run can take up to one minute on the free hosting tier.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef TutorQuestionRequester = Future<Map<String, dynamic>> Function(
  int assignmentId,
  String submissionId,
  String question,
  int hintLevel,
);

class Feedback extends StatelessWidget {
  const Feedback({
    super.key,
    required this.data,
    this.aiTutorEnabled = false,
    this.tutorQuestionRequester,
  });

  final UnittestFeedbackDto data;
  final bool aiTutorEnabled;
  final TutorQuestionRequester? tutorQuestionRequester;

  @override
  Widget build(BuildContext context) {
    final passed = data.unittestPassResults.where((result) => result).length;
    final failed = data.unittestPassResults.length - passed;
    final total = passed + failed;
    final accuracy = total > 0 ? (passed / total) * 100 : 0.0;
    final vars = data.testedVals.map((value) => value.toString()).toList();
    final tutorAvailable = aiTutorEnabled || data.tutorFeedback.isNotEmpty;

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
          _ResultSummary(passed: passed, failed: failed, accuracy: accuracy),
          const SizedBox(height: AppSpacing.md),
          _TerminalOutput(data: data),
          if (data.hint.isNotEmpty ||
              (tutorAvailable && data.submissionId.isNotEmpty)) ...[
            const SizedBox(height: AppSpacing.md),
            _TutorHintPanel(
              data: data,
              allowQuestions: tutorAvailable,
              questionRequester: tutorQuestionRequester ?? askTutorQuestion,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Test details',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
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
                Icon(
                  check ? Icons.check : Icons.cancel,
                  color: check ? Colors.green : Colors.red,
                ),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onTertiaryContainer,
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onTertiaryContainer,
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
                Text(
                  "Passed: $passed",
                  style: const TextStyle(color: Colors.green),
                ),
                const SizedBox(width: 16),
                Icon(Icons.cancel, color: Colors.red),
                const SizedBox(width: 4),
                Text(
                  "Failed: $failed",
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ),
          ),

          // accuracy bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "🎯 Accuracy: ${accuracy.toStringAsFixed(1)}%",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
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
              ],
            ),
          ),
          const SizedBox(height: 12),

          // terminal output / error
          data.execSuccess
              ? Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        "Terminal Output:",
                        style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                              fontFamily: "roboto-mono",
                            ),
                      ),
                    ),
                    Card(
                      color: const Color.fromARGB(100, 43, 74, 93),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Text(
                          "> ${data.codeOutput}",
                          style: const TextStyle(
                            fontFamily: "Courier-New",
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text("There was an error running the code:"),
                    ),
                    Card(
                      color: Theme.of(context).colorScheme.secondary,
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Text(
                          "> ${data.codeExecResult}",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSecondary,
                            fontFamily: "Courier-New",
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

          if (data.hint.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                color: Colors.amber.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lightbulb,
                        color: Colors.amber,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "AI Hint: ${data.hint}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              "Unittest Feedback",
              style: TextStyle(
                fontFamily: "roboto-mono",
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Card(
            color: Theme.of(context).colorScheme.secondary,
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(children: feedbackWidgets),
            ),
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
              backgroundColor: theme.colorScheme.surface.withValues(
                alpha: 0.72,
              ),
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
  const _HintCallout({required this.hint, required this.source});

  final String hint;
  final String source;

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
          Icon(Icons.lightbulb_outline_rounded, color: Colors.amber.shade900),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source == 'openai'
                      ? 'OpenAI tutor hint'
                      : source == 'fallback'
                          ? 'Built-in tutor hint'
                          : 'Guided hint',
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

class _TutorHintPanel extends StatefulWidget {
  const _TutorHintPanel({
    required this.data,
    required this.allowQuestions,
    required this.questionRequester,
  });

  final UnittestFeedbackDto data;
  final bool allowQuestions;
  final TutorQuestionRequester questionRequester;

  @override
  State<_TutorHintPanel> createState() => _TutorHintPanelState();
}

class _TutorHintPanelState extends State<_TutorHintPanel> {
  final TextEditingController _questionController = TextEditingController();
  final FocusNode _questionFocus = FocusNode();
  late String _hint;
  late String _source;
  int _hintLevel = 1;
  bool _loading = false;
  bool _asking = false;
  Map<String, dynamic>? _answer;
  String? _error;
  String? _questionError;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant _TutorHintPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.submissionId != widget.data.submissionId) {
      _reset();
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    _questionFocus.dispose();
    super.dispose();
  }

  void _reset() {
    _hint = widget.data.hint;
    _source = widget.data.tutorSource;
    _hintLevel = 1;
    _loading = false;
    _asking = false;
    _answer = widget.data.tutorFeedback.isEmpty
        ? null
        : Map<String, dynamic>.from(widget.data.tutorFeedback);
    _error = null;
    _questionError = null;
    _questionController.clear();
  }

  Future<void> _askQuestion() async {
    if (_asking || widget.data.submissionId.isEmpty) {
      return;
    }
    final question = _questionController.text.trim();
    if (question.length < 3) {
      setState(() {
        _questionError = 'Enter a question with at least 3 characters.';
      });
      _questionFocus.requestFocus();
      return;
    }
    setState(() {
      _asking = true;
      _questionError = null;
    });
    try {
      final response = await widget.questionRequester(
        widget.data.id,
        widget.data.submissionId,
        question,
        _hintLevel,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _answer = response;
        _asking = false;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _asking = false;
          _questionError =
              'The tutor is temporarily unavailable. Your question was kept; try again.';
        });
      }
    }
  }

  Future<void> _requestNextHint() async {
    if (_loading || _hintLevel >= 4 || widget.data.submissionId.isEmpty) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final feedback = await fetchProgressiveHint(
        widget.data.id,
        widget.data.submissionId,
        _hintLevel + 1,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _hint = feedback['hint']?.toString() ?? _hint;
        _source = feedback['source']?.toString() ?? 'fallback';
        _hintLevel = feedback['hint_level'] is int
            ? feedback['hint_level'] as int
            : _hintLevel + 1;
        _loading = false;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'The next hint is temporarily unavailable. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hint.isNotEmpty) ...[
          _HintCallout(hint: _hint, source: _source),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (_hint.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              Text(
                'Hint level $_hintLevel of 4',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              FilledButton.tonalIcon(
                key: const Key('next-hint-button'),
                onPressed:
                    _loading || _hintLevel >= 4 ? null : _requestNextHint,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(
                  _hintLevel >= 4
                      ? 'Maximum guidance reached'
                      : 'Get another hint',
                ),
              ),
            ],
          ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (widget.allowQuestions) ...[
          if (_hint.isNotEmpty) const SizedBox(height: AppSpacing.md),
          Text(
            'Ask the tutor',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Ask about your latest attempt. The tutor explains and guides, but does not provide completed code.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('tutor-question-field'),
            controller: _questionController,
            focusNode: _questionFocus,
            enabled: !_asking,
            minLines: 1,
            maxLines: 3,
            maxLength: 500,
            textInputAction: TextInputAction.newline,
            onChanged: (_) {
              if (_questionError != null) {
                setState(() => _questionError = null);
              }
            },
            decoration: const InputDecoration(
              labelText: 'Your question',
              hintText: 'For example: Why is my first calculation failing?',
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('ask-tutor-button'),
              onPressed: _asking ? null : _askQuestion,
              icon: _asking
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.question_answer_outlined, size: 18),
              label: Text(_asking ? 'Asking tutor…' : 'Ask tutor'),
            ),
          ),
          if (_questionError != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              liveRegion: true,
              child: Text(
                _questionError!,
                key: const Key('tutor-question-error'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
          if (_answer != null) ...[
            const SizedBox(height: AppSpacing.md),
            _TutorAnswerCard(data: _answer!),
          ],
        ],
      ],
    );
  }
}

class _TutorAnswerCard extends StatelessWidget {
  const _TutorAnswerCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final source = data['source']?.toString() ?? 'fallback';
    final answer = data['answer']?.toString() ?? '';
    final diagnosis = data['diagnosis']?.toString() ?? '';
    final guidingQuestion = data['guiding_question']?.toString() ?? '';
    final nextAction = data['next_action']?.toString() ?? '';
    final debuggingSteps =
        (data['debugging_steps'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList();

    return Semantics(
      container: true,
      liveRegion: true,
      label: source == 'openai'
          ? 'OpenAI tutor response'
          : 'Built-in tutor response',
      child: Card(
        key: const Key('tutor-answer-card'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source == 'openai'
                    ? 'OpenAI tutor response'
                    : 'Built-in tutor response',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (answer.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(answer),
              ],
              if (diagnosis.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('What to inspect: $diagnosis'),
              ],
              if (debuggingSteps.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Debugging steps',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                ...debuggingSteps.asMap().entries.map(
                      (entry) => Text('${entry.key + 1}. ${entry.value}'),
                    ),
              ],
              if (guidingQuestion.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('Think about: $guidingQuestion'),
              ],
              if (nextAction.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('Next action: $nextAction'),
              ],
            ],
          ),
        ),
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
