import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:iuse_demo/widgets/floating_app_bar.dart';
import 'package:iuse_demo/screens/ai_tutor_settings_page.dart';
import 'package:iuse_demo/screens/assignment_insights_page.dart';
import 'package:iuse_demo/screens/assignment_workspace.dart'
    show AssignmentInstructions;
import 'package:iuse_demo/widgets/sim_world_editor.dart';
import 'package:iuse_demo/state/feedback_page_tracker.dart';
import 'package:iuse_demo/screens/feedback_inbox_page.dart';
import 'package:iuse_demo/screens/student_accounts_page.dart';
import 'package:iuse_demo/screens/research_dashboard_page.dart';
import 'package:iuse_demo/screens/study_data_page.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/services/instructor_api.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/app_blocks.dart';
import 'package:iuse_demo/widgets/scrollable_center.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Instructor Studio home: one card per instructor tool.
class InstructorAssignmentAdmin extends StatelessWidget {
  const InstructorAssignmentAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget page, String name) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: RouteSettings(arguments: FeedbackPage(name)),
            builder: (_) => page,
          ),
        );
    final cards = [
      _StudioLinkCard(
        key: const Key('studio-assignments-card'),
        icon: LucideIcons.clipboardList,
        title: 'Assignment management',
        detail: 'Create, edit, validate, and publish versioned assignments.',
        onTap: () =>
            open(const AssignmentManagementPage(), 'Assignment management'),
      ),
      _StudioLinkCard(
        icon: LucideIcons.userCog,
        title: 'Manage accounts',
        detail:
            'Create logins, reset access, and see each account\'s sign-ins.',
        onTap: () => open(const StudentAccountsPage(), 'Manage accounts'),
      ),
      _StudioLinkCard(
        icon: LucideIcons.chartLine,
        title: 'Research study dashboard',
        detail: 'Participation, attempts, and privacy-safe research exports.',
        onTap: () => open(
            const InstructorResearchDashboard(), 'Research study dashboard'),
      ),
      _StudioLinkCard(
        key: const Key('studio-study-data-card'),
        icon: LucideIcons.table,
        title: 'Study data',
        detail: 'Every record the app collects, including AI questions and '
            'hints, as tables you can filter and download as CSV.',
        onTap: () => open(const StudyDataPage(), 'Study data'),
      ),
      _StudioLinkCard(
        key: const Key('studio-ai-card'),
        icon: LucideIcons.brain,
        title: 'AI tutor',
        detail: 'Turn AI tutoring on for the course, set a daily limit, and '
            'see which assignments are reviewed.',
        onTap: () => open(const AiTutorSettingsPage(), 'AI tutor'),
      ),
      _StudioLinkCard(
        key: const Key('studio-feedback-card'),
        icon: LucideIcons.messageSquareText,
        title: 'Feedback',
        detail: 'Bug reports and suggestions sent from any page.',
        onTap: () => open(const FeedbackInboxPage(), 'Feedback inbox'),
      ),
    ];
    return Scaffold(
      appBar: FloatingAppBar(AppBar(
        flexibleSpace: const BrandHeaderGradient(),
        title: const Text('Instructor Studio'))),
      body: ScrollableCenter(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            children: [
              const SectionHeader(
                prominent: true,
                title: 'Instructor Studio',
                subtitle: 'Choose a tool. Your instructor login authorizes '
                    'assignment, account, research, and feedback management.',
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 720 ? 2 : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 16) / columns;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final card in cards)
                        SizedBox(width: width, child: card),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lists every assignment version and opens the editor.
class AssignmentManagementPage extends StatefulWidget {
  const AssignmentManagementPage({super.key});

  @override
  State<AssignmentManagementPage> createState() =>
      _AssignmentManagementPageState();
}

class _AssignmentManagementPageState extends State<AssignmentManagementPage> {
  List<Map<String, dynamic>> _assignments = [];
  bool _loading = true;
  String? _error;

  /// Stable IDs on the students' Old assignments panel, and where that list
  /// comes from: the repository file or an instructor's choice.
  Set<String> _oldIds = {};
  String _catalogSource = 'file';
  bool _catalogBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await fetchAdminAssignments(AuthApi.token ?? '');
      // The list still works if the catalog cannot be read.
      Map<String, dynamic>? catalog;
      try {
        catalog = await fetchCatalogSettings(AuthApi.token ?? '');
      } on Object {
        catalog = null;
      }
      if (mounted) {
        setState(() {
          _assignments = values;
          if (catalog != null) _showCatalog(catalog);
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showCatalog(Map<String, dynamic> catalog) {
    _oldIds = {
      for (final id in (catalog['old_stable_ids'] as List? ?? const []))
        '$id',
    };
    _catalogSource = '${catalog['source'] ?? 'file'}';
  }

  /// Moves one assignment between the students' current and Old panels.
  Future<void> _saveCatalog(List<String>? oldIds) async {
    setState(() => _catalogBusy = true);
    try {
      final catalog = await saveCatalogSettings(AuthApi.token ?? '', oldIds);
      if (mounted) setState(() => _showCatalog(catalog));
    } on Object catch (error) {
      if (mounted) {
        setState(() =>
            _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _catalogBusy = false);
    }
  }

  void _toggleOld(String stableId) {
    final next = {..._oldIds};
    if (!next.remove(stableId)) next.add(stableId);
    _saveCatalog(next.toList()..sort());
  }

  void _openInsights(Map<String, dynamic> assignment) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(arguments: FeedbackPage('Insights')),
      builder: (_) => AssignmentInsightsPage(
        assignmentId: assignment['id'] as int,
        title: '${assignment['title']}',
      ),
    ));
  }

  Future<void> _edit([Map<String, dynamic>? assignment]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings:
            const RouteSettings(arguments: FeedbackPage('Assignment editor')),
        builder: (_) => AssignmentEditorPage(
          adminToken: AuthApi.token ?? '',
          assignment: assignment,
        ),
      ),
    );
    if (saved == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final published =
        _assignments.where((a) => a['status'] == 'published').length;

    final createButton = FilledButton.icon(
      key: const Key('create-assignment-button'),
      onPressed: _loading ? null : () => _edit(),
      icon: const Icon(LucideIcons.plus),
      label: const Text('Create assignment'),
    );
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          prominent: true,
          title: 'Manage versioned assignments',
          subtitle: 'Publishing is blocked until the reference solution '
              'passes the hidden grader.',
        ),
      ],
    );

    return Scaffold(
      appBar: FloatingAppBar(AppBar(
        flexibleSpace: const BrandHeaderGradient(),
        title: const Text('Assignment management'),
      )),
      body: ScrollableCenter(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            children: [
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 720
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: intro),
                          const SizedBox(width: 24),
                          createButton,
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          intro,
                          const SizedBox(height: 16),
                          createButton
                        ],
                      ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 28),
              Row(
                children: [
                  Text('Assignments', style: theme.textTheme.titleLarge),
                  const SizedBox(width: 12),
                  if (!_loading)
                    Text(
                      '${_assignments.length} total · $published published',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
              if (!_loading) ...[
                const SizedBox(height: 6),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      _catalogSource == 'file'
                          ? 'Old assignments panel: the repository list '
                              '(catalog.json).'
                          : 'Old assignments panel: chosen here.',
                      key: const Key('catalog-source'),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (_catalogSource != 'file')
                      TextButton(
                        key: const Key('catalog-reset'),
                        onPressed:
                            _catalogBusy ? null : () => _saveCatalog(null),
                        child: const Text('Use the repository list'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_assignments.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('No assignments are available yet.'),
                  ),
                )
              else
                for (final assignment in _assignments)
                  _StudioAssignmentRow(
                    assignment: assignment,
                    onTap: () => _edit(assignment),
                    isOld: _oldIds.contains('${assignment['stable_id']}'),
                    onToggleOld: _catalogBusy
                        ? null
                        : () => _toggleOld('${assignment['stable_id']}'),
                    onInsights: assignment['id'] is int
                        ? () => _openInsights(assignment)
                        : null,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudioLinkCard extends StatelessWidget {
  const _StudioLinkCard({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          // Room for a two-line description, so cards side by side match.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Row(
            children: [
              IconTile(icon: icon, size: 44),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronRight,
                  color: AppColors.inkMuted),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _StudioAssignmentRow extends StatelessWidget {
  const _StudioAssignmentRow({
    required this.assignment,
    required this.onTap,
    this.isOld = false,
    this.onToggleOld,
    this.onInsights,
  });

  final Map<String, dynamic> assignment;
  final VoidCallback onTap;

  /// On the students' Old assignments panel.
  final bool isOld;
  final VoidCallback? onToggleOld;
  final VoidCallback? onInsights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final published = assignment['status'] == 'published';
    final ros2 = '${assignment['language']}'.contains('ros2');
    Widget chip(String label, Color background, Color foreground) =>
        StatusPill(
          label: label,
          color: foreground,
          background: background,
          size: PillSize.small,
        );

    // The row's main area opens the editor and carries the assignment's
    // name for screen readers; Insights and Old/current are separate buttons.
    return Card(
      child: Row(
        children: [
          Expanded(
      // Announced as a button that opens this assignment's editor.
      child: Semantics(
        button: true,
        child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brandTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${assignment['id']}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.brandDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignment['title']?.toString() ?? 'Untitled assignment',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        chip(
                          published ? 'Published' : '${assignment['status']}',
                          published
                              ? AppColors.successContainer
                              : AppColors.neutralContainer,
                          published ? AppColors.success : AppColors.inkMuted,
                        ),
                        chip(
                          ros2 ? 'ROS 2' : 'Python',
                          ros2
                              ? theme.colorScheme.secondaryContainer
                              : AppColors.neutralContainer,
                          ros2
                              ? theme.colorScheme.onSecondaryContainer
                              : AppColors.inkMuted,
                        ),
                        chip(
                          isOld ? 'Old' : 'Current',
                          isOld
                              ? AppColors.neutralContainer
                              : theme.colorScheme.primaryContainer,
                          isOld
                              ? AppColors.inkMuted
                              : theme.colorScheme.onPrimaryContainer,
                        ),
                        Text(
                          '${assignment['stable_id']} • '
                          'v${assignment['version']}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Edit assignment',
                child: Icon(LucideIcons.pencil,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      ),
          ),
          if (onInsights != null)
            IconButton(
              key: Key('assignment-insights-${assignment['id']}'),
              tooltip: 'Insights for Assignment ${assignment['id']}, '
                  'where students get stuck',
              onPressed: onInsights,
              icon: const Icon(LucideIcons.chartLine),
            ),
          IconButton(
            key: Key('assignment-old-${assignment['id']}'),
            tooltip: isOld
                ? 'Move Assignment ${assignment['id']} to current assignments'
                : 'Move Assignment ${assignment['id']} to Old assignments',
            onPressed: onToggleOld,
            icon: Icon(
                isOld ? LucideIcons.archiveRestore : LucideIcons.archive),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class AssignmentEditorPage extends StatefulWidget {
  const AssignmentEditorPage({
    super.key,
    required this.adminToken,
    this.assignment,
  });

  final String adminToken;
  final Map<String, dynamic>? assignment;

  @override
  State<AssignmentEditorPage> createState() => _AssignmentEditorPageState();
}

class _AssignmentEditorPageState extends State<AssignmentEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;
  Map<String, dynamic>? _saved;
  String? _message;
  bool _messageIsError = false;

  /// What is running now (Validate or Publish); null when idle.
  String? _busy;

  static const _jsonFields = {
    'execution_settings',
    'public_tests',
    'rubric',
    'misconceptions',
    'tutoring_rules',
    'simulation_config',
    'asset_manifest',
    'grader_config',
  };

  @override
  void initState() {
    super.initState();
    final source = widget.assignment ?? _newAssignment();
    _saved = widget.assignment;
    _controllers = {
      for (final field in [
        'stable_id',
        'version',
        'title',
        'description',
        'assignment_html',
        'starter_code',
        'language',
        'learning_objectives',
        ..._jsonFields,
        'solution_html',
        'reference_solution_path',
      ])
        field: TextEditingController(
          text: _displayValue(field, source[field]),
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  static Map<String, dynamic> _newAssignment() => {
        'stable_id': 'new-robotics-assignment',
        'version': 1,
        'title': 'New robotics assignment',
        'description': '',
        'assignment_html': '<p><strong>Scenario</strong></p>',
        'starter_code': '',
        'language': 'python',
        'status': 'draft',
        'learning_objectives': <String>[],
        'execution_settings': {
          'runtime': 'python3.14',
          'timeout_seconds': 5,
          'allowed_imports': ['math', 'numpy', 'scipy'],
        },
        'public_tests': <dynamic>[],
        'rubric': <dynamic>[],
        'misconceptions': <dynamic>[],
        'tutoring_rules': {
          'max_hint_level': 4,
          'never_reveal_solution': true,
        },
        'simulation_config': {'enabled': false},
        'asset_manifest': <dynamic>[],
        'grader_type': 'python_variables',
        'grader_config': {'expected_values': <String, dynamic>{}},
        'solution_html': '',
        'reference_solution_path': '',
      };

  static String _displayValue(String field, dynamic value) {
    if (field == 'learning_objectives' && value is List) {
      return value.join('\n');
    }
    if (_jsonFields.contains(field)) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return value?.toString() ?? '';
  }

  Map<String, dynamic> _payload() {
    dynamic decodeJson(String field) {
      final source = _controllers[field]!.text.trim();
      return jsonDecode(source.isEmpty ? '{}' : source);
    }

    return {
      if (_saved?['id'] is int) 'id': _saved!['id'],
      'stable_id': _controllers['stable_id']!.text.trim(),
      'version': int.tryParse(_controllers['version']!.text) ?? 1,
      'title': _controllers['title']!.text.trim(),
      'description': _controllers['description']!.text,
      'assignment_html': _controllers['assignment_html']!.text,
      'starter_code': _controllers['starter_code']!.text,
      'language': _controllers['language']!.text.trim(),
      'status': _saved?['status'] ?? 'draft',
      'learning_objectives': _controllers['learning_objectives']!
          .text
          .split('\n')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      for (final field in _jsonFields) field: decodeJson(field),
      'grader_type': _saved?['grader_type'] ?? 'python_variables',
      'solution_html': _controllers['solution_html']!.text,
      'reference_solution_path':
          _controllers['reference_solution_path']!.text.trim().isEmpty
              ? null
              : _controllers['reference_solution_path']!.text.trim(),
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final saved = await saveAdminAssignment(widget.adminToken, _payload());
      if (mounted) {
        setState(() {
          _saved = saved;
          _controllers['version']!.text = '${saved['version']}';
          _message = 'Saved assignment version ${saved['version']}.';
          _messageIsError = false;
        });
      }
    } on Object catch (error) {
      _report(error.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _report(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  /// Runs one Validate or Publish action at a time, with visible progress.
  Future<void> _run(String busy, Future<void> Function() action) async {
    if (_busy != null || _saving) return;
    setState(() {
      _busy = busy;
      _message = null;
    });
    try {
      await action();
    } on Object catch (error) {
      _report(error.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _validate() async {
    if (_saved?['id'] is! int) {
      _report('Save the assignment before validation.', error: true);
      return;
    }
    await _run('Validating: running the reference solution through the grader…',
        () async {
      final result = await validateAdminAssignment(
        widget.adminToken,
        _saved!['id'] as int,
      );
      final valid = result['valid'] == true;
      _report(
        valid
            ? 'Validation passed. This assignment is publishable.'
            : 'Validation failed: ${(result['errors'] as List).join(' ')}',
        error: !valid,
      );
    });
  }

  Future<void> _publish() async {
    if (_saved?['id'] is! int) {
      _report('Save the assignment before publishing.', error: true);
      return;
    }
    await _run('Publishing…', () async {
      await publishAdminAssignment(
        widget.adminToken,
        _saved!['id'] as int,
      );
      if (mounted) setState(() => _saved!['status'] = 'published');
      _report('Published successfully.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title, String detail, List<Widget> fields) =>
        AppPanel(
          margin: const EdgeInsets.only(bottom: 20),
          title: title,
          subtitle: detail,
          bodyPadding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, field) in fields.indexed) ...[
                if (index > 0) const SizedBox(height: 16),
                field,
              ],
            ],
          ),
        );

    return Scaffold(
      appBar: FloatingAppBar(AppBar(
        flexibleSpace: const BrandHeaderGradient(),
        title: Text(_saved?['title']?.toString() ?? 'New assignment'),
        actions: MediaQuery.sizeOf(context).width < 600
            // Phones keep the title readable with icon-only actions.
            ? [
                IconButton(
                  tooltip: 'Validate',
                  onPressed: _busy != null ? null : _validate,
                  icon: const Icon(LucideIcons.clipboardCheck),
                ),
                IconButton(
                  tooltip: 'Publish',
                  onPressed: _busy != null ? null : _publish,
                  icon: const Icon(LucideIcons.upload),
                ),
                const SizedBox(width: 4),
              ]
            : [
                TextButton.icon(
                  onPressed: _busy != null ? null : _validate,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(LucideIcons.clipboardCheck, size: 18),
                  label: const Text('Validate'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy != null ? null : _publish,
                  style: FilledButton.styleFrom(
                    backgroundBuilder: plainButtonBackground,
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.brandDark,
                    minimumSize: const Size(0, 40),
                  ),
                  icon: const Icon(LucideIcons.upload, size: 18),
                  label: const Text('Publish'),
                ),
                const SizedBox(width: 16),
              ],
      )),
      body: Form(
        key: _formKey,
        child: _withStatusBar(
          theme,
          ScrollableCenter(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                children: [
                  section(
                    'Identity',
                    'Stable ID, version, and language identify every attempt.',
                    [
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _field('stable_id', 'Stable ID', width: 360),
                          _field('version', 'Version', width: 120),
                          _field('language', 'Language', width: 180),
                        ],
                      ),
                      _field('title', 'Title'),
                    ],
                  ),
                  section(
                    'Student-facing content',
                    'What students read before they start coding.',
                    [
                      _field('description', 'Description', lines: 3),
                      _field('learning_objectives',
                          'Learning objectives (one per line)',
                          lines: 4),
                      _field('assignment_html', 'Instructions HTML',
                          lines: 8, monospace: true),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          key: const Key('preview-as-student'),
                          onPressed: _previewAsStudent,
                          icon: const Icon(LucideIcons.eye),
                          label: const Text('Preview as a student sees it'),
                        ),
                      ),
                    ],
                  ),
                  section(
                    'Starter code and grading',
                    'Starter code, public tests, rubric, and grader settings.',
                    [
                      _field('starter_code', 'Starter code',
                          lines: 10, monospace: true),
                      for (final field in _jsonFields)
                        _field(
                          field,
                          field.replaceAll('_', ' '),
                          lines: 7,
                          jsonField: true,
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          key: const Key('edit-simulation-world'),
                          onPressed: _editSimulationWorld,
                          icon: const Icon(LucideIcons.map),
                          label: const Text('Edit the simulation world'),
                        ),
                      ),
                    ],
                  ),
                  section(
                    'Server-only solution',
                    'Never shown to students before they unlock the worked solution.',
                    [
                      _field('solution_html', 'Worked solution HTML',
                          lines: 6, monospace: true),
                      _field(
                        'reference_solution_path',
                        'Server-side reference solution path',
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _saving || _busy != null ? null : _save,
                      icon: const Icon(LucideIcons.save),
                      label: Text(_saving ? 'Saving…' : 'Save draft'),
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

  /// The instructions exactly as the student workspace renders them, at
  /// computer or phone width, before saving.
  void _previewAsStudent() {
    var phone = false;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                  child: Row(children: [
                    const Expanded(child: Text('Student preview')),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Computer')),
                        ButtonSegment(value: true, label: Text('Phone')),
                      ],
                      selected: {phone},
                      onSelectionChanged: (value) =>
                          setDialog(() => phone = value.first),
                    ),
                    IconButton(
                      tooltip: 'Close preview',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(LucideIcons.x),
                    ),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: phone ? 390 : double.infinity,
                      child: AssignmentInstructions(
                        key: const Key('student-preview'),
                        html: _controllers['assignment_html']!.text,
                        assignmentId: _saved?['id'] as int? ?? 0,
                        assignmentVersion:
                            int.tryParse(_controllers['version']!.text) ?? 1,
                        canRevealSolution: false,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Edits simulation_config.world with fields and a live preview.
  Future<void> _editSimulationWorld() async {
    final controller = _controllers['simulation_config']!;
    Map<String, dynamic> config;
    try {
      config = Map<String, dynamic>.from(jsonDecode(controller.text) as Map);
    } on Object {
      _report('Fix the simulation config JSON before editing the world.',
          error: true);
      return;
    }
    final world = config['world'] is Map
        ? Map<String, dynamic>.from(config['world'] as Map)
        : <String, dynamic>{
            'walls': [
              [1.2, -3.0, 1.2, 3.0],
            ],
            'robot': {'x': 0.0, 'y': 0.0, 'theta': 0.0, 'radius': 0.15},
            'duration_seconds': 8.0,
          };
    final edited = await editSimWorld(context, world);
    if (edited == null || !mounted) return;
    config['world'] = edited;
    setState(() {
      controller.text = const JsonEncoder.withIndent('  ').convert(config);
    });
    _report('Simulation world updated. Save the draft to keep it.');
  }

  Widget _withStatusBar(ThemeData theme, Widget page) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_statusBar(theme), Expanded(child: page)],
      );

  /// Progress and the latest outcome, pinned under the toolbar so Save,
  /// Validate, and Publish always show what happened.
  Widget _statusBar(ThemeData theme) {
    final busy = _busy ?? (_saving ? 'Saving…' : null);
    final message = busy ?? _message;
    if (message == null) return const SizedBox.shrink();
    final error = busy == null && _messageIsError;
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busy != null) const LinearProgressIndicator(minHeight: 3),
        Material(
          key: const Key('assignment-editor-status'),
          color: busy != null
              ? scheme.surfaceContainerHigh
              : error
                  ? scheme.errorContainer
                  : scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Row(
              children: [
                Icon(
                  busy != null
                      ? LucideIcons.hourglass
                      : error
                          ? LucideIcons.circleAlert
                          : LucideIcons.circleCheck,
                  size: 20,
                  color: error ? scheme.onErrorContainer : scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: SelectableText(message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: error ? scheme.onErrorContainer : null)),
                  ),
                ),
                if (busy == null)
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: () => setState(() => _message = null),
                    icon: const Icon(LucideIcons.x, size: 18),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(
    String name,
    String label, {
    int lines = 1,
    double? width,
    bool jsonField = false,
    bool monospace = false,
  }) {
    final field = TextFormField(
      controller: _controllers[name],
      minLines: lines,
      maxLines: lines,
      style: monospace || jsonField
          ? const TextStyle(
              fontFamily: 'Courier-New',
              fontSize: 14,
              height: 1.45,
              color: AppColors.ink,
              fontWeight: FontWeight.w600)
          : null,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: lines > 1,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        if ({'stable_id', 'title', 'language'}.contains(name) &&
            (value == null || value.trim().isEmpty)) {
          return '$label is required.';
        }
        if (jsonField) {
          try {
            jsonDecode(value ?? '');
          } on Object {
            return 'Enter valid JSON.';
          }
        }
        return null;
      },
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}
