import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:iuse_demo/widgets/floating_app_bar.dart';
import 'package:iuse_demo/widgets/landing_page_header.dart';
import 'package:iuse_demo/state/current_session.dart';
import 'package:iuse_demo/state/feedback_mode.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:iuse_demo/editor/indent_guides.dart';
import 'package:iuse_demo/editor/editor_tools.dart';
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/models/playground_parameter.dart';
import 'package:iuse_demo/models/simulation_trace.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/services/assignment_api.dart';
import 'package:iuse_demo/services/research_api.dart';
import 'package:iuse_demo/state/app_learning_progress.dart';
import 'package:iuse_demo/state/learning_progress_store.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/theme/editor_palette.dart';
import 'package:iuse_demo/widgets/app_blocks.dart';
import 'package:iuse_demo/widgets/earlier_draft_banner.dart';
import 'package:iuse_demo/widgets/playground_dialog.dart';
import 'package:iuse_demo/widgets/robot_sim_panel.dart';
import 'package:iuse_demo/widgets/run_terminal.dart';
import 'package:highlight/languages/python.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.id,
    this.displayNumber,
  });
  final String title;
  final int id;

  /// The course number students see; null shows the ID.
  final int? displayNumber;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum AssignmentWorkspaceFocus { none, editor, instructions, results }

