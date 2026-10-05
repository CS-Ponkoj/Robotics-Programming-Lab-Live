import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:iuse_demo/editor/indent_guides.dart';
import 'package:iuse_demo/editor/editor_tools.dart';
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/services/assignment_api.dart';
import 'package:iuse_demo/services/research_api.dart';
import 'package:iuse_demo/state/app_learning_progress.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/theme/editor_palette.dart';
import 'package:iuse_demo/widgets/playground_dialog.dart';
import 'package:highlight/languages/python.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title, required this.id});
  final String title;
  final int id;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum AssignmentWorkspaceFocus { none, editor, instructions, results }

enum DraftSaveState { idle, saving, saved, sessionSaved, failed }

void setAssignmentEditorContent(
  CodeController controller,
  String content,
) {
  // CodeController keeps a separate full-code model; assigning inherited
  // TextEditingController.text can leave that model on the previous file.
  controller.fullText = content;
}

int editorIndentLevel(String line) {
  return indentationDepth(line);
}

bool hasNonWhitespaceCode(String code) => code.trim().isNotEmpty;

class _MyHomePageState extends State<MyHomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late Future<AssignmentDto> _assignment;
  late Future<UnittestFeedbackDto> _feedback;
  late CodeController _controller;
  late FocusNode _editorFocusNode;
  String _code = "";
  String? _serverDraft;
  int? _assignmentVersion;
  bool _enableFeedback = false;
  bool _submitted = false;
  bool _emptyCodeAttempted = false;
  bool _isRunning = false;
  bool _hasUnrunChanges = false;
  bool _init = true;
  String _submissionId = '';
  String _revealedSolutionHtml = '';
  String? _selectedProjectFilePath;
  bool _selectedProjectFileEditable = true;
  int _selectedWorkspaceTab = 0;
  double _editorWidthFraction = 0.5;
  AssignmentWorkspaceFocus _workspaceFocus = AssignmentWorkspaceFocus.none;
  Timer? _draftSaveTimer;
  Future<void> _draftWriteQueue = Future<void>.value();
  DraftSaveState _draftSaveState = DraftSaveState.idle;
  double _editorFontSize = 16;
  bool _editorDarkMode = true;
  int? _diagnosticLine;
  bool _suppressEditorChange = false;
  String? _playgroundFunction;
  Map<String, dynamic> _simulationConfig = const {};
  // Kept in memory only so reopening the playground restores the last inputs.
  String _playgroundArguments = '';

  @override
  void initState() {
    super.initState();
    _controller = CodeController(
      language: python,
      params: EditorParams(tabSpaces: 4),
    );
    _editorFocusNode = FocusNode(debugLabel: 'assignment-code-editor');
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _assignment = _loadAssignment();
    unawaited(_trackAssignmentOpened());
    _feedback = fetchUnittestFeedback(widget.id, "");
    _submissionId = learningProgress.submissionIds[widget.id] ?? '';
    if (solutionRevealedAssignments.contains(widget.id) &&
        _submissionId.isNotEmpty) {
      unawaited(_loadPreviouslyRevealedSolution());
    }
  }

  Future<AssignmentDto> _loadAssignment() async {
    final assignment = await fetchAssignment(widget.id);
    _controller.autocompleter.setCustomWords(
      assignmentCompletionWords(assignment),
    );
    try {
      final draft = await fetchCodeDraft(widget.id);
      if (draft.assignmentVersion == assignment.version && draft.saved) {
        _serverDraft = draft.code;
        _draftSaveState = DraftSaveState.saved;
      }
    } on Object {
      // Local drafts remain a reliable fallback while the API is unavailable.
    }
    return assignment;
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
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    researchTracker.clearActiveAssignment(widget.id);
    if (!_init && _assignmentVersion != null) {
      unawaited(_persistDraft(_code));
    }
    _editorFocusNode.dispose();
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
    // Keep the newest code on this device at once, so logout or a lost
    // connection cannot drop it; the server copy follows after a short pause.
    unawaited(learningProgress.saveDraft(widget.id, assignmentVersion, code));
    unawaited(learningProgress.setDraftSynced(widget.id, false));
    if (mounted) {
      setState(() => _draftSaveState = DraftSaveState.saving);
    }
    _draftSaveTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_persistDraft(code)),
    );
  }

  Future<DraftSaveState> _persistDraft(String code) async {
    final assignmentVersion = _assignmentVersion;
    if (assignmentVersion == null) {
      return DraftSaveState.failed;
    }
    final precedingWrite = _draftWriteQueue;
    final writeFinished = Completer<void>();
    _draftWriteQueue = writeFinished.future;
    await precedingWrite;
    try {
      await learningProgress.saveDraft(widget.id, assignmentVersion, code);
      final result = await saveCodeDraft(widget.id, assignmentVersion, code);
      if (code == _code) {
        await learningProgress.setDraftSynced(widget.id, true);
      }
      final savedState =
          result.saved ? DraftSaveState.saved : DraftSaveState.sessionSaved;
      if (mounted && code == _code) {
        setState(() => _draftSaveState = savedState);
      }
      return savedState;
    } on Object {
      if (mounted && code == _code) {
        setState(() => _draftSaveState = DraftSaveState.failed);
      }
      return DraftSaveState.failed;
    } finally {
      writeFinished.complete();
    }
  }

  Future<void> _saveDraftNow() async {
    if (_init || _assignmentVersion == null || !_selectedProjectFileEditable) {
      return;
    }
    _draftSaveTimer?.cancel();
    final code = _controller.fullText;
    _code = code;
    setState(() => _draftSaveState = DraftSaveState.saving);
    final saveResult = await _persistDraft(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (saveResult) {
          DraftSaveState.saved => 'Draft saved.',
          DraftSaveState.sessionSaved =>
            'Draft saved for this session. It resets on refresh.',
          _ => 'Cloud save failed. Check your connection and try Ctrl+S again.',
        }),
      ),
    );
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (isEditorSaveShortcut(
      event,
      editorHasFocus: _editorFocusNode.hasFocus,
      editable: _selectedProjectFileEditable,
    )) {
      unawaited(_saveDraftNow());
      return true;
    }
    final handled = handleEditorKeyEvent(
      event,
      _controller,
      editorHasFocus: _editorFocusNode.hasFocus,
      editable: _selectedProjectFileEditable,
    );
    if (handled) {
      _handleEditableCodeChanged();
    }
    return handled;
  }

  void _handleEditableCodeChanged() {
    if (_suppressEditorChange) {
      return;
    }
    final updatedCode = _controller.fullText;
    if (updatedCode != _code &&
        (_submitted || !_hasUnrunChanges || _emptyCodeAttempted)) {
      setState(() {
        _submitted = false;
        _emptyCodeAttempted = false;
        _hasUnrunChanges = true;
        _diagnosticLine = null;
      });
    }
    _saveDraft(updatedCode);
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
    // Until the assignment loads, _code is not the code shown in the editor;
    // running now would wrongly report an empty editor.
    if (_init) return;
    if (!hasNonWhitespaceCode(_code)) {
      setState(() {
        _submitted = false;
        _emptyCodeAttempted = true;
        _diagnosticLine = null;
      });
      _openResultsPanel();
      return;
    }
    setState(() {
      _submitted = true;
      _emptyCodeAttempted = false;
      _isRunning = true;
      _hasUnrunChanges = false;
      _diagnosticLine = null;
      _feedback = fetchUnittestFeedback(
        widget.id,
        _code,
        useAiTutor: _enableFeedback,
      );
    });
    _openResultsPanel();

    _feedback.then(
      (feedback) {
        if (!mounted) {
          return;
        }
        final score = feedback.score.clamp(0, 100).toInt();
        setState(() {
          lastAttemptAccuracy[widget.id] = score;
          _submissionId = feedback.submissionId;
          _isRunning = false;
          _diagnosticLine = extractPythonErrorLine(
            '${feedback.codeExecResult}\n${feedback.codeOutput}',
            _controller.fullText.split('\n').length,
          );
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

  Future<void> _openPlayground() async {
    final functionName = _playgroundFunction;
    if (_init || functionName == null) return;
    if (!hasNonWhitespaceCode(_code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write some code before trying inputs.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => PlaygroundDialog(
        assignmentId: widget.id,
        functionName: functionName,
        code: _code,
        initialArguments: _playgroundArguments,
        onArgumentsChanged: (value) => _playgroundArguments = value,
        simulationConfig: _simulationConfig,
      ),
    );
  }

  Future<void> _formatCode() async {
    if (!_selectedProjectFileEditable || _isRunning) {
      return;
    }
    try {
      final result =
          await formatAssignmentCode(widget.id, _controller.fullText);
      if (!mounted) return;
      if (!result.changed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('The Python code is already formatted.')),
        );
        return;
      }
      _suppressEditorChange = true;
      setAssignmentEditorContent(_controller, result.code);
      _suppressEditorChange = false;
      setState(() {
        _submitted = false;
        _hasUnrunChanges = true;
        _diagnosticLine = null;
      });
      _saveDraft(result.code);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Python formatting applied.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _resetStarterCode() async {
    if (_init || !_selectedProjectFileEditable || _isRunning) return;
    final assignment = await _assignment;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Restore starter code?'),
            content: const Text(
              'This replaces the current draft for this assignment version.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Restore'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    _draftSaveTimer?.cancel();
    try {
      await deleteCodeDraft(widget.id, assignment.version);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return;
    }
    await learningProgress.clearDraft(widget.id);
    _suppressEditorChange = true;
    setAssignmentEditorContent(_controller, assignment.code);
    _suppressEditorChange = false;
    setState(() {
      _code = assignment.code;
      _submitted = false;
      _emptyCodeAttempted = false;
      _hasUnrunChanges = false;
      _diagnosticLine = null;
      _draftSaveState = DraftSaveState.idle;
    });
  }

  Future<void> _showReplaceDialog() async {
    var query = '';
    var replacement = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Replace text'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('replace-find-field'),
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Find'),
                onChanged: (value) => query = value,
              ),
              TextField(
                key: const Key('replace-with-field'),
                decoration: const InputDecoration(labelText: 'Replace with'),
                onChanged: (value) => replacement = value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (query.isEmpty) return;
              final updated = _controller.fullText.replaceAll(
                query,
                replacement,
              );
              if (updated != _controller.fullText) {
                setAssignmentEditorContent(_controller, updated);
                _handleEditableCodeChanged();
              }
              Navigator.pop(dialogContext);
            },
            child: const Text('Replace all'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFindDialog() async {
    var enteredQuery = '';
    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Find in code'),
        content: TextField(
          key: const Key('editor-find-field'),
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Find'),
          onChanged: (value) => enteredQuery = value,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, enteredQuery),
            child: const Text('Find next'),
          ),
        ],
      ),
    );
    if (!mounted || query == null || query.isEmpty) return;
    final start =
        _controller.selection.end.clamp(0, _controller.fullText.length);
    var match = _controller.fullText.indexOf(query, start);
    if (match < 0 && start > 0) {
      match = _controller.fullText.indexOf(query);
    }
    if (match < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“$query” was not found.')),
      );
      return;
    }
    _controller.selection = TextSelection(
      baseOffset: match,
      extentOffset: match + query.length,
    );
    _editorFocusNode.requestFocus();
  }

  void _showShortcutHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => const AlertDialog(
        title: Text('Editor shortcuts'),
        content: Text(
          'Ctrl+Enter  Run tests\n'
          'Ctrl+S  Save draft now (Ctrl+Alt+D browser fallback)\n'
          'Ctrl+F  Find (Ctrl+Alt+Q browser fallback)\n'
          'Ctrl+H  Replace (Ctrl+Alt+W browser fallback)\n'
          'Shift+Alt+F  Format Python (Ctrl+Shift+I on Linux)\n'
          'Ctrl+Alt+R  Restore starter code\n'
          'Ctrl+- / Ctrl+=  Editor font (Ctrl+Alt+1 / Ctrl+Alt+2 fallback)\n'
          'Ctrl+Alt+A  Python names and APIs\n'
          'F1  Keyboard shortcuts (Ctrl+Alt+K browser fallback)\n'
          'Ctrl+Alt+T  Switch editor theme\n'
          'Ctrl+Alt+E  Focus or restore code editor\n'
          'Ctrl+Z  Undo\n'
          'Ctrl+Y or Ctrl+Shift+Z  Redo\n'
          'Tab / Shift+Tab  Indent or outdent selected lines\n'
          'Ctrl+/  Toggle comments',
        ),
      ),
    );
  }

  void _changeEditorFontSize(int delta) {
    setState(() => _editorFontSize = (_editorFontSize + delta).clamp(12, 22));
  }

  void _toggleEditorTheme() {
    setState(() => _editorDarkMode = !_editorDarkMode);
  }

  Future<void> _showApiReference() async {
    final assignment = await _assignment;
    if (!mounted) return;
    final items = assignmentApiReference(assignment);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Available Python names'),
        content: SizedBox(
          width: 520,
          child: SelectableText(
            items.isEmpty
                ? 'Use the names provided in the starter code and instructions.'
                : items.join('\n'),
          ),
        ),
      ),
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
    if (target == AssignmentWorkspaceFocus.results) {
      _openResultsPanel();
      return;
    }
    setState(() {
      if (useDesktopLayout) {
        _workspaceFocus = target;
      } else {
        _selectedWorkspaceTab = switch (target) {
          AssignmentWorkspaceFocus.editor => 0,
          AssignmentWorkspaceFocus.instructions => 1,
          AssignmentWorkspaceFocus.results => _selectedWorkspaceTab,
          AssignmentWorkspaceFocus.none => _selectedWorkspaceTab,
        };
      }
    });
  }

  void _openResultsPanel() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  Widget _resultsPanel() => ColoredBox(
        color: AppColors.resultsSurface,
        child: SafeArea(
          child: Column(key: const Key('assignment-results-panel'), children: [
            Container(
              color: AppColors.resultsHeader,
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(children: [
                const Icon(Icons.fact_check_rounded),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Results',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700))),
                IconButton(
                  key: const Key('minimize-results-button'),
                  tooltip: 'Minimize results',
                  onPressed: () => _scaffoldKey.currentState?.closeEndDrawer(),
                  icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                ),
              ]),
            ),
            SwitchListTile(
              key: const Key('results-ai-toggle'),
              title: const Text('AI tutoring'),
              subtitle: const Text(
                  'Off by default; built-in feedback remains available'),
              value: _enableFeedback,
              onChanged: (value) {
                setState(() => _enableFeedback = value);
                unawaited(_trackWorkspaceEvent(
                    'ai_tutor_toggled', {'enabled': value}));
              },
            ),
            Expanded(
                child: _emptyCodeAttempted
                    ? EmptyCodeTestRunState(onRestore: _resetStarterCode)
                    : _submitted
                        ? FutureBuilder<UnittestFeedbackDto>(
                            future: _feedback,
                            builder: (ctx, snap) {
                              if (snap.connectionState ==
                                  ConnectionState.waiting) {
                                return const SecureGraderLoadingState();
                              }
                              if (snap.hasError) {
                                final error = snap.error;
                                return TestRunErrorState(
                                  onRetry: _runTests,
                                  message: error is ApiRequestException
                                      ? error.message
                                      : null,
                                );
                              }
                              if (snap.hasData) {
                                return Feedback(
                                    data: snap.data!,
                                    aiTutorEnabled: _enableFeedback);
                              }
                              return const SizedBox.shrink();
                            })
                        : const _EmptyResultsState()),
          ]),
        ),
      );

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
    final showResizeHandle =
        useDesktopLayout && _workspaceFocus == AssignmentWorkspaceFocus.none;
    final progressState = learningProgress.assignmentState(widget.id);
    final submissionStatus = lastAttemptAccuracy.containsKey(widget.id)
        ? _hasUnrunChanges
            ? '${progressState.label} • Code changed • Previous score: ${lastAttemptAccuracy[widget.id]}%'
            : '${progressState.label} • Last score: ${lastAttemptAccuracy[widget.id]}%'
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
      onResultsOpen: _openResultsPanel,
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
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _showFindDialog,
          const SingleActivator(LogicalKeyboardKey.keyQ,
              control: true, alt: true): _showFindDialog,
          const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
            if (_selectedProjectFileEditable) _showReplaceDialog();
          },
          const SingleActivator(LogicalKeyboardKey.keyW,
              control: true, alt: true): () {
            if (_selectedProjectFileEditable) _showReplaceDialog();
          },
          const SingleActivator(LogicalKeyboardKey.keyD,
              control: true, alt: true): () {
            if (_selectedProjectFileEditable) _saveDraftNow();
          },
          const SingleActivator(LogicalKeyboardKey.keyF,
              shift: true, alt: true): () {
            if (_selectedProjectFileEditable) _formatCode();
          },
          const SingleActivator(LogicalKeyboardKey.keyI,
              control: true, shift: true): () {
            if (_selectedProjectFileEditable) _formatCode();
          },
          const SingleActivator(LogicalKeyboardKey.keyR,
              control: true, alt: true): () {
            if (_selectedProjectFileEditable) _resetStarterCode();
          },
          const SingleActivator(LogicalKeyboardKey.minus, control: true): () {
            _changeEditorFontSize(-1);
          },
          const SingleActivator(LogicalKeyboardKey.digit1,
              control: true, alt: true): () {
            _changeEditorFontSize(-1);
          },
          const SingleActivator(LogicalKeyboardKey.equal, control: true): () {
            _changeEditorFontSize(1);
          },
          const SingleActivator(LogicalKeyboardKey.digit2,
              control: true, alt: true): () {
            _changeEditorFontSize(1);
          },
          const SingleActivator(LogicalKeyboardKey.keyA,
              control: true, alt: true): _showApiReference,
          const SingleActivator(LogicalKeyboardKey.f1): _showShortcutHelp,
          const SingleActivator(LogicalKeyboardKey.keyK,
              control: true, alt: true): _showShortcutHelp,
          const SingleActivator(LogicalKeyboardKey.keyT,
              control: true, alt: true): _toggleEditorTheme,
          const SingleActivator(LogicalKeyboardKey.keyE, control: true, alt: true):
              () => _toggleWorkspaceFocus(
                    AssignmentWorkspaceFocus.editor,
                  ),
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
            key: _scaffoldKey,
            appBar: appBar,
            endDrawer: Drawer(
              width: MediaQuery.sizeOf(context).width >= 600
                  ? 520
                  : MediaQuery.sizeOf(context).width * 0.94,
              backgroundColor: AppColors.resultsSurface,
              child: _resultsPanel(),
            ),
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
                                  onRun: _init ? null : _runTests,
                                  onTryInputs:
                                      _init || _playgroundFunction == null
                                          ? null
                                          : () => unawaited(_openPlayground()),
                                  onSave: _selectedProjectFileEditable
                                      ? () => unawaited(_saveDraftNow())
                                      : null,
                                  saveState: _draftSaveState,
                                  onSearch: _showFindDialog,
                                  onReplace: _selectedProjectFileEditable
                                      ? _showReplaceDialog
                                      : null,
                                  onFormat: _selectedProjectFileEditable
                                      ? _formatCode
                                      : null,
                                  onReset: _selectedProjectFileEditable
                                      ? _resetStarterCode
                                      : null,
                                  onShowShortcuts: _showShortcutHelp,
                                  onShowApiReference: _showApiReference,
                                  editorDarkMode: _editorDarkMode,
                                  onToggleEditorTheme: _toggleEditorTheme,
                                  fontSize: _editorFontSize,
                                  onDecreaseFont: () =>
                                      _changeEditorFontSize(-1),
                                  onIncreaseFont: () =>
                                      _changeEditorFontSize(1),
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
                                          final localDraft =
                                              learningProgress.draftFor(
                                            widget.id,
                                            snap.data!.version,
                                          );
                                          // A local draft the server never
                                          // confirmed is newer than the
                                          // server copy.
                                          final preferLocal = localDraft !=
                                                  null &&
                                              learningProgress.hasUnsyncedDraft(
                                                widget.id,
                                              );
                                          _code = (preferLocal
                                                  ? localDraft
                                                  : _serverDraft) ??
                                              localDraft ??
                                              snap.data!.code;
                                          if (preferLocal) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                              if (mounted) {
                                                unawaited(
                                                  _persistDraft(_code),
                                                );
                                              }
                                            });
                                          }
                                          _selectedProjectFilePath =
                                              snap.data!.editableFilePath;
                                          _selectedProjectFileEditable = true;
                                          _playgroundFunction =
                                              snap.data!.playgroundFunction;
                                          _simulationConfig =
                                              snap.data!.simulationConfig;
                                          setAssignmentEditorContent(
                                            _controller,
                                            _code,
                                          );
                                          _init = false;
                                          // The toolbar was built earlier in
                                          // this frame; rebuild it so Run
                                          // tests becomes enabled.
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            if (mounted) setState(() {});
                                          });
                                        }
                                        return AssignmentProjectWorkspace(
                                          files: snap.data!.projectFiles,
                                          selectedPath:
                                              _selectedProjectFilePath,
                                          selectedFileEditable:
                                              _selectedProjectFileEditable,
                                          controller: _controller,
                                          editorDarkMode: _editorDarkMode,
                                          focusNode: _editorFocusNode,
                                          fontSize: _editorFontSize,
                                          diagnosticLine: _diagnosticLine,
                                          onFileSelected: _selectProjectFile,
                                          onChanged: () {
                                            if (_selectedProjectFileEditable) {
                                              _handleEditableCodeChanged();
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
                      if (showInstructions)
                        Expanded(
                          flex: showResizeHandle
                              ? ((1 - _editorWidthFraction) * 1000).round()
                              : 1,
                          child: LayoutBuilder(
                              builder: (context, rightConstraints) => Column(
                                    children: [
                                      // Instructions fill the right workspace panel.
                                      if (showInstructions)
                                        Expanded(
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
                                                    ? () =>
                                                        _toggleWorkspaceFocus(
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
                                                  child: FutureBuilder<
                                                      AssignmentDto>(
                                                    future: _assignment,
                                                    builder: (ctx, snap) {
                                                      if (snap.hasData) {
                                                        return AssignmentInstructions(
                                                          assignmentId:
                                                              widget.id,
                                                          assignmentVersion:
                                                              snap.data!
                                                                  .version,
                                                          html: snap
                                                              .data!.htmlDesc
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
                                                          hasSolution: snap
                                                              .data!
                                                              .hasSolution,
                                                          solutionRevealed:
                                                              solutionRevealedAssignments
                                                                  .contains(
                                                                      widget
                                                                          .id),
                                                          canRevealSolution:
                                                              learningProgress
                                                                  .hasAttempted(
                                                            widget.id,
                                                          ),
                                                          onSolutionRevealed:
                                                              () => unawaited(
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
                                    ],
                                  )),
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

class AssignmentInstructions extends StatefulWidget {
  const AssignmentInstructions({
    super.key,
    required this.html,
    this.assignmentId = 1,
    this.assignmentVersion = 1,
    this.solutionHtml = '',
    this.hasSolution = false,
    this.solutionRevealed = false,
    this.canRevealSolution = true,
    this.onSolutionRevealed,
  });

  final String html;
  final int assignmentId;
  final int assignmentVersion;
  final String solutionHtml;
  final bool hasSolution;
  final bool solutionRevealed;
  final bool canRevealSolution;
  final VoidCallback? onSolutionRevealed;

  @override
  State<AssignmentInstructions> createState() => _AssignmentInstructionsState();
}

class _AssignmentInstructionsState extends State<AssignmentInstructions> {
  final _scenario = GlobalKey();
  final _task = GlobalKey();
  final _support = GlobalKey();

  Widget _sectionLink(String label, GlobalKey target) => OutlinedButton(
      onPressed: () {
        final targetContext = target.currentContext;
        if (targetContext != null) {
          Scrollable.ensureVisible(targetContext,
              duration: const Duration(milliseconds: 250));
        }
      },
      child: Text(label));

  @override
  Widget build(BuildContext context) {
    final sections = AssignmentInstructionSections.fromHtml(
        versionAssignmentImages(widget.html, widget.assignmentVersion));
    final taskList = InstructionTaskList.fromHtml(sections.task);
    final displayedSolutionHtml = widget.solutionHtml.isNotEmpty
        ? widget.solutionHtml
        : sections.solution;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _sectionLink('Scenario', _scenario),
          if (sections.task.isNotEmpty) _sectionLink('Your task', _task),
          if (sections.support.isNotEmpty)
            _sectionLink('Data & rules', _support),
        ]),
        const SizedBox(height: 12),
        SizedBox(key: _scenario),
        _InstructionSectionCard(
          key: const Key('instruction-scenario-section'),
          icon: Icons.explore_outlined,
          title: 'Scenario',
          subtitle: 'Understand the environment and objective',
          html: sections.scenario,
        ),
        if (sections.task.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(key: _task),
          _InstructionSectionCard(
            key: const Key('instruction-task-section'),
            icon: Icons.task_alt_rounded,
            title: 'Your task',
            subtitle: 'What your solution needs to calculate',
            html: taskList.remainingHtml,
            introHtml: taskList.introHtml,
            checklistItems: taskList.items,
          ),
        ],
        if (sections.support.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(key: _support),
          _InstructionSectionCard(
            key: const Key('instruction-support-section'),
            icon: Icons.tips_and_updates_outlined,
            title: 'Helpful information',
            subtitle: 'Given data, hints, and assumptions',
            html: sections.support,
          ),
        ],
        if (widget.hasSolution || displayedSolutionHtml.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _SolutionSection(
            html: displayedSolutionHtml,
            revealed: widget.solutionRevealed,
            canReveal: widget.canRevealSolution,
            onReveal: widget.onSolutionRevealed,
          ),
        ],
      ],
    );
  }
}

// A new assignment version must not reuse Flutter/browser's old image URL.
String versionAssignmentImages(String html, int version) {
  return html.replaceAllMapped(
    RegExp(r'''(<img\b[^>]*\bsrc\s*=\s*)(["'])([^"']+)\2''',
        caseSensitive: false),
    (match) {
      final uri = Uri.tryParse(match[3]!);
      if (uri == null || !RegExp(r'^/images/\d+$').hasMatch(uri.path)) {
        return match[0]!;
      }
      final updated = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'assignment_version': '$version',
      });
      return '${match[1]}${match[2]}$updated${match[2]}';
    },
  );
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

class InstructionTaskList {
  const InstructionTaskList({
    required this.items,
    required this.introHtml,
    required this.remainingHtml,
  });

  final List<String> items;
  final String introHtml;
  final String remainingHtml;

  static final RegExp _orderedList =
      RegExp(r'<ol(?:\s[^>]*)?>(.*?)</ol>', caseSensitive: false, dotAll: true);
  static final RegExp _item =
      RegExp(r'<li(?:\s[^>]*)?>(.*?)</li>', caseSensitive: false, dotAll: true);

  factory InstructionTaskList.fromHtml(String html) {
    final list = _orderedList.firstMatch(html);
    if (list == null) {
      return InstructionTaskList(
          items: const [], introHtml: '', remainingHtml: html);
    }
    final items = _item
        .allMatches(list.group(1)!)
        .map((match) => match.group(1)!)
        .toList();
    if (items.isEmpty) {
      return InstructionTaskList(
          items: const [], introHtml: '', remainingHtml: html);
    }
    return InstructionTaskList(
      items: items,
      introHtml: html.substring(0, list.start),
      remainingHtml: html.substring(list.end),
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
    this.introHtml = '',
    this.checklistItems = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String html;
  final String introHtml;
  final List<String> checklistItems;

  void _showDiagram(BuildContext context, String source, String? alt) {
    final imageUri = apiBaseUri.resolve(source);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width * 0.9,
          height: MediaQuery.sizeOf(context).height * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(alt ?? 'Assignment diagram')),
                  IconButton(
                    tooltip: 'Close enlarged diagram',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Flexible(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Image.network(
                    imageUri.toString(),
                    fit: BoxFit.contain,
                    semanticLabel: alt ?? 'Assignment diagram',
                    errorBuilder: (context, error, stackTrace) => const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text('Diagram unavailable. Try again later.'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
            if (introHtml.trim().isNotEmpty) ...[
              HtmlWidget(
                introHtml,
                baseUrl: apiBaseUri,
                textStyle: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.65,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (checklistItems.isNotEmpty) ...[
              Text('What to complete',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.sm),
              ...checklistItems.asMap().entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: CircleAvatar(
                            radius: 12,
                            child: Text('${entry.key + 1}',
                                style: theme.textTheme.labelSmall),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Semantics(
                            label: 'Task step ${entry.key + 1}',
                            child: HtmlWidget(entry.value,
                                baseUrl: apiBaseUri,
                                textStyle: theme.textTheme.bodyMedium),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (html.trim().isNotEmpty)
              HtmlWidget(
                html,
                baseUrl: apiBaseUri,
                onTapImage: (image) {
                  if (image.sources.isNotEmpty) {
                    _showDiagram(context, image.sources.first.url, image.alt);
                  }
                },
                textStyle: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.65,
                ),
              ),
            if (html.contains('<img'))
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text('Tap the diagram to enlarge it',
                    style: theme.textTheme.labelSmall),
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
  // Null while the assignment code is still loading.
  final VoidCallback? onRun;
  // Null when the assignment has no ungraded input playground.
  final VoidCallback? onTryInputs;
  final VoidCallback? onSave;
  final bool isFocused;
  final VoidCallback? onFocusToggle;
  final DraftSaveState saveState;
  final VoidCallback? onSearch;
  final VoidCallback? onReplace;
  final VoidCallback? onFormat;
  final VoidCallback? onReset;
  final VoidCallback? onShowShortcuts;
  final VoidCallback? onShowApiReference;
  final bool editorDarkMode;
  final VoidCallback? onToggleEditorTheme;
  final double fontSize;
  final VoidCallback? onDecreaseFont;
  final VoidCallback? onIncreaseFont;

  const AssignmentEditorToolbar({
    super.key,
    required this.isRunning,
    required this.onRun,
    this.onTryInputs,
    this.onSave,
    this.isFocused = false,
    this.onFocusToggle,
    this.saveState = DraftSaveState.idle,
    this.onSearch,
    this.onReplace,
    this.onFormat,
    this.onReset,
    this.onShowShortcuts,
    this.onShowApiReference,
    this.editorDarkMode = true,
    this.onToggleEditorTheme,
    this.fontSize = 16,
    this.onDecreaseFont,
    this.onIncreaseFont,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget toolButton({
      required String keyName,
      required IconData icon,
      required String label,
      required String shortcut,
      required VoidCallback? onPressed,
    }) =>
        IconButton(
          key: Key('editor-$keyName-button'),
          tooltip: '$label ($shortcut)',
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          visualDensity: VisualDensity.compact,
        );

    return Container(
      height: 108,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          Row(
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
              if (saveState != DraftSaveState.idle)
                Tooltip(
                  message: switch (saveState) {
                    DraftSaveState.saving => 'Saving draft',
                    DraftSaveState.saved => 'Draft saved',
                    DraftSaveState.sessionSaved =>
                      'Draft saved for this session; refresh resets it',
                    DraftSaveState.failed =>
                      'Cloud save failed. A local fallback remains available.',
                    DraftSaveState.idle => '',
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: Icon(
                      switch (saveState) {
                        DraftSaveState.saving => Icons.sync_rounded,
                        DraftSaveState.saved => Icons.cloud_done_outlined,
                        DraftSaveState.sessionSaved => Icons.save_outlined,
                        DraftSaveState.failed => Icons.cloud_off_outlined,
                        DraftSaveState.idle => Icons.cloud_outlined,
                      },
                      key: const Key('draft-save-state-icon'),
                      size: 20,
                      color: saveState == DraftSaveState.failed
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                // Fade the trailing edge so a clipped row reads as scrollable.
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0, 0.9, 1],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: SingleChildScrollView(
                    key: const Key('editor-actions-scroll'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 24),
                    child: Row(
                      children: [
                        toolButton(
                          keyName: 'save',
                          icon: Icons.save_outlined,
                          label: 'Save draft',
                          shortcut: 'Ctrl+S / Ctrl+Alt+D',
                          onPressed: onSave,
                        ),
                        toolButton(
                          keyName: 'find',
                          icon: Icons.search_rounded,
                          label: 'Find',
                          shortcut: 'Ctrl+F / Ctrl+Alt+Q',
                          onPressed: onSearch,
                        ),
                        toolButton(
                          keyName: 'replace',
                          icon: Icons.find_replace_rounded,
                          label: 'Replace',
                          shortcut: 'Ctrl+H / Ctrl+Alt+W',
                          onPressed: onReplace,
                        ),
                        toolButton(
                          keyName: 'format',
                          icon: Icons.auto_fix_high_rounded,
                          label: 'Format Python',
                          shortcut: 'Shift+Alt+F / Ctrl+Shift+I',
                          onPressed: isRunning ? null : onFormat,
                        ),
                        toolButton(
                          keyName: 'restore',
                          icon: Icons.restart_alt_rounded,
                          label: 'Restore starter code',
                          shortcut: 'Ctrl+Alt+R',
                          onPressed: isRunning ? null : onReset,
                        ),
                        const SizedBox(
                            height: 28, child: VerticalDivider(width: 18)),
                        toolButton(
                          keyName: 'font-down',
                          icon: Icons.text_decrease_rounded,
                          label: 'Decrease editor font',
                          shortcut: 'Ctrl+- / Ctrl+Alt+1',
                          onPressed: fontSize > 12 ? onDecreaseFont : null,
                        ),
                        toolButton(
                          keyName: 'font-up',
                          icon: Icons.text_increase_rounded,
                          label: 'Increase editor font',
                          shortcut: 'Ctrl+= / Ctrl+Alt+2',
                          onPressed: fontSize < 22 ? onIncreaseFont : null,
                        ),
                        const SizedBox(
                            height: 28, child: VerticalDivider(width: 18)),
                        toolButton(
                          keyName: 'reference',
                          icon: Icons.integration_instructions_outlined,
                          label: 'Python names and APIs',
                          shortcut: 'Ctrl+Alt+A',
                          onPressed: onShowApiReference,
                        ),
                        toolButton(
                          keyName: 'shortcuts',
                          icon: Icons.keyboard_outlined,
                          label: 'Keyboard shortcuts',
                          shortcut: 'F1 / Ctrl+Alt+K',
                          onPressed: onShowShortcuts,
                        ),
                        toolButton(
                          keyName: 'theme',
                          icon: editorDarkMode
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          label: editorDarkMode
                              ? 'Switch editor to light mode'
                              : 'Switch editor to dark mode',
                          shortcut: 'Ctrl+Alt+T',
                          onPressed: onToggleEditorTheme,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (onFocusToggle != null)
                IconButton(
                  key: const Key('focus-editor-button'),
                  tooltip: isFocused
                      ? 'Restore workspace (Ctrl+Alt+E)'
                      : 'Focus code editor (Ctrl+Alt+E)',
                  onPressed: onFocusToggle,
                  icon: Icon(
                    isFocused
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              if (onTryInputs != null) ...[
                const SizedBox(width: AppSpacing.xs),
                // Phones keep room for the editor tools with an icon-only button.
                if (MediaQuery.sizeOf(context).width < 480)
                  IconButton.outlined(
                    key: const Key('try-inputs-button'),
                    tooltip: 'Try inputs: call your function. Not graded or saved.',
                    onPressed: isRunning ? null : onTryInputs,
                    icon: const Icon(Icons.science_outlined, size: 20),
                  )
                else
                  Tooltip(
                    message: 'Call your function with your own inputs. '
                        'Not graded or saved.',
                    child: OutlinedButton.icon(
                      key: const Key('try-inputs-button'),
                      onPressed: isRunning ? null : onTryInputs,
                      icon: const Icon(Icons.science_outlined, size: 18),
                      label: const Text('Try inputs'),
                    ),
                  ),
              ],
              const SizedBox(width: AppSpacing.sm),
              Semantics(
                label: isRunning
                    ? 'Assignment tests are running'
                    : 'Run assignment tests. Keyboard shortcut Control Enter',
                button: true,
                enabled: !isRunning && onRun != null,
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
    this.editorDarkMode = true,
    this.focusNode,
    this.fontSize = 16,
    this.diagnosticLine,
    required this.onFileSelected,
    required this.onChanged,
  });

  final List<AssignmentProjectFile> files;
  final String? selectedPath;
  final bool selectedFileEditable;
  final CodeController controller;
  final bool editorDarkMode;
  final FocusNode? focusNode;
  final double fontSize;
  final int? diagnosticLine;
  final ValueChanged<AssignmentProjectFile> onFileSelected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = editorDarkMode ? EditorPalette.dark : EditorPalette.light;
    final editor = Column(
      children: [
        if (files.isNotEmpty)
          ProjectFileStatusBar(
            path: selectedPath ?? files.first.path,
            editable: selectedFileEditable,
            diagnosticLine: diagnosticLine,
          ),
        Expanded(
          child: Semantics(
            label: selectedFileEditable
                ? 'Editable Python code file'
                : 'Read-only project file',
            textField: true,
            readOnly: !selectedFileEditable,
            child: EditorIndentGuides(
              controller: controller,
              fontSize: fontSize,
              color: palette.lineNumber,
              child: CodeTheme(
                data: CodeThemeData(styles: palette.styles),
                child: CodeField(
                  key: const Key('assignment-code-field'),
                  controller: controller,
                  focusNode: focusNode,
                  cursorColor: palette.foreground,
                  gutterStyle: GutterStyle(
                    width: 64,
                    background: palette.background,
                    textStyle: TextStyle(color: palette.lineNumber),
                  ),
                  textSelectionTheme: TextSelectionThemeData(
                    cursorColor: palette.foreground,
                    selectionColor: palette.selection,
                    selectionHandleColor: palette.symbol,
                  ),
                  textStyle:
                      TextStyle(fontFamily: 'Courier-New', fontSize: fontSize),
                  expands: true,
                  minLines: null,
                  readOnly: !selectedFileEditable,
                  onChanged: (_) => onChanged(),
                ),
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final code = controller.text;
            final caret = controller.selection.baseOffset.clamp(0, code.length);
            final beforeCaret = code.substring(0, caret);
            final line = '\n'.allMatches(beforeCaret).length + 1;
            final column = caret - beforeCaret.lastIndexOf('\n');
            final lineText = code.split('\n')[line - 1];
            return Container(
              key: const Key('editor-position-status'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              color: palette.background,
              child: Text(
                'Ln $line, Col $column  ·  Indent level ${editorIndentLevel(lineText)}',
                style: TextStyle(color: palette.lineNumber, fontSize: 12),
              ),
            );
          },
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
    this.diagnosticLine,
  });

  final String path;
  final bool editable;
  final int? diagnosticLine;

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
          if (diagnosticLine != null) ...[
            Icon(
              Icons.error_outline_rounded,
              size: 15,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Check line $diagnosticLine',
              key: const Key('editor-diagnostic-line'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
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
  final VoidCallback onResultsOpen;
  final ValueChanged<bool> onFeedbackChanged;

  const AssignmentPageHeader({
    super.key,
    required this.title,
    required this.assignmentId,
    required this.status,
    required this.feedbackEnabled,
    required this.onBack,
    required this.onHome,
    required this.onResultsOpen,
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
      leadingWidth: showFeedbackLabel ? 64 : 48,
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
          SizedBox(width: showFeedbackLabel ? AppSpacing.md : AppSpacing.sm),
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
            key: const Key('open-results-button'),
            onPressed: onResultsOpen,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onPrimary,
            ),
            icon: const Icon(Icons.fact_check_outlined, size: 20),
            label: const Text('Results'),
          )
        else
          IconButton(
            key: const Key('open-results-button'),
            tooltip: 'Open results',
            onPressed: onResultsOpen,
            icon: const Icon(Icons.fact_check_outlined),
          ),
        // On phones Back already returns to the assignment list, so the
        // title keeps the space a duplicate Home icon would take.
        if (showFeedbackLabel)
          TextButton.icon(
            key: const Key('assignment-home-button'),
            onPressed: onHome,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onPrimary,
            ),
            icon: const Icon(Icons.home_rounded, size: 20),
            label: const Text('Home'),
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
        child: SingleChildScrollView(
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
                'Run your code to see test results and feedback. Tutor questions become available after the first run.',
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

class EmptyCodeTestRunState extends StatelessWidget {
  const EmptyCodeTestRunState({super.key, required this.onRestore});

  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('empty-code-test-run-state'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.code_off_rounded,
                size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.sm),
            Text('The code editor is empty',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Enter code or restore the starter code before running tests. '
              'No attempt was submitted. Tutor questions become available after a test run.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonalIcon(
              key: const Key('restore-starter-from-results'),
              onPressed: onRestore,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Restore starter code'),
            ),
          ],
        ),
      ),
    );
  }
}

class TestRunErrorState extends StatelessWidget {
  const TestRunErrorState({super.key, required this.onRetry, this.message});

  final VoidCallback onRetry;

  /// The server's explanation when it rejected the run (for example a rate
  /// limit); null when the grading service could not be reached.
  final String? message;

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
                message == null
                    ? 'Grading service unavailable'
                    : 'Your code was not graded',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message ??
                    'Your code was not graded. Confirm that the backend is '
                        'running at $apiBaseUrl, then try again.',
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
    final passRate = total > 0 ? (passed / total) * 100 : 0.0;
    final score = data.score.clamp(0, 100).toInt();
    final vars = data.testedVals.map((value) => value.toString()).toList();
    final tutorAvailable = aiTutorEnabled && data.submissionId.isNotEmpty;
    final showHint = data.hint.isNotEmpty &&
        (aiTutorEnabled || data.tutorSource != 'openai');

    final orderedChecks = data.unittestFeedback.asMap().entries.toList()
      ..sort((a, b) {
        final aPassed = a.key < data.unittestPassResults.length &&
            data.unittestPassResults[a.key];
        final bPassed = b.key < data.unittestPassResults.length &&
            data.unittestPassResults[b.key];
        return (aPassed ? 1 : 0).compareTo(bPassed ? 1 : 0);
      });
    final resultCards = orderedChecks.map((entry) {
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

      final detail =
          entry.key < data.evidence.length ? data.evidence[entry.key] : null;
      return _TestResultCard(
        checkNumber: entry.key + 1,
        passed: didPass,
        first: first,
        highlighted: highlighted,
        last: last,
        label: detail?.label,
        reason: detail?.reason,
        weight: detail?.weight,
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
            score: score,
            passRate: passRate,
          ),
          if (failed > 0 || !data.execSuccess) ...[
            const SizedBox(height: AppSpacing.sm),
            _ResultNextStep(executionFailed: !data.execSuccess),
          ],
          const SizedBox(height: AppSpacing.sm),
          _TerminalOutput(data: data),
          if (showHint || tutorAvailable) ...[
            const SizedBox(height: AppSpacing.md),
            _TutorHintPanel(
              data: data,
              allowQuestions: tutorAvailable,
              useAiTutor: aiTutorEnabled,
              questionRequester: tutorQuestionRequester ?? askTutorQuestion,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            failed > 0 ? 'Test details · failed first' : 'Test details',
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

class _ResultNextStep extends StatelessWidget {
  const _ResultNextStep({required this.executionFailed});

  final bool executionFailed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('result-next-step'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded,
              size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              executionFailed
                  ? 'Next step: resolve the execution error below, then run the tests again.'
                  : 'Next step: review the first failed check and compare that part of your code with the task instructions.',
              style: theme.textTheme.bodySmall,
            ),
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
    required this.score,
    required this.passRate,
  });

  final int passed;
  final int failed;
  final int score;
  final double passRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allPassed = failed == 0 && passed > 0;
    final statusColor = performanceColor(score);
    final statusBackground = statusColor.withValues(alpha: 0.12);

    return Semantics(
      container: true,
      label: 'Test score $score percent. $passed passed and $failed failed.',
      child: Container(
        key: const Key('result-summary'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: statusBackground,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: statusColor.withValues(alpha: 0.28)),
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
                  '$score%',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            LinearProgressIndicator(
              value: score / 100,
              color: statusColor,
              minHeight: 8,
              borderRadius: BorderRadius.circular(AppRadii.pill),
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
                  label: 'Pass rate: ${passRate.toStringAsFixed(1)}%',
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
    // AI-generated feedback always uses the reserved AI color and badge.
    final fromAi = source == 'openai';
    final foreground = fromAi ? AppColors.ai : Colors.brown.shade900;

    return Container(
      key: const Key('guided-hint'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: fromAi ? AppColors.aiContainer : const Color(0xFFFFF5D9),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: fromAi
              ? AppColors.ai.withValues(alpha: 0.35)
              : const Color(0xFFE7C968),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            fromAi
                ? Icons.auto_awesome_rounded
                : Icons.lightbulb_outline_rounded,
            color: fromAi ? AppColors.ai : Colors.amber.shade900,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      fromAi
                          ? 'OpenAI tutor hint'
                          : source == 'fallback'
                              ? 'Built-in tutor hint'
                              : 'Guided hint',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (fromAi) const AiGeneratedBadge(),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  hint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fromAi ? AppColors.ink : Colors.brown.shade900,
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

/// Marks content produced by the optional AI tutor.
class AiGeneratedBadge extends StatelessWidget {
  const AiGeneratedBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('ai-generated-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.ai,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Text(
          'AI-generated',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

class _TutorHintPanel extends StatefulWidget {
  const _TutorHintPanel({
    required this.data,
    required this.allowQuestions,
    required this.useAiTutor,
    required this.questionRequester,
  });

  final UnittestFeedbackDto data;
  final bool allowQuestions;
  final bool useAiTutor;
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
    if (oldWidget.data.submissionId != widget.data.submissionId ||
        oldWidget.allowQuestions != widget.allowQuestions) {
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
    _answer = !widget.allowQuestions || widget.data.tutorFeedback.isEmpty
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
        useAiTutor: widget.useAiTutor,
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
        color: source == 'openai'
            ? AppColors.aiContainer
            : Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: BorderSide(
            color: source == 'openai'
                ? AppColors.ai.withValues(alpha: 0.35)
                : AppColors.border,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    source == 'openai'
                        ? Icons.auto_awesome_rounded
                        : Icons.support_agent_rounded,
                    size: 18,
                    color: source == 'openai' ? AppColors.ai : AppColors.brand,
                  ),
                  Text(
                    source == 'openai'
                        ? 'OpenAI tutor response'
                        : 'Built-in tutor response',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: source == 'openai' ? AppColors.ai : null,
                        ),
                  ),
                  if (source == 'openai') const AiGeneratedBadge(),
                ],
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

/// Plain-language guidance for a grader failure reason, or null when the
/// check passed or the grader did not classify it.
String? failureReasonExplanation(String? reason) {
  return switch (reason) {
    'wrong_all_inputs' =>
      'Wrong for every grading scenario. Recheck the formula and make sure '
          'this value is returned in the right position.',
    'wrong_some_inputs' =>
      'Right for some scenarios but not all. Use the function parameters '
          'instead of fixed numbers, and check edge cases. Try inputs lets '
          'you test other values.',
    'error_on_some_inputs' =>
      'Your function stopped with an error on at least one scenario. Look '
          'for division by zero, empty lists, missing keys, or a missing '
          'function.',
    'unsupported_type' =>
      'This value has a type the grader cannot compare. Return plain numbers, '
          'text, or lists; for example, convert NumPy values with float().',
    'not_checked' =>
      'Not checked because the code did not finish running. Fix the error '
          'shown above first.',
    _ => null,
  };
}

String _formatPoints(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

class _TestResultCard extends StatelessWidget {
  const _TestResultCard({
    required this.checkNumber,
    required this.passed,
    required this.first,
    required this.highlighted,
    required this.last,
    this.label,
    this.reason,
    this.weight,
  });

  final int checkNumber;
  final bool passed;
  final String first;
  final String highlighted;
  final String last;
  final String? label;
  final String? reason;
  final double? weight;

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
                  if (label != null && label!.isNotEmpty)
                    Text(
                      label!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  Text(
                    weight == null
                        ? 'Check $checkNumber'
                        : 'Check $checkNumber · '
                            '${passed ? _formatPoints(weight!) : '0'} of '
                            '${_formatPoints(weight!)} points',
                    key: Key('test-result-points-$checkNumber'),
                    style: theme.textTheme.labelSmall,
                  ),
                  if (!passed && failureReasonExplanation(reason) != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      key: Key('test-result-reason-$checkNumber'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.tips_and_updates_outlined,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            failureReasonExplanation(reason)!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
