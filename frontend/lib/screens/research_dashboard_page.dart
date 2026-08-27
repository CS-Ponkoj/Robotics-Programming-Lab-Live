import 'package:flutter/material.dart';
import 'package:iuse_demo/services/research_api.dart';
import 'package:iuse_demo/theme/app_theme.dart';

class StudentResearchPage extends StatefulWidget {
  const StudentResearchPage({super.key, this.initialData});

  final Map<String, dynamic>? initialData;

  @override
  State<StudentResearchPage> createState() => _StudentResearchPageState();
}

class _StudentResearchPageState extends State<StudentResearchPage> {
  late Future<Map<String, dynamic>> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = widget.initialData == null
        ? fetchMyResearchData()
        : Future.value(widget.initialData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My study progress')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ResearchError(onRetry: () => setState(_reload));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final summary = _map(data['summary']);
          return _ResearchPageBody(
            children: [
              Text('Your learning record',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Participant ${summary['participant_code']}. Only you and your instructor can view this record.',
              ),
              const SizedBox(height: AppSpacing.lg),
              ResearchMetricGrid(summary: summary),
              const SizedBox(height: AppSpacing.xl),
              const _SectionTitle(
                title: 'Assignment analytics',
                subtitle:
                    'Every result is kept separate by assignment version.',
              ),
              const SizedBox(height: AppSpacing.sm),
              _AssignmentAnalyticsList(
                rows: _listOfMaps(data['assignment_summaries']),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionTitle(
                title: 'Attempt history',
                subtitle: 'Newest attempts appear first.',
              ),
              const SizedBox(height: AppSpacing.sm),
              _AttemptHistory(rows: _listOfMaps(data['attempts'])),
              const SizedBox(height: AppSpacing.xl),
              _MetricCatalogCard(catalog: _map(data['metric_catalog'])),
            ],
          );
        },
      ),
    );
  }
}

class InstructorResearchDashboard extends StatefulWidget {
  const InstructorResearchDashboard({
    super.key,
    this.initialParticipants,
    this.initialData,
  });

  final List<Map<String, dynamic>>? initialParticipants;
  final Map<String, dynamic>? initialData;

  @override
  State<InstructorResearchDashboard> createState() =>
      _InstructorResearchDashboardState();
}

class _InstructorResearchDashboardState
    extends State<InstructorResearchDashboard> {
  late Future<Map<String, dynamic>> _data;
  bool _downloading = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    if (widget.initialData != null) {
      _data = Future.value(widget.initialData);
    } else if (widget.initialParticipants != null) {
      _data = Future.value({
        'overview': _aggregateParticipants(widget.initialParticipants!),
        'participants': widget.initialParticipants,
        'assignment_summaries': const <Map<String, dynamic>>[],
        'data_health': const <String, dynamic>{},
      });
    } else {
      _data = fetchInstructorResearchData();
    }
  }

  Future<void> _download(String datasetName, String format) async {
    setState(() => _downloading = true);
    try {
      final saved = await downloadResearchDataset(
        datasetName: datasetName,
        format: format,
      );
      if (!saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downloads are available in the web application.'),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Research study dashboard'),
        actions: [
          PopupMenuButton<String>(
            key: const Key('research-export-menu'),
            enabled: !_downloading,
            tooltip: 'Export research data',
            onSelected: (value) {
              final parts = value.split(':');
              _download(parts.first, parts.last);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'student_summary:csv',
                child: Text('Participant summary CSV'),
              ),
              PopupMenuItem(
                value: 'assignment_summary:csv',
                child: Text('Participant-assignment CSV'),
              ),
              PopupMenuItem(
                value: 'class_assignment_summary:csv',
                child: Text('Class assignment CSV'),
              ),
              PopupMenuItem(
                value: 'assignment_attempts:csv',
                child: Text('Assignment attempts CSV'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'all:xlsx',
                child: Text('Complete Excel workbook'),
              ),
            ],
            icon: _downloading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ResearchError(onRetry: () => setState(_reload));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final overview = _map(data['overview']);
          final participants = _listOfMaps(data['participants']);
          final filtered = participants
              .where(
                (item) => item['participant_code']
                    .toString()
                    .toLowerCase()
                    .contains(_query.toLowerCase()),
              )
              .toList();
          return _ResearchPageBody(
            children: [
              const _SectionTitle(
                title: 'Classroom overview',
                subtitle:
                    'Research-safe summaries use participant codes, never login IDs.',
              ),
              const SizedBox(height: AppSpacing.md),
              _ClassroomMetricGrid(summary: overview),
              const SizedBox(height: AppSpacing.xl),
              _SectionTitle(
                title: 'Participant catalog',
                subtitle: '${participants.length} active participants',
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('participant-search'),
                decoration: const InputDecoration(
                  labelText: 'Search participant code',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (filtered.isEmpty)
                const _EmptyResearchState(
                  message: 'No participant matches this search.',
                )
              else
                ...filtered.map(_participantCard),
              const SizedBox(height: AppSpacing.xl),
              const _SectionTitle(
                title: 'Assignment catalog',
                subtitle: 'Current published versions only.',
              ),
              const SizedBox(height: AppSpacing.sm),
              _InstructorAssignmentList(
                rows: _listOfMaps(data['assignment_summaries']),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionTitle(
                title: 'Data health',
                subtitle: 'Checks that protect the research dataset.',
              ),
              const SizedBox(height: AppSpacing.sm),
              _DataHealthCard(values: _map(data['data_health'])),
              const SizedBox(height: AppSpacing.xl),
              _MetricCatalogCard(catalog: _map(data['metric_catalog'])),
            ],
          );
        },
      ),
    );
  }

  Widget _participantCard(Map<String, dynamic> participant) {
    final participantCode = participant['participant_code'].toString();
    return Card(
      key: Key('research-participant-$participantCode'),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        leading: CircleAvatar(
          child: Text(participantCode.characters.take(2).toString()),
        ),
        title: Text(participantCode),
        subtitle: Text(
          '${participant['attempts']} attempts · ${participant['assignments_completed']} completed · ${_formatDuration(_intValue(participant['active_seconds']))}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${participant['best_score']}%',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        onTap: participant['student_id'] == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ResearchStudentDetailPage(
                      studentId: participant['student_id'].toString(),
                    ),
                  ),
                ),
      ),
    );
  }
}