enum DraftSaveState { idle, saving, saved, sessionSaved, failed, outdated }

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
  // Set from the server once the assignment loads; AI stays off until then.
  bool _aiTutorAvailable = false;
  String _aiTutorMessage = aiTutorUnavailableMessage;
  bool _isRos2 = false;
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
  // Code kept from an older version of this assignment, offered to copy.
  String? _earlierDraft;
  double _editorFontSize = 16;
  bool _editorDarkMode = true;
  int? _diagnosticLine;

  /// The score before the latest run, to show how this run compares.
  int? _previousScore;
  bool _suppressEditorChange = false;
  String? _playgroundFunction;
  String _starterCode = '';
  // Terminal under the editor: what the last run printed and any error.
  // Open from the start, like the VS Code panel.
  bool _terminalExpanded = true;
  double _terminalHeight = 180;
  List<TerminalLine> _terminalLines = const [];
  String? _terminalRequestError;
  String _terminalFileName = 'your_code.py';
  bool _terminalPython = true;

  /// The ROS 2 run command (ros2 run, package, executable); null otherwise.
  String? _terminalCommand;
  Map<String, dynamic> _simulationConfig = const {};
  // Robot replay (visual only): the last simulation and which results tab shows.
  Future<SimulationResultDto>? _simulation;
  bool _isSimulating = false;
  // The code the terminal's simulation lines describe, when it shows one.
  String? _terminalSimulatedCode;
  // The square Simulation panel: docked above the instructions or floating.
  // Docked above the instructions by default; it can float as its own window.
  SimPanelMode _simMode = SimPanelMode.docked;
  // Scenario / Your task / Rules tabs shown in the Instructions header.
  final _instructionNav = InstructionSectionNav();
  // Starts collapsed so the empty panel does not cover the instructions;
  // the first Simulate opens it.
  bool _simCollapsed = true;
  // Null until moved: the window starts at the top right of the workspace.
  Offset? _simOffset;
  double _simSize = 660;
  // Share of the right column the docked panel takes; kept for the session.
  double _simDockFraction = kSimDockDefault;
  // The moment and view a failed check asked the replay to show.
  SimFocus? _simFocus;
  int _simFocusToken = 0;
  // Kept in memory only so reopening the playground restores the last inputs.
  String _playgroundArguments = '';
  // Playground runs for the current code only; memory only, never sent.
  List<PlaygroundRun> _playgroundHistory = const [];
  String _playgroundHistoryCode = '';

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
    if (mounted) {
      setState(() {
        _aiTutorAvailable = assignment.aiTutorAvailable;
        if (assignment.aiTutorMessage.isNotEmpty) {
          _aiTutorMessage = assignment.aiTutorMessage;
        }
        _isRos2 = assignment.language.contains('ros2');
        if (!_aiTutorAvailable) _enableFeedback = false;
      });
    }
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
    _instructionNav.dispose();
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
    } on AssignmentChangedException {
      if (mounted && code == _code) {
        setState(() => _draftSaveState = DraftSaveState.outdated);
      }
      return DraftSaveState.outdated;
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
          DraftSaveState.outdated => 'This assignment was updated while it '
              'was open, so the cloud copy was not saved. Your code is kept '
              'on this device: reopen the assignment to see the new version '
              'and copy your code across.',
          _ => 'Cloud save failed. Your code is kept on this device; check '
              'your connection and try Ctrl+S again.',
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

  /// AI feedback is requested only when the server offers it and the student
  /// turned it on; otherwise use_ai_tutor is always false.
  bool get _aiTutorOn => _aiTutorAvailable && _enableFeedback;

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
    final ranCode = _code;
    setState(() {
      _terminalExpanded = true;
      _terminalLines = const [];
      _terminalRequestError = null;
      _submitted = true;
      _emptyCodeAttempted = false;
      _isRunning = true;
      _terminalSimulatedCode = null;
      _hasUnrunChanges = false;
      _diagnosticLine = null;
      _feedback = fetchUnittestFeedback(
        widget.id,
        _code,
        useAiTutor: _aiTutorOn,
      );
    });
    _openResultsPanel();

    _feedback.then(
      (feedback) {
        if (!mounted) {
          return;
        }
        final score = feedback.score.clamp(0, 100).toInt();
        final previousScore = learningProgress.latestScores[widget.id];
        setState(() {
          _previousScore = previousScore;
          lastAttemptAccuracy[widget.id] = score;
          _submissionId = feedback.submissionId;
          _isRunning = false;
          _terminalLines = buildRunTerminalLines(
            data: feedback,
            code: ranCode,
            fileName: _terminalFileName,
            python: _terminalPython,
            command: _terminalCommand,
          );
          _diagnosticLine = extractPythonErrorLine(
            '${feedback.codeExecResult}\n${feedback.codeOutput}',
            _controller.fullText.split('\n').length,
          );
        });
        unawaited(
          learningProgress.recordSubmission(widget.id, feedback.submissionId),
        );
        unawaited(learningProgress.recordAttempt(widget.id, score));
        if (summarizeChecks(feedback) case final checks?) {
          unawaited(learningProgress.recordCheckSummary(widget.id, checks));
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _isRunning = false;
            _terminalRequestError = error is ApiRequestException
                ? error.message
                : 'Could not reach the code runner. Check your connection '
                    'and try again.';
          });
        }
      },
    );
  }

  bool get _hasRobotSimulation =>
      currentFeedbackMode.value.allowsSimulation &&
      _simulationConfig['enabled'] == true &&
      _simulationConfig['provider'] == 'ros2_2d';

  void _runSimulation({bool keepFocus = false}) {
    if (_init || _isSimulating || _isRunning) return;
    if (!keepFocus) _simFocus = null;
    if (!hasNonWhitespaceCode(_code)) {
      setState(() {
        _emptyCodeAttempted = true;
        });
      _openResultsPanel();
      return;
    }
    final simulatedCode = _code;
    final simulation = runSimulation(widget.id, simulatedCode);
    setState(() {
      _isSimulating = true;
      _simulation = simulation;
      _simCollapsed = false;
      _emptyCodeAttempted = false;
      if (MediaQuery.sizeOf(context).width < 900) {
        _selectedWorkspaceTab = 2;
      } else if (_simMode == SimPanelMode.docked &&
          _workspaceFocus == AssignmentWorkspaceFocus.editor) {
        // A docked panel lives in the right column; bring it back.
        _workspaceFocus = AssignmentWorkspaceFocus.none;
      }
    });
    simulation.then(
      (result) {
        if (!mounted) return;
        setState(() {
          _isSimulating = false;
          _terminalExpanded = true;
          _terminalRequestError = null;
          _terminalLines =
              buildSimulationTerminalLines(result, _terminalFileName);
          _terminalSimulatedCode = simulatedCode;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _isSimulating = false);
      },
    );
  }

  /// Opens the replay at the moment that shows a failed check, simulating the
  /// current code first when there is no replay of it yet.
  void _watchInSimulation(String hintKey) {
    final focus = SimFocus.forHint(hintKey, ++_simFocusToken);
    if (focus == null) return;
    _scaffoldKey.currentState?.closeEndDrawer();
    final needsRun = _simulation == null || _terminalSimulatedCode != _code;
    setState(() {
      _simFocus = focus;
      _simCollapsed = false;
      if (MediaQuery.sizeOf(context).width < 900) _selectedWorkspaceTab = 2;
    });
    if (needsRun) _runSimulation(keepFocus: true);
  }

  void _toggleSimMode() {
    setState(() {
      _simMode = _simMode == SimPanelMode.docked
          ? SimPanelMode.floating
          : SimPanelMode.docked;
      _simCollapsed = false;
    });
  }

  void _openSimFullScreen() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: RobotSimPanel(
          simulation: _simulation,
          isSimulating: _isSimulating,
          onSimulate: null,
          onClose: () => Navigator.pop(dialogContext),
        ),
      ),
    );
  }

  /// The docked panel or the phone Simulation tab.
  Widget _simPanel({required bool phone}) => RobotSimPanel(
        simulation: _simulation,
        isSimulating: _isSimulating,
        onSimulate: _init ? null : _runSimulation,
        collapsed: !phone && _simCollapsed,
        onToggleCollapsed:
            phone ? null : () => setState(() => _simCollapsed = !_simCollapsed),
        onToggleMode: phone ? null : _toggleSimMode,
        onFullScreen: _openSimFullScreen,
        focus: _simFocus,
      );

  /// The panel as its own window over the workspace: drag the header to
  /// move it and the corner to resize it.
  Widget _floatingSimPanel(BoxConstraints area) {
    final size = _simSize
        .clamp(280.0,
            math.max(280.0, math.min(area.maxWidth - 32, area.maxHeight - 64)))
        .toDouble();
    // Header, then the strip when collapsed; otherwise room for the view
    // switch on top of a square replay.
    final height = _simCollapsed
        ? 48.0 + (_simulation == null ? 0 : kSimStripHeight)
        : math.min(size + 92, math.max(200.0, area.maxHeight - 16));
    final offset = _simOffset ?? Offset(area.maxWidth - size - 24, 16);
    final left =
        offset.dx.clamp(0.0, math.max(0.0, area.maxWidth - size)).toDouble();
    final top =
        offset.dy.clamp(0.0, math.max(0.0, area.maxHeight - 48)).toDouble();
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: RobotSimPanel(
              simulation: _simulation,
              isSimulating: _isSimulating,
              onSimulate: _init ? null : _runSimulation,
              mode: SimPanelMode.floating,
              collapsed: _simCollapsed,
              onToggleCollapsed: () =>
                  setState(() => _simCollapsed = !_simCollapsed),
              onToggleMode: _toggleSimMode,
              onFullScreen: _openSimFullScreen,
              onHeaderDrag: (details) => setState(
                  () => _simOffset = Offset(left, top) + details.delta),
              focus: _simFocus,
            ),
          ),
          if (!_simCollapsed)
            Positioned(
              right: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: GestureDetector(
                  key: const Key('robot-sim-resize'),
                  onPanUpdate: (details) => setState(() => _simSize =
                      (size + math.max(details.delta.dx, details.delta.dy))
                          .clamp(280.0, 900.0)
                          .toDouble()),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(LucideIcons.maximize2,
                        size: 16,
                        color: Theme.of(context).colorScheme.outline),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openPlayground() async {
    final functionName = _playgroundFunction;
    if (_init || functionName == null) return;
    if (_playgroundHistoryCode != _code) {
      _playgroundHistory = const [];
      _playgroundHistoryCode = _code;
    }
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
        sampleArguments: playgroundSampleArguments(_simulationConfig),
        parameters: playgroundParameters(_simulationConfig),
        scenarios: playgroundScenarios(_simulationConfig),
        history: _playgroundHistory,
        onHistoryChanged: (runs) => _playgroundHistory = runs,
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
      // Earlier results belong to the replaced code, as after any edit.
      _hasUnrunChanges = true;
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

  void _openLineInEditor(int line) {
    final lines = _controller.fullText.split('\n');
    if (line < 1 || line > lines.length) return;
    var offset = 0;
    for (var index = 0; index < line - 1; index++) {
      offset += lines[index].length + 1;
    }
    _controller.selection = TextSelection.collapsed(offset: offset);
    setState(() => _diagnosticLine = line);
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
          'Ctrl+Alt+A  Names in the starter code\n'
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
        title: const Text('Names in the starter code'),
        content: SizedBox(
          width: 520,
          child: SelectableText(
            '${items.isEmpty ? 'Use the names provided in the starter code '
                'and instructions.' : items.join('\n')}\n\n'
            'These are the functions, classes, and imports in the starter '
            'files. The instructions say which imports are allowed.',
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

  void _setAiTutor(bool value) {
    setState(() => _enableFeedback = value);
    unawaited(_trackWorkspaceEvent('ai_tutor_toggled', {'enabled': value}));
  }

  Widget _resultsPanel() => ColoredBox(
        color: AppColors.resultsSurface,
        child: SafeArea(
          child: Column(key: const Key('assignment-results-panel'), children: [
            Container(
              decoration: const BoxDecoration(
                color: AppColors.resultsHeader,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(children: [
                const IconTile(icon: LucideIcons.clipboardCheck),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('Results',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.brandDark))),
                // The same AI button as the page header, so the switch can
                // be reached while Results covers the header.
                if (currentFeedbackMode.value.allowsAi)
                  Tooltip(
                    message: _aiTutorAvailable
                        ? 'Built-in feedback stays available'
                        : _aiTutorMessage,
                    child: AiToggle(
                      key: const Key('results-ai-toggle'),
                      onDark: false,
                      value: _aiTutorOn,
                      onChanged: _aiTutorAvailable ? _setAiTutor : null,
                    ),
                  ),
                IconButton(
                  key: const Key('minimize-results-button'),
                  tooltip: 'Minimize results',
                  onPressed: () => _scaffoldKey.currentState?.closeEndDrawer(),
                  icon: const Icon(LucideIcons.panelRightClose),
                ),
              ]),
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
                                return SecureGraderLoadingState(
                                    ros2Package: _isRos2);
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
                                    previousScore: _previousScore,
                                    errorLine: _diagnosticLine,
                                    onGoToLine: (line) {
                                      _scaffoldKey.currentState
                                          ?.closeEndDrawer();
                                      _openLineInEditor(line);
                                    },
                                    aiTutorEnabled: _aiTutorOn,
                                    onWatchInSimulation: _hasRobotSimulation
                                        ? _watchInSimulation
                                        : null);
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
    final showSimTab = !useDesktopLayout &&
        _hasRobotSimulation &&
        _selectedWorkspaceTab == 2;
    final showDockedSim = useDesktopLayout &&
        _hasRobotSimulation &&
        _simMode == SimPanelMode.docked;
    final showFloatingSim = useDesktopLayout &&
        _hasRobotSimulation &&
        _simMode == SimPanelMode.floating;
    final showInstructions = useDesktopLayout
        ? _workspaceFocus == AssignmentWorkspaceFocus.none ||
            _workspaceFocus == AssignmentWorkspaceFocus.instructions
        : _selectedWorkspaceTab == 1 || showSimTab;
    final showResizeHandle =
        useDesktopLayout && _workspaceFocus == AssignmentWorkspaceFocus.none;
    // Saved work shows as in progress, whether it is on this device or
    // came back from the server.
    final serverDraft = _serverDraft;
    final progressState = learningProgress.assignmentState(
      widget.id,
      assignmentVersion: _assignmentVersion,
      starterCode: _starterCode,
      hasServerDraft: serverDraft != null &&
          serverDraft.trim().isNotEmpty &&
          serverDraft != _starterCode,
    );
    final lastScore = lastAttemptAccuracy[widget.id];
    final appBar = AssignmentPageHeader(
      title: widget.title,
      assignmentId: widget.id,
      displayNumber: widget.displayNumber,
      status: progressState.label,
      lastScore: lastScore,
      checks: learningProgress.checkSummaries[widget.id],
      codeChangedSinceScore: lastScore != null && _hasUnrunChanges,
      solutionViewed: solutionRevealedAssignments.contains(widget.id),
      feedbackEnabled: _aiTutorOn,
      aiTutorAvailable: _aiTutorAvailable,
      aiTutorMessage: _aiTutorMessage,
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
            // Results slide in without dimming the editor, so the terminal
            // stays readable next to the feedback.
            drawerScrimColor: Colors.transparent,
            endDrawer: Drawer(
              width: MediaQuery.sizeOf(context).width >= 600
                  ? 520
                  : MediaQuery.sizeOf(context).width * 0.94,
              backgroundColor: AppColors.resultsSurface,
              child: _resultsPanel(),
            ),
            body: LayoutBuilder(
              builder: (context, bodyArea) => Stack(
                children: [
                  Positioned.fill(
                    child: Column(
              children: [
                if (!useDesktopLayout)
                  AssignmentWorkspaceNavigation(
                    showSimulation: _hasRobotSimulation,
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
                            margin: useDesktopLayout
                                ? EdgeInsets.fromLTRB(
                                    AppSpacing.sm,
                                    AppSpacing.sm,
                                    showResizeHandle ? 0 : AppSpacing.sm,
                                    AppSpacing.sm,
                                  )
                                : EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            decoration: workspaceCardDecoration(
                              context,
                              framed: useDesktopLayout,
                              color: Theme.of(
                                context,
                              ).colorScheme.secondaryFixedDim,
                            ),
                            foregroundDecoration: useDesktopLayout
                                ? workspaceCardEdge()
                                : null,
                            child: Column(
                              children: [
                                AssignmentEditorToolbar(
                                  isRunning: _isRunning,
                                  onRun: _init ? null : _runTests,
                                  onTryInputs:
                                      _init || _playgroundFunction == null
                                          ? null
                                          : () => unawaited(_openPlayground()),
                                  onSimulate: _init || !_hasRobotSimulation
                                      ? null
                                      : _runSimulation,
                                  isSimulating: _isSimulating,
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
                                          _starterCode = snap.data!.code;
                                          final earlier = learningProgress
                                              .earlierDraftFor(
                                            widget.id,
                                            snap.data!.version,
                                          );
                                          _earlierDraft = earlier != null &&
                                                  earlier.trim().isNotEmpty &&
                                                  earlier != _starterCode &&
                                                  earlier != _code
                                              ? earlier
                                              : null;
                                          _terminalFileName = snap
                                                  .data!.editableFilePath
                                                  ?.split('/')
                                                  .last ??
                                              'your_code.py';
                                          _terminalPython = snap.data!.language
                                              .startsWith('python');
                                          final rosPath = snap
                                                  .data!.editableFilePath
                                                  ?.split('/') ??
                                              const <String>[];
                                          _terminalCommand = snap.data!.language
                                                      .contains('ros2') &&
                                                  rosPath.length >= 3
                                              ? 'ros2 run ${rosPath[1]} '
                                                  '${rosPath.last.replaceAll('.py', '')}'
                                              : null;
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
                                        final earlierDraft = _earlierDraft;
                                        final version = snap.data!.version;
                                        final workspace =
                                            AssignmentProjectWorkspace(
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
                                        if (earlierDraft == null) {
                                          return workspace;
                                        }
                                        return Column(
                                          children: [
                                            EarlierVersionDraftBanner(
                                              code: earlierDraft,
                                              onDismiss: () {
                                                unawaited(learningProgress
                                                    .dismissEarlierDraft(
                                                  widget.id,
                                                  version,
                                                ));
                                                setState(
                                                  () => _earlierDraft = null,
                                                );
                                              },
                                            ),
                                            Expanded(child: workspace),
                                          ],
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
                                if (_isRunning && _isRos2)
                                  const Ros2RunningNote(),
                                RunTerminalPanel(
                                  expanded: _terminalExpanded,
                                  height: _terminalHeight,
                                  running: _isRunning,
                                  lines: _terminalLines,
                                  requestError: _terminalRequestError,
                                  codeChanged: _terminalSimulatedCode == null
                                      ? _hasUnrunChanges
                                      : _terminalSimulatedCode != _code,
                                  onToggle: () => setState(
                                    () => _terminalExpanded =
                                        !_terminalExpanded,
                                  ),
                                  onResize: (value) =>
                                      setState(() => _terminalHeight = value),
                                  onClear: () => setState(() {
                                    _terminalLines = const [];
                                    _terminalRequestError = null;
                                  }),
                                  onOpenLine: _openLineInEditor,
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
                                      // Phones: the Simulation tab fills the panel.
                                      if (showSimTab)
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.all(
                                                AppSpacing.sm),
                                            child: _simPanel(phone: true),
                                          ),
                                        ),
                                      // Desktop: a square panel above the
                                      // instructions, like a dashboard tile.
                                      if (showDockedSim)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              AppSpacing.sm,
                                              AppSpacing.sm,
                                              AppSpacing.sm,
                                              0),
                                          child: _simCollapsed
                                              ? _simPanel(phone: false)
                                              : SizedBox(
                                                  height: rightConstraints
                                                          .maxHeight *
                                                      _simDockFraction,
                                                  child:
                                                      _simPanel(phone: false),
                                                ),
                                        ),
                                      // Drag to share the column with the
                                      // instructions.
                                      if (showDockedSim && !_simCollapsed)
                                        SimDockDivider(
                                          fraction: _simDockFraction,
                                          columnHeight:
                                              rightConstraints.maxHeight,
                                          onChanged: (value) => setState(
                                              () => _simDockFraction = value),
                                        ),
                                      // Instructions fill the rest of the panel.
                                      if (!showSimTab)
                                        Expanded(
                                          child: Container(
                                            key: const Key(
                                              'assignment-instructions-card',
                                            ),
                                            margin: useDesktopLayout
                                                ? EdgeInsets.fromLTRB(
                                                    showResizeHandle
                                                        ? 0
                                                        : AppSpacing.sm,
                                                    showDockedSim &&
                                                            !_simCollapsed
                                                        ? 0
                                                        : AppSpacing.sm,
                                                    AppSpacing.sm,
                                                    AppSpacing.sm,
                                                  )
                                                : EdgeInsets.zero,
                                            clipBehavior: Clip.antiAlias,
                                            decoration: workspaceCardDecoration(
                                              context,
                                              framed: useDesktopLayout,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surface,
                                            ),
                                            foregroundDecoration:
                                                useDesktopLayout
                                                    ? workspaceCardEdge()
                                                    : null,
                                            child: Column(
                                            children: [
                                              AssignmentPanelHeader(
                                                icon: LucideIcons.bookOpen,
                                                title: 'Instructions',
                                                subtitle:
                                                    'Review the scenario and task',
                                                sectionNav: _instructionNav,
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
                                                // A soft grey behind the white
                                                // section cards.
                                                child: ColoredBox(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerLow,
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
                                                          sectionNav:
                                                              _instructionNav,
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
                                              ),
                                            ],
                                          ),
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
                  if (showFloatingSim) _floatingSimPanel(bodyArea),
                ],
              ),
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
    this.sectionNav,
  });

  /// When given, the section tabs live in the panel header instead of above
  /// the sections, and follow the scroll position.
  final InstructionSectionNav? sectionNav;

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
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_followScroll);
      _position = position?..addListener(_followScroll);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_followScroll);
    super.dispose();
  }

  /// Marks the section whose top has passed the top of the panel.
  void _followScroll() {
    final nav = widget.sectionNav;
    final position = _position;
    if (nav == null || position == null) return;
    final viewport = position.context.storageContext.findRenderObject();
    if (viewport is! RenderBox) return;
    var current = 0;
    if (position.pixels >= position.maxScrollExtent - 4 &&
        position.maxScrollExtent > 0) {
      current = nav.sections.length - 1;
    } else {
      for (final (index, section) in nav.sections.indexed) {
        final box = section.target.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached) continue;
        final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
        if (top <= 72) current = index;
      }
    }
    nav.select(current);
  }

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
    final nav = widget.sectionNav;
    if (nav != null) {
      final entries = [
        InstructionSection('Scenario', _scenario),
        if (sections.task.isNotEmpty) InstructionSection('Your task', _task),
        if (sections.support.isNotEmpty)
          InstructionSection('Rules & scoring', _support),
      ];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) nav.setSections(entries);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (nav == null) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            _sectionLink('Scenario', _scenario),
            if (sections.task.isNotEmpty) _sectionLink('Your task', _task),
            if (sections.support.isNotEmpty)
              _sectionLink('Rules & scoring', _support),
          ]),
          const SizedBox(height: 12),
        ],
        SizedBox(key: _scenario),
        _InstructionSectionCard(
          key: const Key('instruction-scenario-section'),
          icon: LucideIcons.compass,
          title: 'Scenario',
          subtitle: 'Understand the environment and objective',
          html: sections.scenario,
        ),
        if (sections.task.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(key: _task),
          _InstructionSectionCard(
            key: const Key('instruction-task-section'),
            icon: LucideIcons.circleCheckBig,
            title: 'Your task',
            subtitle: 'What your solution needs to do',
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
            icon: LucideIcons.lightbulb,
            title: 'Rules, scoring, and checks',
            subtitle: 'Rules, scoring, given data, and hints',
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
// The path is made relative so it resolves under an API base URL that has a
// path prefix, such as https://rpl.ponkoj.com/api/.
String versionAssignmentImages(String html, int version) {
  return html.replaceAllMapped(
    RegExp(r'''(<img\b[^>]*\bsrc\s*=\s*)(["'])([^"']+)\2''',
        caseSensitive: false),
    (match) {
      final uri = Uri.tryParse(match[3]!);
      if (uri == null || !RegExp(r'^/?images/\d+$').hasMatch(uri.path)) {
        return match[0]!;
      }
      final updated = uri.replace(path: uri.path.replaceFirst(RegExp('^/'), ''), queryParameters: {
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
    r'<p><strong(?:\s[^>]*)?>\s*(Scenario|Given Data|Task|Questions?|Hints?|Assumptions?|Solution|Rules|Scope and scoring|How scoring works|Safety requirements|Safety and recovery requirements|What Run Tests checks|Before you run the tests):?\s*</strong></p>',
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

      // The rules card gathers several named parts (Rules, Hints, How
      // scoring works, ...), so every one keeps its own heading.
      if (buffers[destination]!.isNotEmpty || destination == 'support') {
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
                    icon: const Icon(LucideIcons.x),
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
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.border),
          boxShadow: appCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconTile(icon: icon, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandDark,
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
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandDark)),
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
                customStylesBuilder: instructionHeadingStyles,
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

String _cssHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Instruction subheadings ("What Run Tests checks", "How scoring works",
/// h3/h4) in the brand colour, so they stand apart from the body text. A
/// subheading is a paragraph whose only content is bold text.
Map<String, String>? instructionHeadingStyles(dom.Element element) {
  final heading = {
    'color': _cssHex(AppColors.brandDark),
    'font-weight': '700',
  };
  final tag = element.localName;
  if (tag == 'h2' || tag == 'h3' || tag == 'h4') return heading;
  if (tag == 'strong' || tag == 'b') {
    final parent = element.parent;
    if (parent != null &&
        parent.localName == 'p' &&
        parent.children.length == 1 &&
        parent.text.trim() == element.text.trim()) {
      return {...heading, 'font-size': '1.08em'};
    }
  }
  return null;
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
        icon: const Icon(LucideIcons.eye),
        title: const Text('Show solution approach?'),
        content: const Text(
          'The solution approach will be shown and this assignment will be '
          'marked as Solution viewed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            key: const Key('confirm-solution-reveal-button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Show solution approach'),
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
                      LucideIcons.eye,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Solution approach',
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
                      LucideIcons.eyeOff,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Solution approach',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            canReveal
                                ? 'Hidden until you choose to show it'
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
                  style: const ButtonStyle(backgroundBuilder: plainButtonBackground),
                  key: const Key('reveal-solution-button'),
                  onPressed: canReveal ? () => _requestReveal(context) : null,
                  icon: Icon(
                    canReveal ? LucideIcons.eye : LucideIcons.lock,
                  ),
                  label: Text(
                    canReveal
                        ? 'Show solution approach'
                        : 'Complete one test run first',
                  ),
                ),
              ],
            ),
    );
  }
}

/// Background of a workspace panel; on desktop it is a rounded card with a
/// light shadow, separated from the next panel by the grey page.
BoxDecoration workspaceCardDecoration(
  BuildContext context, {
  required bool framed,
  required Color color,
}) =>
    BoxDecoration(
      color: color,
      borderRadius: framed ? BorderRadius.circular(AppRadii.md) : null,
      boxShadow: framed ? appCardShadow : null,
    );

/// The card's visible edge, drawn over the content so it is never hidden.
BoxDecoration workspaceCardEdge() => BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadii.md),
      border: Border.all(color: AppColors.border),
    );

/// One instruction section a header tab scrolls to.
class InstructionSection {
  const InstructionSection(this.label, this.target);
  final String label;
  final GlobalKey target;
}

/// The instruction sections and which one is in view, shared by the
/// Instructions header tabs and the scrolling instructions.
class InstructionSectionNav extends ChangeNotifier {
  List<InstructionSection> sections = const [];
  int current = 0;

  void setSections(List<InstructionSection> value) {
    final same = value.length == sections.length &&
        [for (var i = 0; i < value.length; i++)
          value[i].label == sections[i].label &&
              value[i].target == sections[i].target].every((x) => x);
    if (same) return;
    sections = value;
    if (current >= sections.length) current = 0;
    notifyListeners();
  }

  void select(int index) {
    if (index == current) return;
    current = index;
    notifyListeners();
  }

  void jumpTo(int index) {
    select(index);
    final target = sections[index].target.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target,
          duration: const Duration(milliseconds: 250));
    }
  }
}

class AssignmentPanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isFocused;
  final VoidCallback? onFocusToggle;

  /// Section tabs shown in this header row, in place of the subtitle.
  final InstructionSectionNav? sectionNav;

  const AssignmentPanelHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.isFocused = false,
    this.onFocusToggle,
    this.sectionNav,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // One compact header line shared with the other panels.
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: PanelTitleRow(
        // With section tabs the title keeps its width and the tabs fill the
        // rest of the row.
        title: title,
        icon: icon,
        subtitle: sectionNav == null ? subtitle : null,
        fillTitle: sectionNav != null,
        actions: [
          if (sectionNav case final nav?)
            Expanded(
              child: ListenableBuilder(
                listenable: nav,
                builder: (context, _) => nav.sections.isEmpty
                    ? const SizedBox.shrink()
                    : SingleChildScrollView(
                        key: const Key('instruction-section-tabs'),
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(left: 12),
                        child: PillTabBar(compact: true, tabs: [
                          for (final (index, section) in nav.sections.indexed)
                            PillTabData(
                              key: Key('instruction-tab-$index'),
                              label: section.label,
                              selected: nav.current == index,
                              onTap: () => nav.jumpTo(index),
                            ),
                        ]),
                      ),
              ),
            ),
          if (onFocusToggle != null)
            IconButton(
              key: Key('focus-${title.toLowerCase()}-button'),
              tooltip: isFocused ? 'Restore workspace' : 'Focus $title',
              onPressed: onFocusToggle,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                isFocused
                    ? LucideIcons.minimize2
                    : LucideIcons.maximize2,
                size: 20,
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
  /// Replay the node in the 2D robot world; null when the assignment has none.
  final VoidCallback? onSimulate;
  final bool isSimulating;
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
    this.onSimulate,
    this.isSimulating = false,
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
      height: 60,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // A narrow editor panel keeps room for the tools with an icon-only
          // Simulate button.
          LayoutBuilder(builder: (context, constraints) {
            final compactSimulate = constraints.maxWidth < 760;
            return Row(
            children: [
              Tooltip(
                message: 'Edit the starter code, then run the tests',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.code,
                        size: 18,
                        color: theme.colorScheme.primary,
                        semanticLabel: compactSimulate ? 'Python editor' : null),
                    // A narrow panel keeps the room for its tools.
                    if (!compactSimulate) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Python editor',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28, child: VerticalDivider(width: 20)),
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
                          icon: LucideIcons.save,
                          label: 'Save draft',
                          shortcut: 'Ctrl+S / Ctrl+Alt+D',
                          onPressed: onSave,
                        ),
                        toolButton(
                          keyName: 'find',
                          icon: LucideIcons.search,
                          label: 'Find',
                          shortcut: 'Ctrl+F / Ctrl+Alt+Q',
                          onPressed: onSearch,
                        ),
                        toolButton(
                          keyName: 'replace',
                          icon: LucideIcons.replace,
                          label: 'Replace',
                          shortcut: 'Ctrl+H / Ctrl+Alt+W',
                          onPressed: onReplace,
                        ),
                        toolButton(
                          keyName: 'format',
                          icon: LucideIcons.wandSparkles,
                          label: 'Format Python',
                          shortcut: 'Shift+Alt+F / Ctrl+Shift+I',
                          onPressed: isRunning ? null : onFormat,
                        ),
                        toolButton(
                          keyName: 'restore',
                          icon: LucideIcons.rotateCcw,
                          label: 'Restore starter code',
                          shortcut: 'Ctrl+Alt+R',
                          onPressed: isRunning ? null : onReset,
                        ),
                        const SizedBox(
                            height: 28, child: VerticalDivider(width: 18)),
                        toolButton(
                          keyName: 'font-down',
                          icon: LucideIcons.aArrowDown,
                          label: 'Decrease editor font',
                          shortcut: 'Ctrl+- / Ctrl+Alt+1',
                          onPressed: fontSize > 12 ? onDecreaseFont : null,
                        ),
                        toolButton(
                          keyName: 'font-up',
                          icon: LucideIcons.aArrowUp,
                          label: 'Increase editor font',
                          shortcut: 'Ctrl+= / Ctrl+Alt+2',
                          onPressed: fontSize < 22 ? onIncreaseFont : null,
                        ),
                        const SizedBox(
                            height: 28, child: VerticalDivider(width: 18)),
                        toolButton(
                          keyName: 'reference',
                          icon: LucideIcons.fileCode,
                          label: 'Names in the starter code',
                          shortcut: 'Ctrl+Alt+A',
                          onPressed: onShowApiReference,
                        ),
                        toolButton(
                          keyName: 'shortcuts',
                          icon: LucideIcons.keyboard,
                          label: 'Keyboard shortcuts',
                          shortcut: 'F1 / Ctrl+Alt+K',
                          onPressed: onShowShortcuts,
                        ),
                        toolButton(
                          keyName: 'theme',
                          icon: editorDarkMode
                              ? LucideIcons.sun
                              : LucideIcons.moon,
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
              if (saveState != DraftSaveState.idle)
                Tooltip(
                  message: switch (saveState) {
                    DraftSaveState.saving => 'Saving draft',
                    DraftSaveState.saved => 'Draft saved',
                    DraftSaveState.sessionSaved =>
                      'Draft saved for this session; refresh resets it',
                    DraftSaveState.failed =>
                      'Cloud save failed. A local fallback remains available.',
                    DraftSaveState.outdated =>
                      'Assignment updated. Reopen it; your code is kept on '
                      'this device to copy across.',
                    DraftSaveState.idle => '',
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: Icon(
                      switch (saveState) {
                        DraftSaveState.saving => LucideIcons.refreshCw,
                        DraftSaveState.saved => LucideIcons.cloudCheck,
                        DraftSaveState.sessionSaved => LucideIcons.save,
                        DraftSaveState.failed => LucideIcons.cloudOff,
                        DraftSaveState.outdated => LucideIcons.history,
                        DraftSaveState.idle => LucideIcons.cloud,
                      },
                      key: const Key('draft-save-state-icon'),
                      size: 20,
                      color: saveState == DraftSaveState.failed ||
                              saveState == DraftSaveState.outdated
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
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
                        ? LucideIcons.minimize2
                        : LucideIcons.maximize2,
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
                    icon: const Icon(LucideIcons.flaskConical, size: 20),
                  )
                else
                  Tooltip(
                    message: 'Call your function with your own inputs. '
                        'Not graded or saved.',
                    child: OutlinedButton.icon(
                      key: const Key('try-inputs-button'),
                      onPressed: isRunning ? null : onTryInputs,
                      icon: const Icon(LucideIcons.flaskConical, size: 18),
                      label: const Text('Try inputs'),
                    ),
                  ),
              ],
              if (onSimulate != null) ...[
                const SizedBox(width: AppSpacing.xs),
                if (compactSimulate)
                  IconButton.outlined(
                    key: const Key('simulate-button'),
                    tooltip: isSimulating
                        ? 'Simulating…'
                        : 'Simulate: watch your node drive the robot. Not graded.',
                    onPressed: isRunning || isSimulating ? null : onSimulate,
                    icon: isSimulating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.bot, size: 20),
                  )
                else
                  Tooltip(
                    message: 'Watch your node drive the robot in a 2D world. '
                        'Not graded.',
                    child: OutlinedButton.icon(
                      key: const Key('simulate-button'),
                      onPressed: isRunning || isSimulating ? null : onSimulate,
                      icon: isSimulating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.bot, size: 18),
                      label: Text(isSimulating ? 'Simulating…' : 'Simulate'),
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
                        : const Icon(LucideIcons.play, size: 20),
                    label: Text(isRunning ? 'Running…' : 'Run tests'),
                  ),
                ),
              ),
            ],
          );
          }),
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
            files: files,
            onFileSelected: onFileSelected,
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
                  textStyle: TextStyle(
                    fontFamily: 'Courier-New',
                    fontSize: fontSize,
                    shadows: palette.thickenStrokes
                        ? [
                            Shadow(
                              color: palette.foreground,
                              offset: const Offset(0.5, 0),
                            ),
                          ]
                        : null,
                  ),
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
            final style = TextStyle(
              color: palette.lineNumber,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            );
            final path = selectedPath ?? '';
            final language = path.endsWith('.xml')
                ? 'XML'
                : path.endsWith('.cfg')
                    ? 'Config'
                    : path.isEmpty || path.endsWith('.py')
                        ? 'Python'
                        : 'Plain text';
            // Position on the left, file details on the right, like the
            // status bar of a code editor.
            return Container(
              key: const Key('editor-position-status'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: palette.background,
                border: Border(
                  top: BorderSide(
                    color: palette.lineNumber.withValues(alpha: 0.25),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text('Ln $line, Col $column', style: style),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      'Indent level ${editorIndentLevel(lineText)}',
                      style: style,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  Text(language, style: style),
                  const SizedBox(width: 16),
                  Text('Spaces: 4', style: style),
                ],
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
              // A one-line picker leaves room to edit on a phone; the full
              // list took most of the height above the terminal.
              ProjectFilePicker(
                files: files,
                selectedPath: selectedPath,
                onFileSelected: onFileSelected,
              ),
              Expanded(child: editor),
            ],
          );
        }
        // The explorer is a narrow icon rail that slides open over the
        // editor, so the editor keeps its width when the names are shown.
        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AssignmentProjectExplorer.railWidth,
              ),
              child: editor,
            ),
            Positioned(left: 0, top: 0, bottom: 0, child: explorer),
          ],
        );
      },
    );
  }
}

/// Narrow-screen file chooser with every project file, marked editable or
/// read only.
class ProjectFilePicker extends StatelessWidget {
  const ProjectFilePicker({
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
    final current = files.any((file) => file.path == selectedPath)
        ? selectedPath
        : files.first.path;
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('project-file-picker'),
            value: current,
            isExpanded: true,
            icon: const Icon(LucideIcons.chevronsUpDown),
            items: [
              for (final file in files)
                DropdownMenuItem(
                  value: file.path,
                  child: Row(
                    children: [
                      Icon(
                        file.editable
                            ? LucideIcons.pencil
                            : LucideIcons.lock,
                        size: 16,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          file.path,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (path) {
              if (path == null || path == current) return;
              onFileSelected(files.firstWhere((file) => file.path == path));
            },
          ),
        ),
      ),
    );
  }
}

/// Project files as a narrow rail of icons, each badged with a lock (read
/// only) or a pencil (editable). Hovering or focusing the rail slides it open
/// over the editor to show every file name; the header pin keeps it open,
/// which is also how touch screens without hover open it.
class AssignmentProjectExplorer extends StatefulWidget {
  const AssignmentProjectExplorer({
    super.key,
    required this.files,
    required this.selectedPath,
    required this.onFileSelected,
  });

  static const double railWidth = 52;
  static const double openWidth = 280;

  final List<AssignmentProjectFile> files;
  final String? selectedPath;
  final ValueChanged<AssignmentProjectFile> onFileSelected;

  @override
  State<AssignmentProjectExplorer> createState() =>
      _AssignmentProjectExplorerState();
}

class _AssignmentProjectExplorerState extends State<AssignmentProjectExplorer> {
  bool _hovered = false;
  bool _focused = false;
  bool _pinned = false;

  bool get _open => _hovered || _focused || _pinned;

  /// Folders the student has closed; every folder starts open.
  final Set<String> _closedFolders = {};

  /// Folders first, then files, each sorted by name, like a code editor.
  List<_ProjectTreeRow> _treeRows() {
    final root = _ProjectFolder('');
    for (final file in widget.files) {
      final segments = file.path.split('/');
      var folder = root;
      for (var i = 0; i < segments.length - 1; i++) {
        final path = segments.sublist(0, i + 1).join('/');
        folder = folder.folders.putIfAbsent(
          segments[i],
          () => _ProjectFolder(path),
        );
      }
      folder.files.add(file);
    }
    final rows = <_ProjectTreeRow>[];
    void visit(_ProjectFolder folder, int depth) {
      final names = folder.folders.keys.toList()..sort();
      for (final name in names) {
        final child = folder.folders[name]!;
        rows.add(_ProjectTreeRow(depth: depth, name: name, folder: child));
        if (!_closedFolders.contains(child.path)) {
          visit(child, depth + 1);
        }
      }
      String fileName(AssignmentProjectFile file) => file.path.split('/').last;
      final files = [...folder.files]
        ..sort((a, b) => fileName(a).compareTo(fileName(b)));
      for (final file in files) {
        rows.add(
          _ProjectTreeRow(
            depth: depth,
            name: file.path.split('/').last,
            file: file,
          ),
        );
      }
    }

    visit(root, 0);
    return rows;
  }

  Widget _treeRow(ThemeData theme, _ProjectTreeRow row) {
    final scheme = theme.colorScheme;
    final file = row.file;
    final folder = row.folder;
    final selected = file != null && file.path == widget.selectedPath;
    final folderOpen =
        folder != null && !_closedFolders.contains(folder.path);
    const indent = 14.0;
    final contentColor =
        selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    final Widget leading;
    if (folder != null) {
      leading = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            folderOpen
                ? LucideIcons.chevronDown
                : LucideIcons.chevronRight,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 2),
          Icon(
            folderOpen ? LucideIcons.folderOpen : LucideIcons.folder,
            size: 18,
            color: scheme.primary,
          ),
        ],
      );
    } else {
      final badgeColor = file!.editable ? scheme.primary : scheme.outline;
      leading = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 20),
          Icon(projectFileIcon(row.name), size: 18, color: contentColor),
        ],
      );
      return _treeRowFrame(
        theme,
        key: Key('project-file-${file.path}'),
        depth: row.depth,
        indent: indent,
        selected: selected,
        semantics: '${file.path}, ${file.editable ? 'editable' : 'read only'}',
        onTap: () => widget.onFileSelected(file),
        children: [
          leading,
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              row.name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: selected ? FontWeight.w700 : null,
                color: selected ? scheme.onPrimaryContainer : null,
              ),
            ),
          ),
          Tooltip(
            message: file.editable ? 'Editable' : 'Read only',
            child: Icon(
              file.editable ? LucideIcons.pencil : LucideIcons.lock,
              size: 14,
              color: badgeColor,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      );
    }
    return _treeRowFrame(
      theme,
      key: Key('project-folder-${folder.path}'),
      depth: row.depth,
      indent: indent,
      selected: false,
      semantics:
          'Folder ${folder.path}, ${folderOpen ? 'expanded' : 'collapsed'}',
      onTap: () => setState(() {
        if (!_closedFolders.remove(folder.path)) {
          _closedFolders.add(folder.path);
        }
      }),
      children: [
        leading,
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            row.name,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// One tree line: indent guides for each level, then the row content,
  /// laid out at the open width so it never overflows while sliding open.
  Widget _treeRowFrame(
    ThemeData theme, {
    required Key key,
    required int depth,
    required double indent,
    required bool selected,
    required String semantics,
    required VoidCallback onTap,
    required List<Widget> children,
  }) {
    final scheme = theme.colorScheme;
    return Semantics(
      label: semantics,
      button: true,
      selected: selected,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Material(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: SizedBox(
              height: 32,
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: AssignmentProjectExplorer.openWidth - 9,
                maxWidth: AssignmentProjectExplorer.openWidth - 9,
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    for (var level = 0; level < depth; level++)
                      SizedBox(
                        width: indent,
                        height: 32,
                        child: Center(
                          child: VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: scheme.outlineVariant,
                          ),
                        ),
                      ),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final open = _open;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) => setState(() => _focused = value),
        child: AnimatedContainer(
          key: const Key('project-file-explorer'),
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: open
              ? AssignmentProjectExplorer.openWidth
              : AssignmentProjectExplorer.railWidth,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(right: BorderSide(color: scheme.outlineVariant)),
            boxShadow: open && !_pinned
                ? [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(3, 0),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(theme, open),
              Expanded(
                child: open
                    ? Builder(
                        builder: (context) {
                          final rows = _treeRows();
                          return ListView.builder(
                            key: const Key('assignment-project-file-tree'),
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            itemCount: rows.length,
                            itemBuilder: (context, index) =>
                                _treeRow(theme, rows[index]),
                          );
                        },
                      )
                    : ListView.builder(
                        key: const Key('assignment-project-file-tree'),
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        itemCount: widget.files.length,
                        itemBuilder: (context, index) =>
                            _fileRow(theme, widget.files[index], open),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, bool open) {
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      toggled: _pinned,
      label: _pinned ? 'Unpin project files' : 'Pin project files open',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('project-files-pin'),
        onTap: () => setState(() => _pinned = !_pinned),
        // Laid out at the open width and clipped, so the header never
        // overflows while the rail is sliding open or shut.
        child: SizedBox(
          height: 44,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: AssignmentProjectExplorer.openWidth - 1,
            maxWidth: AssignmentProjectExplorer.openWidth - 1,
            child: Row(
              children: [
                SizedBox(
                  width: AssignmentProjectExplorer.railWidth - 1,
                  child: Icon(
                    LucideIcons.folderTree,
                    size: 20,
                    color: scheme.primary,
                  ),
                ),
                Expanded(
                  child: Text(
                    'PROJECT FILES (${widget.files.length})',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                if (open)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Icon(
                      _pinned ? LucideIcons.pinOff : LucideIcons.pin,
                      size: 16,
                      color: _pinned ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileRow(ThemeData theme, AssignmentProjectFile file, bool open) {
    final scheme = theme.colorScheme;
    final selected = file.path == widget.selectedPath;
    final segments = file.path.split('/');
    final name = segments.last;
    final folder = segments.length > 1
        ? segments.sublist(0, segments.length - 1).join('/')
        : '';
    final iconColor =
        selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    final badgeColor = file.editable ? scheme.primary : scheme.outline;
    return Semantics(
      label: '${file.path}, ${file.editable ? 'editable' : 'read only'}',
      button: true,
      selected: selected,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Material(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: Key('project-file-${file.path}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => widget.onFileSelected(file),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  SizedBox(
                    width: AssignmentProjectExplorer.railWidth - 9,
                    child: Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(projectFileIcon(name), size: 22, color: iconColor),
                          Positioned(
                            right: -6,
                            bottom: -5,
                            child: Container(
                              key: Key('project-file-badge-${file.path}'),
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: badgeColor),
                              ),
                              child: Icon(
                                file.editable
                                    ? LucideIcons.pencil
                                    : LucideIcons.lock,
                                size: 10,
                                color: badgeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: AnimatedOpacity(
                      opacity: open ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: selected ? FontWeight.w700 : null,
                              color:
                                  selected ? scheme.onPrimaryContainer : null,
                            ),
                          ),
                          if (folder.isNotEmpty)
                            Text(
                              folder,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
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
        ),
      ),
    );
  }
}

class _ProjectFolder {
  _ProjectFolder(this.path);

  final String path;
  final Map<String, _ProjectFolder> folders = {};
  final List<AssignmentProjectFile> files = [];
}

class _ProjectTreeRow {
  const _ProjectTreeRow({
    required this.depth,
    required this.name,
    this.folder,
    this.file,
  });

  final int depth;
  final String name;
  final _ProjectFolder? folder;
  final AssignmentProjectFile? file;
}

/// Icon for a project file, by its extension.
IconData projectFileIcon(String name) {
  if (name.endsWith('.py')) return LucideIcons.code;
  if (name.endsWith('.xml')) return LucideIcons.braces;
  if (name.endsWith('.cfg')) return LucideIcons.slidersHorizontal;
  return LucideIcons.file;
}

/// File tabs above the editor, like a code editor's tab strip. Editable files
/// always have a tab; a read-only file opened from the tree shows as a
/// preview tab that can be closed. The right side shows the open file's
/// state (Editable or Read only) and the line to check after an error.
class ProjectFileStatusBar extends StatelessWidget {
  const ProjectFileStatusBar({
    super.key,
    required this.path,
    required this.editable,
    this.diagnosticLine,
    this.files = const [],
    this.onFileSelected,
  });

  final String path;
  final bool editable;
  final int? diagnosticLine;
  final List<AssignmentProjectFile> files;
  final ValueChanged<AssignmentProjectFile>? onFileSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editableFiles = files.where((file) => file.editable).toList();
    final tabs = <AssignmentProjectFile>[
      ...editableFiles,
      if (!editableFiles.any((file) => file.path == path))
        files.firstWhere(
          (file) => file.path == path,
          orElse: () => AssignmentProjectFile(path: path, editable: editable),
        ),
    ];
    final fallback = editableFiles.isEmpty ? null : editableFiles.first;
    final select = onFileSelected;
    return Container(
      key: const Key('project-file-status-bar'),
      height: 40,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final file in tabs)
                  _FileTab(
                    file: file,
                    active: file.path == path,
                    onTap: select == null ? null : () => select(file),
                    onClose: !file.editable && fallback != null && select != null
                        ? () => select(fallback)
                        : null,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                if (diagnosticLine != null) ...[
                  StatusPill(
                    key: const Key('editor-diagnostic-line'),
                    label: 'Check line $diagnosticLine',
                    color: scheme.error,
                    icon: LucideIcons.circleAlert,
                    size: PillSize.small,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                StatusPill(
                  label: editable ? 'Editable' : 'Read only',
                  color: editable ? scheme.primary : scheme.onSurfaceVariant,
                  icon: editable ? LucideIcons.pencil : LucideIcons.lock,
                  size: PillSize.small,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileTab extends StatelessWidget {
  const _FileTab({
    required this.file,
    required this.active,
    this.onTap,
    this.onClose,
  });

  final AssignmentProjectFile file;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = file.path.split('/').last;
    final color = active ? scheme.onSurface : scheme.onSurfaceVariant;
    final readOnlyNote = file.editable ? '' : ', read only';
    return Tooltip(
      message: file.path + readOnlyNote,
      child: Semantics(
        button: true,
        selected: active,
        label: '$name tab$readOnlyNote',
        excludeSemantics: true,
        child: Material(
          color: active ? scheme.surface : Colors.transparent,
          child: InkWell(
            key: Key('editor-tab-${file.path}'),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: active ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                  right: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Icon(projectFileIcon(name), size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    name,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      fontStyle:
                          file.editable ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                  if (!file.editable) ...[
                    const SizedBox(width: 4),
                    Icon(LucideIcons.lock, size: 12, color: color),
                  ],
                  if (onClose != null)
                    IconButton(
                      key: Key('editor-tab-close-${file.path}'),
                      tooltip: 'Close $name',
                      onPressed: onClose,
                      icon: const Icon(LucideIcons.x, size: 14),
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      padding: EdgeInsets.zero,
                    )
                  else
                    const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
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
            // Transparent so the grey page shows between the two cards.
            color: Colors.transparent,
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

  /// The course number students see; null shows the ID.
  final int? displayNumber;

  /// Progress state label, such as Not started or Attempted.
  final String status;

  /// Percentage of the latest scored run; null before any run.
  final int? lastScore;

  /// The code was edited after [lastScore], so it is the previous score.
  final bool codeChangedSinceScore;
  final bool solutionViewed;
  final bool feedbackEnabled;

  /// False when the server has no AI provider: the switch stays off and
  /// disabled.
  final bool aiTutorAvailable;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final VoidCallback onResultsOpen;
  final ValueChanged<bool> onFeedbackChanged;

  const AssignmentPageHeader({
    super.key,
    required this.title,
    required this.assignmentId,
    this.displayNumber,
    required this.status,
    this.lastScore,
    this.checks,
    this.codeChangedSinceScore = false,
    this.solutionViewed = false,
    required this.feedbackEnabled,
    this.aiTutorAvailable = true,
    required this.onBack,
    required this.onHome,
    required this.onResultsOpen,
    required this.onFeedbackChanged,
    this.aiTutorMessage = aiTutorUnavailableMessage,
  });

  /// Why the AI tutor is unavailable, shown when it is.
  final String aiTutorMessage;

  /// The latest run's checks, drawn as a small meter beside the score.
  final CheckSummary? checks;

  String get _displayTitle {
    final prefix = 'Assignment $assignmentId:';
    return title.startsWith(prefix)
        ? title.substring(prefix.length).trim()
        : title;
  }

  Widget _withUnavailableTooltip({
    required bool show,
    required Widget child,
  }) =>
      show ? Tooltip(message: aiTutorMessage, child: child) : child;

  @override
  Size get preferredSize => const Size.fromHeight(82);

  (Color, Color) get _statusColors => switch (status) {
        'Completed' => (AppColors.successContainer, AppColors.success),
        'Attempted' => (const Color(0xFFDFE8F5), const Color(0xFF1F4277)),
        'In progress' => (const Color(0xFFDDEFF2), const Color(0xFF0F4C5C)),
        _ => (const Color(0xFFEDF1F5), AppColors.inkMuted),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final session = currentSession;
    final (statusBackground, statusForeground) = _statusColors;

    Widget chip(String text, Color background, Color foreground,
            {Key? key, IconData? icon}) =>
        Container(
          key: key,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: foreground),
              const SizedBox(width: 4),
            ],
            Text(text,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: foreground, fontWeight: FontWeight.w700)),
          ]),
        );

    final statusCards = [
      chip(status, statusBackground, statusForeground,
          key: const Key('header-status-chip')),
      if (solutionViewed) ...[
        const SizedBox(width: 6),
        chip('Solution viewed', AppColors.warningContainer,
            AppColors.performanceMid,
            key: const Key('header-solution-viewed'),
            icon: LucideIcons.eye),
      ],
    ];

    final scoreCard = lastScore == null
        ? null
        : Container(
            key: const Key('header-score-card'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                text: codeChangedSinceScore
                    ? 'Previous score (code changed)  '
                    : 'Last score  ',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.inkMuted),
              ),
              TextSpan(
                text: '$lastScore%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: performanceColor(lastScore!),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ])),
          );

    final checkMeter = checks == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 10),
            child: ChecksMeter(
              key: const Key('header-checks-meter'),
              passed: checks!.passed,
              total: checks!.total,
              onDark: true,
            ),
          );

    return FloatingAppBar(barHeight: 64, AppBar(
      flexibleSpace: const BrandHeaderGradient(),
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      backgroundColor: theme.colorScheme.primary,
      leadingWidth: wide ? 60 : 50,
      leading: Center(
        child: HeaderIconButton(
          tooltip: 'Back to assignments',
          onPressed: onBack,
          icon: LucideIcons.arrowLeft,
        ),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            ),
            child: Text(
              (displayNumber ?? assignmentId).toString().padLeft(2, '0'),
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(width: wide ? 12 : AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // First row: the title, then progress and solution cards.
                Row(children: [
                  Flexible(
                    child: Text(
                      _displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(width: 8),
                    ...statusCards,
                  ],
                ]),
                // Second row: the score as its own card (and, on phones,
                // the status cards, which do not fit beside the title).
                if (scoreCard != null || checkMeter != null || !wide) ...[
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      if (!wide) ...statusCards,
                      if (!wide && scoreCard != null)
                        const SizedBox(width: 6),
                      if (scoreCard != null) scoreCard,
                      if (checkMeter != null) checkMeter,
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (wide)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: TextButton.icon(
              key: const Key('open-results-button'),
              onPressed: onResultsOpen,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                minimumSize: const Size(40, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                ),
              ),
              icon: const Icon(LucideIcons.clipboardCheck, size: 18),
              label: const Text('Results'),
            ),
          )
        else
          HeaderIconButton(
            key: const Key('open-results-button'),
            tooltip: 'Open results',
            onPressed: onResultsOpen,
            icon: LucideIcons.clipboardCheck,
          ),
        // On phones Back already returns to the assignment list, so the
        // title keeps the space a duplicate Home icon would take.
        if (wide)
          HeaderIconButton(
            key: const Key('assignment-home-button'),
            tooltip: 'Home',
            onPressed: onHome,
            icon: LucideIcons.house,
          ),
        // Only the TDD + AI feedback mode has an AI tutor to switch on.
        if (currentFeedbackMode.value.allowsAi)
          _withUnavailableTooltip(
            show: !aiTutorAvailable,
            child: AiToggle(
              key: const Key('header-ai-toggle'),
              value: aiTutorAvailable && feedbackEnabled,
              onChanged: aiTutorAvailable ? onFeedbackChanged : null,
            ),
          ),
        if (session != null)
          Padding(
            padding: EdgeInsets.only(left: 4, right: wide ? 12 : 8),
            child: AccountMenuButton(
              user: session.user,
              onLogout: session.onLogout,
              compact: !wide,
              avatarOnly: !wide,
            ),
          )
        else
          const SizedBox(width: AppSpacing.sm),
      ],
    ));
  }
}

/// The AI tutor switch as a small "AI" button: the sparkles move while it is
/// on, and the button fades while it is off.
class AiToggle extends StatefulWidget {
  const AiToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.onDark = true,
  });

  final bool value;

  /// True on the coloured page header; false on light panels.
  final bool onDark;

  /// Null when the course has no AI tutor available.
  final ValueChanged<bool>? onChanged;

  @override
  State<AiToggle> createState() => _AiToggleState();
}

class _AiToggleState extends State<AiToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AiToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  bool? _wasOn;

  /// Switching on plays a short burst of pulses; the button then stays lit.
  void _sync() {
    final on = widget.value;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (on && _wasOn == false && !reduceMotion) {
      unawaited(_burst());
    } else if (!on) {
      _pulse
        ..stop()
        ..value = 0;
    }
    _wasOn = on;
  }

  Future<void> _burst() async {
    for (var i = 0; i < 3 && mounted && widget.value; i++) {
      await _pulse.forward(from: 0).orCancel.catchError((_) {});
      if (!mounted || !widget.value) return;
      await _pulse.reverse().orCancel.catchError((_) {});
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.value;
    final enabled = widget.onChanged != null;
    final dark = widget.onDark;
    final ink = dark ? Colors.white : AppColors.brandDark;
    final fill = dark
        ? Colors.white.withValues(alpha: on ? 0.22 : 0.08)
        : (on ? AppColors.brandTint : Colors.white);
    final edge = dark
        ? Colors.white.withValues(alpha: on ? 0.55 : 0.18)
        : (on ? AppColors.brand : AppColors.border);
    final sparkle = on
        ? (dark ? const Color(0xFFFFE08A) : const Color(0xFFB7791F))
        : ink;
    return Semantics(
      label: 'AI',
      toggled: on,
      enabled: enabled,
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: on ? 'AI is on' : 'AI is off',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: on ? 1 : (enabled ? 0.55 : 0.35),
            child: Material(
              color: fill,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
                side: BorderSide(color: edge),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? () => widget.onChanged!(!on) : null,
                child: SizedBox(
                  height: 40,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) => Transform.rotate(
                          angle: (_pulse.value - 0.5) * 0.5,
                          child: Transform.scale(
                            scale: 1 + _pulse.value * 0.18,
                            child: child,
                          ),
                        ),
                        child: Icon(
                          LucideIcons.sparkles,
                          size: 18,
                          color: sparkle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'AI',
                        style: TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
    this.showSimulation = false,
  });

  /// Adds a Simulation tab for assignments with a robot replay.
  final bool showSimulation;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      key: const Key('assignment-workspace-navigation'),
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: [
        const NavigationDestination(
            icon: Icon(LucideIcons.code), label: 'Code'),
        const NavigationDestination(
          icon: Icon(LucideIcons.bookOpen),
          label: 'Instructions',
        ),
        if (showSimulation)
          const NavigationDestination(
            icon: Icon(LucideIcons.bot),
            label: 'Simulation',
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
                LucideIcons.circlePlay,
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
            Icon(LucideIcons.codeXml,
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
              style: const ButtonStyle(backgroundBuilder: plainButtonBackground),
              key: const Key('restore-starter-from-results'),
              onPressed: onRestore,
              icon: const Icon(LucideIcons.rotateCcw),
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
                LucideIcons.cloudOff,
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
                icon: const Icon(LucideIcons.refreshCw),
                label: const Text('Retry test run'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown beside a disabled AI switch when the server has no AI provider.
const aiTutorUnavailableMessage =
    'Not enabled for this course. Built-in hints still work.';

/// Status shown while a ROS 2 package builds and runs; Python runs are quick.
const ros2RunningMessage = 'Building and running your ROS 2 package. '
    'This usually takes about 15 seconds.';

class Ros2RunningNote extends StatelessWidget {
  const Ros2RunningNote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('ros2-running-note'),
        width: double.infinity,
        color: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                ros2RunningMessage,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SecureGraderLoadingState extends StatelessWidget {
  const SecureGraderLoadingState({super.key, this.ros2Package = false});

  /// True for ROS 2 assignments, whose package build takes noticeably longer.
  final bool ros2Package;

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
            if (ros2Package) ...[
              Text(
                ros2RunningMessage,
                key: const Key('ros2-grader-loading-note'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
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

class Feedback extends StatefulWidget {
  const Feedback({
    super.key,
    required this.data,
    this.aiTutorEnabled = false,
    this.tutorQuestionRequester,
    this.onWatchInSimulation,
    this.previousScore,
    this.errorLine,
    this.onGoToLine,
  });

  /// The score before this run; null on a first run.
  final int? previousScore;

  /// The line the run's error points at, if any.
  final int? errorLine;
  final ValueChanged<int>? onGoToLine;

  final UnittestFeedbackDto data;
  final bool aiTutorEnabled;
  final TutorQuestionRequester? tutorQuestionRequester;

  /// Opens the replay at the moment that shows a failed check's cause.
  final ValueChanged<String>? onWatchInSimulation;

  @override
  State<Feedback> createState() => _FeedbackState();
}

class _FeedbackState extends State<Feedback> {
  /// Passed checks stay folded while some still fail.
  bool _showPassed = false;
  final _hintKey = GlobalKey();

  @override
  void didUpdateWidget(covariant Feedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) _showPassed = false;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final aiTutorEnabled = widget.aiTutorEnabled;
    final tutorQuestionRequester = widget.tutorQuestionRequester;
    final onWatchInSimulation = widget.onWatchInSimulation;
    final passed = data.unittestPassResults.where((result) => result).length;
    final failed = data.unittestPassResults.length - passed;
    final total = passed + failed;
    final passRate = total > 0 ? (passed / total) * 100 : 0.0;
    final score = data.score.clamp(0, 100).toInt();
    // Points come from weighted checks; zero-weight checks are requirements.
    double? totalPoints;
    var earnedPoints = 0.0;
    var requirementChecks = 0;
    for (final (index, detail) in data.evidence.indexed) {
      final weight = detail.weight;
      if (weight == null) continue;
      totalPoints = (totalPoints ?? 0) + weight;
      final checkPassed = index < data.unittestPassResults.length &&
          data.unittestPassResults[index];
      earnedPoints += detail.earnedWeight ?? (checkPassed ? weight : 0);
      if (weight == 0) requirementChecks++;
    }
    final vars = data.testedVals.map((value) => value.toString()).toList();
    // Traditional accounts get the score and counts only (server-enforced).
    final resultsOnly = data.feedbackMode == FeedbackMode.traditional.wire;
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
    final failedCards = <Widget>[];
    final passedCards = <Widget>[];
    ({int number, String label, String message, String? hintKey})? firstFailed;
    for (final entry in orderedChecks) {
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
      if (!didPass && firstFailed == null) {
        firstFailed = (
          number: entry.key + 1,
          label: (detail?.label ?? '').isNotEmpty
              ? detail!.label
              : 'Check ${entry.key + 1}',
          message: feedback,
          hintKey: detail?.hintKey,
        );
      }
      (didPass ? passedCards : failedCards).add(_TestResultCard(
        checkNumber: entry.key + 1,
        passed: didPass,
        first: first,
        highlighted: highlighted,
        last: last,
        label: detail?.label,
        reason: detail?.reason,
        weight: detail?.weight,
        earnedWeight: detail?.earnedWeight,
        hintKey: detail?.hintKey,
        onWatch: onWatchInSimulation,
      ));
    }
    List<Widget> spaced(List<Widget> cards) => [
          for (final card in cards) ...[
            card,
            const SizedBox(height: AppSpacing.sm),
          ],
        ];

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
            earnedPoints: totalPoints == null ? null : earnedPoints,
            totalPoints: totalPoints,
            requirementChecks: requirementChecks,
            previousScore: widget.previousScore,
          ),
          // With check details, the first failed check leads with ways to
          // act on it; otherwise a short next step.
          if (data.execSuccess && !resultsOnly && firstFailed != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _FixFirstCard(
              label: firstFailed.label,
              message: firstFailed.message,
              errorLine: widget.errorLine,
              onGoToLine: widget.onGoToLine,
              onWatch: onWatchInSimulation != null &&
                      SimFocus.forHint(firstFailed.hintKey, 0) != null
                  ? () => onWatchInSimulation(firstFailed!.hintKey!)
                  : null,
              onShowHint: showHint
                  ? () {
                      final target = _hintKey.currentContext;
                      if (target != null) {
                        Scrollable.ensureVisible(
                          target,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    }
                  : null,
            ),
          ] else if (failed > 0 || !data.execSuccess) ...[
            const SizedBox(height: AppSpacing.sm),
            _ResultNextStep(
              executionFailed: !data.execSuccess,
              resultsOnly: resultsOnly,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _TerminalOutput(data: data),
          if (showHint || tutorAvailable) ...[
            const SizedBox(height: AppSpacing.md),
            _TutorHintPanel(
              key: _hintKey,
              data: data,
              allowQuestions: tutorAvailable,
              useAiTutor: aiTutorEnabled,
              questionRequester: tutorQuestionRequester ?? askTutorQuestion,
            ),
          ],
          if (!resultsOnly) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              failed > 0 ? 'Test details · failed first' : 'Test details',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (failedCards.isEmpty && passedCards.isEmpty)
              Text(
                'No individual test details were returned.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            if (failedCards.isNotEmpty) ...[
              _CheckGroupHeader(
                key: const Key('checks-failed-group'),
                label: 'Needs attention',
                count: failedCards.length,
                color: Theme.of(context).colorScheme.error,
                icon: LucideIcons.circleX,
              ),
              ...spaced(failedCards),
            ],
            if (passedCards.isNotEmpty) ...[
              if (failedCards.isNotEmpty) const SizedBox(height: AppSpacing.xs),
              _CheckGroupHeader(
                key: const Key('checks-passed-group'),
                label: 'Passed',
                count: passedCards.length,
                color: AppColors.success,
                icon: LucideIcons.circleCheck,
              ),
              if (failedCards.isEmpty || _showPassed)
                ...spaced(passedCards)
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('show-passed-checks'),
                    onPressed: () => setState(() => _showPassed = true),
                    icon: const Icon(LucideIcons.chevronDown, size: 18),
                    label: Text(
                      'Show ${passedCards.length} passed '
                      '${passedCards.length == 1 ? 'check' : 'checks'}',
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The run's checks as a store record, or null when the run returned none.
CheckSummary? summarizeChecks(UnittestFeedbackDto data) {
  final total = data.unittestPassResults.length;
  if (total == 0) return null;
  final passed = data.unittestPassResults.where((result) => result).length;
  var nextFailing = '';
  // Traditional accounts see counts only, so no check name is kept.
  if (data.feedbackMode != FeedbackMode.traditional.wire) {
    for (var index = 0; index < total; index++) {
      if (data.unittestPassResults[index]) continue;
      final label =
          index < data.evidence.length ? data.evidence[index].label : '';
      nextFailing = label.isNotEmpty
          ? label
          : (index < data.unittestFeedback.length
              ? data.unittestFeedback[index]
              : '');
      break;
    }
  }
  return CheckSummary(passed: passed, total: total, nextFailing: nextFailing);
}

/// The first failed check, with the quickest ways to act on it.
class _FixFirstCard extends StatelessWidget {
  const _FixFirstCard({
    required this.label,
    required this.message,
    this.errorLine,
    this.onGoToLine,
    this.onWatch,
    this.onShowHint,
  });

  final String label;
  final String message;
  final int? errorLine;
  final ValueChanged<int>? onGoToLine;
  final VoidCallback? onWatch;
  final VoidCallback? onShowHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = errorLine;
    return Container(
      key: const Key('fix-first-card'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(LucideIcons.target, size: 16, color: AppColors.brand),
            const SizedBox(width: 6),
            Text(
              'FIX THIS FIRST',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.brand,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w800,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (message.isNotEmpty && message != label) ...[
            const SizedBox(height: 4),
            Text(
              message,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ],
          if ((line != null && onGoToLine != null) ||
              onWatch != null ||
              onShowHint != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
              if (line != null && onGoToLine != null)
                OutlinedButton.icon(
                  key: const Key('fix-first-line'),
                  onPressed: () => onGoToLine!(line),
                  icon: const Icon(LucideIcons.textCursor, size: 16),
                  label: Text('Go to line $line'),
                ),
              if (onWatch != null)
                OutlinedButton.icon(
                  key: const Key('fix-first-watch'),
                  onPressed: onWatch,
                  icon: const Icon(LucideIcons.bot, size: 16),
                  label: const Text('Watch in simulation'),
                ),
              if (onShowHint != null)
                FilledButton.tonalIcon(
                  key: const Key('fix-first-hint'),
                  onPressed: onShowHint,
                  icon: const Icon(LucideIcons.lightbulb, size: 16),
                  label: const Text('Show a hint'),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// A heading for one group of checks, with how many it holds.
class _CheckGroupHeader extends StatelessWidget {
  const _CheckGroupHeader({
    super.key,
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  final String label;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      label: '$label, $count',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Divider(color: color.withValues(alpha: 0.2))),
        ]),
      ),
    );
  }
}

class _ResultNextStep extends StatelessWidget {
  const _ResultNextStep({
    required this.executionFailed,
    this.resultsOnly = false,
  });

  final bool executionFailed;
  final bool resultsOnly;

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
          Icon(LucideIcons.lightbulb,
              size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              executionFailed
                  ? 'Next step: resolve the execution error below, then run the tests again.'
                  : resultsOnly
                      ? 'Next step: compare your code with the task instructions, then run the tests again.'
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
                  check ? LucideIcons.check : LucideIcons.circleX,
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
                Icon(LucideIcons.circleCheck, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  "Passed: $passed",
                  style: const TextStyle(color: Colors.green),
                ),
                const SizedBox(width: 16),
                Icon(LucideIcons.circleX, color: Colors.red),
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
                        LucideIcons.lightbulb,
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
    this.earnedPoints,
    this.totalPoints,
    this.requirementChecks = 0,
    this.previousScore,
  });

  /// The score before this run; null on a first run.
  final int? previousScore;

  String? get _change {
    final previous = previousScore;
    if (previous == null) return null;
    if (score > previous) return 'Up from $previous% on your last run';
    if (score < previous) return 'Down from $previous% on your last run';
    return 'Same score as your last run';
  }

  final int passed;
  final int failed;
  final int score;
  final double passRate;

  /// Points earned and available when checks carry points; null otherwise.
  final double? earnedPoints;
  final double? totalPoints;

  /// Checks that must pass but carry no points of their own.
  final int requirementChecks;

  /// Why the score and the passed-check count can disagree, or null.
  String? get _explanation {
    final total = totalPoints;
    if (total == null || total <= 0) return null;
    final earned = earnedPoints ?? 0;
    if (score == 0 && earned > 0) {
      return 'A required check failed, so the score stays at 0% until it '
          'passes.';
    }
    if (requirementChecks > 0 && passed > 0 && score < 100) {
      return '$requirementChecks required checks carry no points; your score '
          'comes from the ${_formatPoints(total)} points of the behavior '
          'checks.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allPassed = failed == 0 && passed > 0;
    final statusColor = performanceColor(score);

    return Semantics(
      container: true,
      label: 'Test score $score percent. $passed of ${passed + failed} '
          'checks passed.',
      child: Container(
        key: const Key('result-summary'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: statusColor.withValues(alpha: 0.35)),
          boxShadow: appCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ScoreRing(
                  key: const Key('result-score-ring'),
                  score: score,
                  color: statusColor,
                  size: 76,
                  label: 'score',
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                          allPassed
                              ? LucideIcons.badgeCheck
                              : LucideIcons.searchCode,
                          size: 18,
                          color: statusColor,
                        ),
                        const SizedBox(width: AppSpacing.xs),
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
                      ]),
                      if (_change case final change?) ...[
                        const SizedBox(height: 2),
                        Row(children: [
                          Icon(
                            score > previousScore!
                                ? LucideIcons.trendingUp
                                : score < previousScore!
                                    ? LucideIcons.trendingDown
                                    : LucideIcons.minus,
                            size: 14,
                            color: AppColors.inkMuted,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              change,
                              key: const Key('result-score-change'),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.inkMuted),
                            ),
                          ),
                        ]),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          if (totalPoints != null)
                            _ResultCount(
                              key: const Key('result-points'),
                              icon: LucideIcons.star,
                              label: 'Points: ${_formatPoints(earnedPoints ?? 0)} of '
                                  '${_formatPoints(totalPoints!)}',
                              color: theme.colorScheme.primary,
                            ),
                          _ResultCount(
                            key: const Key('result-checks'),
                            icon: LucideIcons.check,
                            label: 'Checks passed: $passed of ${passed + failed}',
                            color: AppColors.success,
                          ),
                          if (failed > 0)
                            _ResultCount(
                              icon: LucideIcons.x,
                              label: 'Failed: $failed',
                              color: theme.colorScheme.error,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_explanation case final note?) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                note,
                key: const Key('result-score-explanation'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.inkMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultCount extends StatelessWidget {
  const _ResultCount({
    super.key,
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          // Wraps instead of overflowing in a narrow Results panel.
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
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
    // Traditional runs carry no printed output, so an empty panel would
    // wrongly read as "your program printed nothing".
    if (data.execSuccess && data.feedbackMode == 'traditional') {
      return const SizedBox.shrink();
    }
    if (data.execSuccess) {
      return _TerminalPanel(
        key: const Key('terminal-output'),
        title: 'Terminal output',
        semanticsLabel: 'Terminal output',
        icon: LucideIcons.squareTerminal,
        iconColor: const Color(0xFF90D8B5),
        text: data.codeOutput,
      );
    }
    // A failed run still shows what the program printed before it stopped;
    // that output is often the student's best clue.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TerminalPanel(
          key: const Key('terminal-output'),
          title: 'Execution error',
          semanticsLabel: 'Code execution error',
          icon: LucideIcons.circleAlert,
          iconColor: const Color(0xFFFFB4AB),
          text: data.codeExecResult,
        ),
        if (data.codeOutput.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _TerminalPanel(
            key: const Key('terminal-printed-output'),
            title: 'Your printed output',
            semanticsLabel: 'Printed output before the error',
            icon: LucideIcons.squareTerminal,
            iconColor: const Color(0xFF90D8B5),
            text: data.codeOutput,
          ),
        ],
      ],
    );
  }
}

class _TerminalPanel extends StatelessWidget {
  const _TerminalPanel({
    super.key,
    required this.title,
    required this.semanticsLabel,
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final String title;
  final String semanticsLabel;
  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Container(
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
                  Icon(icon, size: 18, color: iconColor),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    title,
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
                '> ${text.isEmpty ? 'No output returned.' : text}',
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
  const _HintCallout({required this.hint, required this.source, this.details});

  final String hint;
  final String source;

  /// The rest of the same tutor reply (what to inspect, steps, next action),
  /// shown under the one-line hint so one reply reads as one card.
  final Map<String, dynamic>? details;

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
                ? LucideIcons.sparkles
                : LucideIcons.lightbulb,
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
                if (details != null && _TutorDetails.hasContent(details!))
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      color: fromAi ? AppColors.ink : Colors.brown.shade900,
                    ),
                    child: _TutorDetails(
                      key: const Key('tutor-hint-details'),
                      data: details!,
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
  Widget build(BuildContext context) => const StatusPill(
        key: Key('ai-generated-badge'),
        label: 'AI-generated',
        color: AppColors.ai,
        icon: LucideIcons.sparkles,
        solid: true,
        size: PillSize.small,
      );
}

class _TutorHintPanel extends StatefulWidget {
  const _TutorHintPanel({
    super.key,
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
  Map<String, dynamic>? _details;
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
    // The run's tutor reply belongs to the hint; the answer card is only for
    // questions the student actually asks.
    _answer = null;
    _details = !widget.allowQuestions || widget.data.tutorFeedback.isEmpty
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
        _details = widget.allowQuestions ? feedback : null;
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
          _HintCallout(hint: _hint, source: _source, details: _details),
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
                style: const ButtonStyle(backgroundBuilder: plainButtonBackground),
                key: const Key('next-hint-button'),
                onPressed:
                    _loading || _hintLevel >= 4 ? null : _requestNextHint,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.arrowRight, size: 18),
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
            widget.useAiTutor
                ? 'Ask about your latest attempt. The tutor explains and guides, but does not provide completed code.'
                : 'AI tutoring is off, so the built-in tutor answers with general guidance based on your latest results. It does not provide completed code.',
            key: const Key('ask-tutor-intro'),
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
                  : const Icon(LucideIcons.messagesSquare, size: 18),
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
                        ? LucideIcons.sparkles
                        : LucideIcons.headset,
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
              _TutorDetails(data: data, includeAnswer: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// The structured parts of a tutor reply: answer, what to inspect, debugging
/// steps, guiding question, and next action. Empty parts are left out.
class _TutorDetails extends StatelessWidget {
  const _TutorDetails({super.key, required this.data, this.includeAnswer = false});

  final Map<String, dynamic> data;
  final bool includeAnswer;

  static List<String> _steps(Map<String, dynamic> data) =>
      (data['debugging_steps'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList();

  static bool hasContent(Map<String, dynamic> data) =>
      ['diagnosis', 'guiding_question', 'next_action']
          .any((key) => (data[key]?.toString() ?? '').isNotEmpty) ||
      _steps(data).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final answer = includeAnswer ? data['answer']?.toString() ?? '' : '';
    final diagnosis = data['diagnosis']?.toString() ?? '';
    final guidingQuestion = data['guiding_question']?.toString() ?? '';
    final nextAction = data['next_action']?.toString() ?? '';
    final debuggingSteps = _steps(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
    this.earnedWeight,
    this.hintKey,
    this.onWatch,
  });

  final String? hintKey;
  final ValueChanged<String>? onWatch;

  final int checkNumber;
  final bool passed;
  final String first;
  final String highlighted;
  final String last;
  final String? label;
  final String? reason;
  final double? weight;
  final double? earnedWeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = passed ? AppColors.success : theme.colorScheme.error;
    final earned = earnedWeight ?? (passed ? weight : 0);

    final hasLabel = label != null && label!.isNotEmpty;
    return Semantics(
      container: true,
      label: passed ? 'Test passed' : 'Test needs attention',
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: statusColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          passed ? LucideIcons.check : LucideIcons.x,
                          size: 15,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasLabel)
                              Text(
                                label!,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            Text(
                              weight == null
                                  ? 'Check $checkNumber'
                                  : weight == 0
                                      ? 'Check $checkNumber · required, no points'
                                      : 'Check $checkNumber · '
                                          '${_formatPoints(earned ?? 0)} of '
                                          '${_formatPoints(weight!)} points',
                              key: Key('test-result-points-$checkNumber'),
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: AppColors.inkMuted),
                            ),
                            if (!passed &&
                                failureReasonExplanation(reason) != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Row(
                                key: Key('test-result-reason-$checkNumber'),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    LucideIcons.lightbulb,
                                    size: 15,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      failureReasonExplanation(reason)!,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (first.isNotEmpty ||
                                highlighted.isNotEmpty ||
                                last.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.xs),
                              RichText(
                                softWrap: true,
                                text: TextSpan(
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: passed
                                        ? AppColors.inkMuted
                                        : theme.colorScheme.onSurface,
                                    height: 1.45,
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
                            if (!passed &&
                                onWatch != null &&
                                SimFocus.forHint(hintKey, 0) != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  key: Key('test-result-watch-$checkNumber'),
                                  onPressed: () => onWatch!(hintKey!),
                                  icon: const Icon(LucideIcons.bot, size: 18),
                                  label:
                                      const Text('Watch it in the simulation'),
                                ),
                              ),
                          ],
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
