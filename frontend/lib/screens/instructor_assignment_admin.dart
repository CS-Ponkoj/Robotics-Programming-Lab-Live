import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:iuse_demo/state/feedback_page_tracker.dart';
import 'package:iuse_demo/screens/feedback_inbox_page.dart';
import 'package:iuse_demo/screens/student_accounts_page.dart';
import 'package:iuse_demo/screens/research_dashboard_page.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/services/instructor_api.dart';
import 'package:iuse_demo/theme/app_theme.dart';

/// Instructor Studio home: one card per instructor tool.
class InstructorAssignmentAdmin extends StatelessWidget {
  const InstructorAssignmentAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void open(Widget page, String name) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: RouteSettings(arguments: FeedbackPage(name)),
            builder: (_) => page,
          ),
        );
    final cards = [
      _StudioLinkCard(
        key: const Key('studio-assignments-card'),
        icon: Icons.assignment_outlined,
        title: 'Assignment management',
        detail: 'Create, edit, validate, and publish versioned assignments.',
        onTap: () =>
            open(const AssignmentManagementPage(), 'Assignment management'),
      ),
      _StudioLinkCard(
        icon: Icons.manage_accounts_outlined,
        title: 'Manage accounts',
        detail:
            'Create logins, reset access, and see each account\'s sign-ins.',
        onTap: () => open(const StudentAccountsPage(), 'Manage accounts'),
      ),
      _StudioLinkCard(
        icon: Icons.insights_rounded,
        title: 'Research study dashboard',
        detail: 'Participation, attempts, and privacy-safe research exports.',
        onTap: () => open(
            const InstructorResearchDashboard(), 'Research study dashboard'),
      ),
      _StudioLinkCard(
        key: const Key('studio-feedback-card'),
        icon: Icons.feedback_outlined,
        title: 'Feedback',
        detail: 'Bug reports and suggestions sent from any page.',
        onTap: () => open(const FeedbackInboxPage(), 'Feedback inbox'),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Instructor Studio')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            children: [
              Text('Instructor Studio', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Choose a tool. Your instructor login authorizes assignment, '
                'account, research, and feedback management.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
      if (mounted) {
        setState(() => _assignments = values);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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
      icon: const Icon(Icons.add_rounded),
      label: const Text('Create assignment'),
    );
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Manage versioned assignments',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Publishing is blocked until the reference solution passes '
          'the hidden grader.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assignment management'),
      ),
      body: Center(
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
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brandTint,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppColors.brandDark),
              ),
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
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudioAssignmentRow extends StatelessWidget {
  const _StudioAssignmentRow({required this.assignment, required this.onTap});

  final Map<String, dynamic> assignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final published = assignment['status'] == 'published';
    final ros2 = '${assignment['language']}'.contains('ros2');
    Widget chip(String label, Color background, Color foreground) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
          ),
        );

    return Card(
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
                child: Icon(Icons.edit_outlined,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
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
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _validate() async {
    if (_saved?['id'] is! int) {
      setState(() => _message = 'Save the assignment before validation.');
      return;
    }
    final result = await validateAdminAssignment(
      widget.adminToken,
      _saved!['id'] as int,
    );
    if (mounted) {
      setState(() {
        _message = result['valid'] == true
            ? 'Validation passed. This assignment is publishable.'
            : 'Validation failed: ${(result['errors'] as List).join(' ')}';
      });
    }
  }

  Future<void> _publish() async {
    if (_saved?['id'] is! int) {
      setState(() => _message = 'Save the assignment before publishing.');
      return;
    }
    try {
      await publishAdminAssignment(
        widget.adminToken,
        _saved!['id'] as int,
      );
      if (mounted) {
        setState(() {
          _saved!['status'] = 'published';
          _message = 'Published successfully.';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title, String detail, List<Widget> fields) => Card(
          margin: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                for (final (index, field) in fields.indexed) ...[
                  if (index > 0) const SizedBox(height: 16),
                  field,
                ],
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(_saved?['title']?.toString() ?? 'New assignment'),
        actions: MediaQuery.sizeOf(context).width < 600
            // Phones keep the title readable with icon-only actions.
            ? [
                IconButton(
                  tooltip: 'Validate',
                  onPressed: _validate,
                  icon: const Icon(Icons.fact_check_outlined),
                ),
                IconButton(
                  tooltip: 'Publish',
                  onPressed: _publish,
                  icon: const Icon(Icons.publish_rounded),
                ),
                const SizedBox(width: 4),
              ]
            : [
                TextButton.icon(
                  onPressed: _validate,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Validate'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _publish,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.brandDark,
                    minimumSize: const Size(0, 40),
                  ),
                  icon: const Icon(Icons.publish_rounded, size: 18),
                  label: const Text('Publish'),
                ),
                const SizedBox(width: 16),
              ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
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
                if (_message != null) ...[
                  Text(_message!),
                  const SizedBox(height: 16),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving…' : 'Save draft'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