class ResearchStudentDetailPage extends StatefulWidget {
  const ResearchStudentDetailPage({
    super.key,
    required this.studentId,
    this.initialData,
  });

  final String studentId;
  final Map<String, dynamic>? initialData;

  @override
  State<ResearchStudentDetailPage> createState() =>
      _ResearchStudentDetailPageState();
}

class _ResearchStudentDetailPageState extends State<ResearchStudentDetailPage> {
  late Future<Map<String, dynamic>> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = widget.initialData == null
        ? fetchStudentResearchData(widget.studentId)
        : Future.value(widget.initialData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Participant detail')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ResearchError(onRetry: () => setState(_reload));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final summary = _map(data['summary']);
          return _ResearchPageBody(
            children: [
              Text(summary['participant_code'].toString(),
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'This is the same progress information available to the student.',
              ),
              const SizedBox(height: AppSpacing.lg),
              ResearchMetricGrid(summary: summary),
              const SizedBox(height: AppSpacing.xl),
              const _SectionTitle(
                title: 'Assignment analytics',
                subtitle: 'Results are separated by exact version.',
              ),
              const SizedBox(height: AppSpacing.sm),
              _AssignmentAnalyticsList(
                rows: _listOfMaps(data['assignment_summaries']),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionTitle(
                title: 'Attempt history',
                subtitle: 'Safe execution labels; source code is excluded.',
              ),
              const SizedBox(height: AppSpacing.sm),
              _AttemptHistory(rows: _listOfMaps(data['attempts'])),
              const SizedBox(height: AppSpacing.xl),
              _MetricCatalogCard(catalog: _map(data['metric_catalog'])),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle),
      ],
    );
  }
}

