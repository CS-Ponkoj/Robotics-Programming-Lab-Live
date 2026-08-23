import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:iuse_demo/screens/student_accounts_page.dart';
import 'package:iuse_demo/screens/research_dashboard_page.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/services/instructor_api.dart';

class InstructorAssignmentAdmin extends StatefulWidget {
  const InstructorAssignmentAdmin({super.key});

  @override
  State<InstructorAssignmentAdmin> createState() =>
      _InstructorAssignmentAdminState();
}

class _InstructorAssignmentAdminState extends State<InstructorAssignmentAdmin> {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Instructor assignment studio'),
        actions: [
          IconButton(
            tooltip: 'Research study dashboard',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const InstructorResearchDashboard(),
                ),
              );
            },
            icon: const Icon(Icons.insights_rounded),
          ),
          IconButton(
            tooltip: 'Manage student accounts',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const StudentAccountsPage(),
                ),
              );
            },
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
          IconButton(
            tooltip: 'Create assignment',
            onPressed: _loading ? null : () => _edit(),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Manage versioned assignments',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your instructor login authorizes assignment and student '
                  'management. '
                  'Publishing is blocked until the reference solution passes '
                  'the hidden grader.',
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const StudentAccountsPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: const Text('Manage student accounts'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const InstructorResearchDashboard(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.insights_rounded),
                        label: const Text('View research dashboard'),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                ],
                const SizedBox(height: 20),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _assignments.isEmpty
                          ? const Center(
                              child: Text(
                                'No assignments are available yet.',
                              ),
                            )
                          : ListView.separated(
                              itemCount: _assignments.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final assignment = _assignments[index];
                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      child: Text('${assignment['id']}'),
                                    ),
                                    title: Text(
                                      assignment['title']?.toString() ??
                                          'Untitled assignment',
                                    ),
                                    subtitle: Text(
                                      '${assignment['stable_id']} • '
                                      'v${assignment['version']} • '
                                      '${assignment['status']}',
                                    ),
                                    trailing: const Icon(Icons.edit_outlined),
                                    onTap: () => _edit(assignment),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New assignment'),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_saved?['title']?.toString() ?? 'New assignment'),
        actions: [
          TextButton(onPressed: _validate, child: const Text('Validate')),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _publish,
            child: const Text('Publish'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _field('stable_id', 'Stable ID', width: 360),
                _field('version', 'Version', width: 120),
                _field('language', 'Language', width: 180),
              ],
            ),
            const SizedBox(height: 16),
            _field('title', 'Title'),
            const SizedBox(height: 16),
            _field('description', 'Description', lines: 3),
            const SizedBox(height: 16),
            _field('learning_objectives', 'Learning objectives (one per line)',
                lines: 4),
            const SizedBox(height: 16),
            _field('assignment_html', 'Instructions HTML', lines: 8),
            const SizedBox(height: 16),
            _field('starter_code', 'Starter code', lines: 10),
            const SizedBox(height: 16),
            for (final field in _jsonFields) ...[
              _field(
                field,
                field.replaceAll('_', ' '),
                lines: 7,
                jsonField: true,
              ),
              const SizedBox(height: 16),
            ],
            _field('solution_html', 'Worked solution HTML', lines: 6),
            const SizedBox(height: 16),
            _field(
              'reference_solution_path',
              'Server-side reference solution path',
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save draft'),
            ),
          ],
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
  }) {
    final field = TextFormField(
      controller: _controllers[name],
      minLines: lines,
      maxLines: lines,
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