class ResearchMetricGrid extends StatelessWidget {
  const ResearchMetricGrid({super.key, required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    return _MetricGrid(
      metrics: [
        (
          'Assignments completed',
          '${summary['assignments_completed'] ?? 0}',
          Icons.verified_rounded
        ),
        (
          'Total attempts',
          '${summary['attempts'] ?? 0}',
          Icons.playlist_add_check_rounded
        ),
        (
          'Best score',
          '${summary['best_score'] ?? 0}%',
          Icons.insights_rounded
        ),
        (
          'Total app active time',
          _formatDuration(_intValue(summary['active_seconds'])),
          Icons.schedule_rounded
        ),
      ],
    );
  }
}

class _ClassroomMetricGrid extends StatelessWidget {
  const _ClassroomMetricGrid({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    return _MetricGrid(
      metrics: [
        (
          'Active participants',
          '${summary['active_participants'] ?? summary['participants'] ?? 0}',
          Icons.groups_rounded
        ),
        (
          'Students started',
          '${summary['students_started'] ?? 0}',
          Icons.start_rounded
        ),
        (
          'Students completed',
          '${summary['students_completed'] ?? 0}',
          Icons.verified_rounded
        ),
        (
          'Participation rate',
          _formatPercent(summary['participation_rate']),
          Icons.pie_chart_rounded
        ),
        (
          'Completion rate',
          _formatPercent(summary['completion_rate']),
          Icons.task_alt_rounded
        ),
        (
          'Total attempts',
          '${summary['total_attempts'] ?? summary['attempts'] ?? 0}',
          Icons.playlist_add_check_rounded
        ),
        (
          'Total active time',
          _formatDuration(_intValue(
              summary['total_active_seconds'] ?? summary['active_seconds'])),
          Icons.schedule_rounded
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<(String, String, IconData)> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
                ? 3
                : 2;
        final width =
            (constraints.maxWidth - (columns - 1) * AppSpacing.sm) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: _MetricCard(
                    label: metric.$1,
                    value: metric.$2,
                    icon: metric.$3,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _AssignmentAnalyticsList extends StatelessWidget {
  const _AssignmentAnalyticsList({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyResearchState(
        message: 'Assignment progress will appear here.',
      );
    }
    return Column(
      children: rows.map((row) {
        final status = row['status']?.toString() ?? 'not_started';
        return Card(
          child: ExpansionTile(
            key: Key(
                'assignment-analytics-${row['assignment_id']}-${row['assignment_version']}'),
            leading: Icon(_statusIcon(status), color: _statusColor(status)),
            title: Text(
              '${row['assignment_title']} · v${row['assignment_version']}',
            ),
            subtitle: Text(
              '${_statusLabel(status)} · ${row['attempt_count'] ?? 0} attempts · ${_score(row['best_score'])} best',
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailWrap(
                items: [
                  (
                    'Attempts to first success',
                    _availableNumber(row['attempts_to_first_success'])
                  ),
                  ('First score', _score(row['first_score'])),
                  ('Latest score', _score(row['latest_score'])),
                  ('Score improvement', _signedScore(row['score_improvement'])),
                  (
                    'Public tests passed',
                    _formatPercent(row['public_test_pass_percentage'])
                  ),
                  (
                    'Assignment active time',
                    _durationOrUnavailable(
                        row['total_active_seconds'], row['time_availability'])
                  ),
                  (
                    'Active time to completion',
                    _durationOrUnavailable(row['active_seconds_to_completion'],
                        row['completion_time_availability'])
                  ),
                  (
                    'Elapsed time to completion',
                    _durationOrUnavailable(row['elapsed_seconds_to_completion'],
                        row['completion_time_availability'])
                  ),
                  ('First attempt', _shortTimestamp(row['first_attempt_at'])),
                  ('Last attempt', _shortTimestamp(row['last_attempt_at'])),
                  ('Syntax errors', '${row['syntax_error_count'] ?? 0}'),
                  ('Runtime errors', '${row['runtime_error_count'] ?? 0}'),
                  ('Timeouts', '${row['timeout_count'] ?? 0}'),
                  ('Safety rejections', '${row['rejection_count'] ?? 0}'),
                  ('Output limits', '${row['excessive_output_count'] ?? 0}'),
                  (
                    'Size limits',
                    _availableNumber(row['oversized_submission_count'])
                  ),
                  ('Built-in hints', '${row['built_in_hint_count'] ?? 0}'),
                  ('AI interactions', '${row['ai_interaction_count'] ?? 0}'),
                  (
                    'Highest hint level',
                    _availableNumber(row['highest_hint_level'])
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _AttemptHistory extends StatelessWidget {
  const _AttemptHistory({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyResearchState(
        message: 'Assignment attempts will appear here.',
      );
    }
    final numbered = rows.asMap().entries.map((entry) {
      return <String, dynamic>{
        ...entry.value,
        'attempt_number': entry.value['attempt_number'] ?? entry.key + 1,
      };
    }).toList();
    final newest = numbered.reversed.take(50).toList();
    return Column(
      children: newest.map((row) {
        return Card(
          child: Semantics(
            label:
                'Assignment ${row['assignment_id']} attempt ${row['attempt_number']}, ${row['score']} percent, ${row['execution_status_label'] ?? row['execution_status']}',
            child: ListTile(
              leading: CircleAvatar(child: Text('${row['assignment_id']}')),
              title: Text(
                'Attempt #${row['attempt_number']} · Assignment ${row['assignment_id']} · ${row['score']}%',
              ),
              subtitle: Text(
                'v${row['assignment_version']} · ${_modeLabel(row['mode'])} · ${row['execution_status_label'] ?? _safeStatus(row['execution_status'])} · ${_shortTimestamp(row['created_at'])}',
              ),
              trailing: Icon(
                row['passed'] == true
                    ? Icons.check_circle_rounded
                    : Icons.pending_actions_rounded,
                color: row['passed'] == true
                    ? AppColors.success
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _InstructorAssignmentList extends StatelessWidget {
  const _InstructorAssignmentList({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyResearchState(
        message: 'Assignment summaries will appear after students begin.',
      );
    }
    return Column(
      children: rows.map((row) {
        final hidden = _map(row['hidden_test_aggregate']);
        final errors = _listOfMaps(row['most_common_errors']);
        final tests = _listOfMaps(row['most_failed_public_tests']);
        return Card(
          child: ExpansionTile(
            title: Text(
                '${row['assignment_title']} · v${row['assignment_version']}'),
            subtitle: Text(
              '${row['students_started']} started · ${row['students_completed']} completed · ${_formatPercent(row['completion_rate'])}',
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            children: [
              _DetailWrap(
                items: [
                  ('Total attempts', '${row['total_attempts']}'),
                  ('Median final score', _score(row['median_final_score'])),
                  (
                    'Score distribution',
                    _scoreDistribution(row['score_distribution'])
                  ),
                  (
                    'Median attempts to success',
                    _availableNumber(row['median_attempts_to_success'])
                  ),
                  (
                    'Median active time to completion',
                    _durationOrUnavailable(
                        row['median_active_seconds_to_completion'], null)
                  ),
                  (
                    'Hidden-test aggregate',
                    _formatPercent(hidden['pass_percentage'])
                  ),
                  (
                    'Most common errors',
                    errors.isEmpty
                        ? 'None recorded'
                        : errors
                            .map((item) =>
                                '${item['category']} (${item['affected_students']})')
                            .join(', ')
                  ),
                  (
                    'Most-failed public tests',
                    tests.isEmpty
                        ? 'None recorded'
                        : tests
                            .map((item) =>
                                '${item['label']} (${item['affected_students']})')
                            .join(', ')
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _MetricCatalogCard extends StatelessWidget {
  const _MetricCatalogCard({required this.catalog});

  final Map<String, dynamic> catalog;

  @override
  Widget build(BuildContext context) {
    final metrics = _listOfMaps(catalog['metrics']);
    if (metrics.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        key: const Key('phase-1-metric-catalog'),
        leading: const Icon(Icons.menu_book_rounded),
        title: const Text('Phase 1 metric definitions'),
        subtitle: Text(
          '${metrics.length} implemented metrics · catalog ${catalog['catalog_version'] ?? 'current'}',
        ),
        children: metrics
            .map(
              (metric) => ListTile(
                dense: true,
                title: Text('${metric['metric_id']} · ${metric['name']}'),
                subtitle: Text(metric['definition']?.toString() ?? ''),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DataHealthCard extends StatelessWidget {
  const _DataHealthCard({required this.values});

  final Map<String, dynamic> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const _EmptyResearchState(
        message: 'Data-health checks are not available in this preview.',
      );
    }
    final items = [
      ('Missing assignment versions', values['missing_assignment_versions']),
      (
        'Missing conditions',
        values['missing_participant_conditions'] ?? 'Not applicable in Phase 1'
      ),
      ('Duplicate event groups', values['duplicate_event_groups']),
      ('Orphan records', values['orphan_records']),
      ('Timestamp-order errors', values['timestamp_order_errors']),
      ('Demo-data contamination', values['demo_data_contamination']),
      ('Export reconciliation', values['export_reconciliation_status']),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: _DetailWrap(
          items: items.map((item) => (item.$1, _healthValue(item.$2))).toList(),
        ),
      ),
    );
  }
}

class _DetailWrap extends StatelessWidget {
  const _DetailWrap({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 700
            ? (constraints.maxWidth - AppSpacing.sm) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$1,
                            style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 2),
                        Text(item.$2,
                            style: Theme.of(context).textTheme.titleSmall),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _ResearchPageBody extends StatelessWidget {
  const _ResearchPageBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: children,
        ),
      ),
    );
  }
}

class _ResearchError extends StatelessWidget {
  const _ResearchError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 44),
          const SizedBox(height: AppSpacing.sm),
          const Text('Study data is temporarily unavailable.'),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyResearchState extends StatelessWidget {
  const _EmptyResearchState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

Map<String, dynamic> _aggregateParticipants(
  List<Map<String, dynamic>> participants,
) {
  final started =
      participants.where((item) => _intValue(item['attempts']) > 0).length;
  final completed = participants
      .where((item) => _intValue(item['assignments_completed']) > 0)
      .length;
  return {
    'participants': participants.length,
    'active_participants': participants.length,
    'students_started': started,
    'students_completed': completed,
    'participation_rate':
        participants.isEmpty ? null : 100 * started / participants.length,
    'completion_rate': started == 0 ? null : 100 * completed / started,
    'attempts': participants.fold<int>(
        0, (total, row) => total + _intValue(row['attempts'])),
    'assignments_completed': participants.fold<int>(
        0, (total, row) => total + _intValue(row['assignments_completed'])),
    'active_seconds': participants.fold<int>(
        0, (total, row) => total + _intValue(row['active_seconds'])),
  };
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> _listOfMaps(Object? value) => value is List
    ? value.map((item) => _map(item)).toList()
    : <Map<String, dynamic>>[];

int _intValue(Object? value) => value is num ? value.round() : 0;

String _formatDuration(int seconds) {
  final duration = Duration(seconds: seconds);
  if (seconds > 0 && seconds < 60) return '<1m';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${duration.inMinutes}m';
}

String _durationOrUnavailable(Object? value, Object? availability) {
  if (value is! num || availability == 'not_collected') return 'Not available';
  if (availability == 'not_completed') return 'Not completed';
  return _formatDuration(value.round());
}

String _formatPercent(Object? value) => value is num
    ? '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%'
    : 'Not available';

String _score(Object? value) => value is num
    ? '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%'
    : 'Not available';

String _signedScore(Object? value) {
  if (value is! num) return 'Not available';
  final prefix = value > 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} points';
}

String _availableNumber(Object? value) =>
    value is num ? '$value' : 'Not available';

String _shortTimestamp(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return 'Not available';
  final local = parsed.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _statusLabel(String status) => switch (status) {
      'not_started' => 'Not started',
      'started' => 'Started',
      'partial' => 'Partial',
      'completed' => 'Completed',
      _ => 'Unknown',
    };

IconData _statusIcon(String status) => switch (status) {
      'completed' => Icons.check_circle_rounded,
      'partial' => Icons.timelapse_rounded,
      'started' => Icons.play_circle_outline_rounded,
      _ => Icons.radio_button_unchecked_rounded,
    };

Color _statusColor(String status) => status == 'completed'
    ? AppColors.success
    : status == 'partial'
        ? Colors.orange.shade700
        : AppColors.brand;

String _modeLabel(Object? value) => value == 'submit' ? 'Submit' : 'Run';

String _safeStatus(Object? value) => switch (value?.toString()) {
      'completed' => 'Completed',
      'syntax_error' => 'Syntax error',
      'runtime_error' => 'Runtime error',
      'timeout' => 'Timed out',
      'rejected' => 'Rejected by safety policy',
      'grader_unavailable' => 'Grader unavailable',
      'internal_error' => 'Platform error',
      _ => 'Execution error',
    };

String _healthValue(Object? value) {
  if (value == null) return 'Not applicable';
  if (value == 'pass') return 'PASS';
  return '$value';
}

String _scoreDistribution(Object? value) {
  final distribution = _map(value);
  if (distribution.isEmpty) return 'Not available';
  return distribution.entries
      .map((entry) => '${entry.key}: ${entry.value}')
      .join(' · ');
}
