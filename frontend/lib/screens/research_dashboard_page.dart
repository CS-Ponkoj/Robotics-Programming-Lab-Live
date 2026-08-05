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
            return _ResearchError(
              onRetry: () => setState(() => _data = fetchMyResearchData()),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final summary = Map<String, dynamic>.from(data['summary'] as Map);
          final attempts = (data['attempts'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList()
              .reversed
              .toList();
          return _ResearchPageBody(
            children: [
              Text(
                'Your learning record',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Participant ${summary['participant_code']}. Only you and your instructor can view this record.',
              ),
              const SizedBox(height: AppSpacing.lg),
              ResearchMetricGrid(summary: summary),
              const SizedBox(height: AppSpacing.lg),
              Text('Recent attempts',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              if (attempts.isEmpty)
                const _EmptyResearchState(
                  message: 'Your assignment attempts will appear here.',
                )
              else
                ...attempts.take(20).map(
                      (attempt) => Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${attempt['assignment_id']}'),
                          ),
                          title: Text(
                            'Assignment ${attempt['assignment_id']} · ${attempt['score']}%',
                          ),
                          subtitle: Text(
                            'Version ${attempt['assignment_version']} · ${attempt['mode']} · ${_shortTimestamp(attempt['created_at'])}',
                          ),
                          trailing: Icon(
                            attempt['passed'] == true
                                ? Icons.check_circle_rounded
                                : Icons.pending_actions_rounded,
                            color: attempt['passed'] == true
                                ? AppColors.success
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
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
  });

  final List<Map<String, dynamic>>? initialParticipants;

  @override
  State<InstructorResearchDashboard> createState() =>
      _InstructorResearchDashboardState();
}

class _InstructorResearchDashboardState
    extends State<InstructorResearchDashboard> {
  late Future<List<Map<String, dynamic>>> _participants;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _participants = widget.initialParticipants == null
        ? fetchResearchParticipants()
        : Future.value(widget.initialParticipants);
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
      if (mounted) {
        setState(() => _downloading = false);
      }
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
                child: Text('Student summary CSV'),
              ),
              PopupMenuItem(
                value: 'assignment_attempts:csv',
                child: Text('Assignment attempts CSV'),
              ),
              PopupMenuItem(
                value: 'learning_events:csv',
                child: Text('Learning events CSV'),
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
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _participants,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ResearchError(
              onRetry: () => setState(
                () => _participants = fetchResearchParticipants(),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final participants = snapshot.data!;
          final totals = _aggregateParticipants(participants);
          return _ResearchPageBody(
            children: [
              Text(
                'Class study overview',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Review participation and learning evidence by participant code. Login IDs, passwords, code, and API credentials are excluded.',
              ),
              const SizedBox(height: AppSpacing.lg),
              ResearchMetricGrid(summary: totals, instructor: true),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Participants',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text('${participants.length} enrolled'),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (participants.isEmpty)
                const _EmptyResearchState(
                  message: 'Create student accounts to begin a study.',
                )
              else
                ...participants.map(
                  (participant) => Card(
                    key: Key(
                      'research-participant-${participant['participant_code']}',
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      leading: CircleAvatar(
                        child: Text(
                          participant['participant_code']
                              .toString()
                              .characters
                              .take(2)
                              .toString(),
                        ),
                      ),
                      title: Text(participant['participant_code'].toString()),
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
                                    studentId:
                                        participant['student_id'].toString(),
                                  ),
                                ),
                              ),
                    ),
                  ),
                ),
            ],
          );
        },
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
            return _ResearchError(
              onRetry: () => setState(
                () => _data = fetchStudentResearchData(widget.studentId),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final summary = Map<String, dynamic>.from(data['summary'] as Map);
          final events = (data['events'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList()
              .reversed
              .toList();
          return _ResearchPageBody(
            children: [
              Text(
                summary['participant_code'].toString(),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              ResearchMetricGrid(summary: summary),
              const SizedBox(height: AppSpacing.lg),
              Text('Learning timeline',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              if (events.isEmpty)
                const _EmptyResearchState(
                  message: 'No learning events have been recorded yet.',
                )
              else
                ...events.take(100).map(
                      (event) => ListTile(
                        leading:
                            Icon(_eventIcon(event['event_type'].toString())),
                        title:
                            Text(_eventLabel(event['event_type'].toString())),
                        subtitle: Text(
                          'Assignment ${event['assignment_id'] == '' ? '—' : event['assignment_id']} · ${_shortTimestamp(event['created_at'])}',
                        ),
                      ),
                    ),
            ],
          );
        },
      ),
    );
  }
}

class ResearchMetricGrid extends StatelessWidget {
  const ResearchMetricGrid({
    super.key,
    required this.summary,
    this.instructor = false,
  });

  final Map<String, dynamic> summary;
  final bool instructor;

  @override
  Widget build(BuildContext context) {
    final metrics = instructor
        ? [
            (
              'Participants',
              '${summary['participants']}',
              Icons.groups_rounded
            ),
            (
              'Attempts',
              '${summary['attempts']}',
              Icons.playlist_add_check_rounded
            ),
            (
              'Completed',
              '${summary['assignments_completed']}',
              Icons.verified_rounded
            ),
            (
              'Active time',
              _formatDuration(_intValue(summary['active_seconds'])),
              Icons.schedule_rounded
            ),
          ]
        : [
            (
              'Attempts',
              '${summary['attempts']}',
              Icons.playlist_add_check_rounded
            ),
            (
              'Completed',
              '${summary['assignments_completed']}',
              Icons.verified_rounded
            ),
            ('Best score', '${summary['best_score']}%', Icons.insights_rounded),
            (
              'Active time',
              _formatDuration(_intValue(summary['active_seconds'])),
              Icons.schedule_rounded
            ),
          ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
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
  return {
    'participants': participants.length,
    'attempts': participants.fold<int>(
      0,
      (total, row) => total + _intValue(row['attempts']),
    ),
    'assignments_completed': participants.fold<int>(
      0,
      (total, row) => total + _intValue(row['assignments_completed']),
    ),
    'active_seconds': participants.fold<int>(
      0,
      (total, row) => total + _intValue(row['active_seconds']),
    ),
  };
}

int _intValue(Object? value) => value is num ? value.round() : 0;

String _formatDuration(int seconds) {
  final duration = Duration(seconds: seconds);
  if (seconds > 0 && seconds < 60) {
    return '<1m';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  return '${duration.inMinutes}m';
}

String _shortTimestamp(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) {
    return 'Unknown time';
  }
  final local = parsed.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

IconData _eventIcon(String type) => switch (type) {
      'assignment_opened' => Icons.folder_open_rounded,
      'assignment_run' || 'assignment_submitted' => Icons.play_arrow_rounded,
      'hint_requested' => Icons.lightbulb_outline_rounded,
      'solution_revealed' => Icons.visibility_rounded,
      'ai_tutor_toggled' => Icons.auto_awesome_rounded,
      _ => Icons.timeline_rounded,
    };

String _eventLabel(String type) => switch (type) {
      'assignment_opened' => 'Opened assignment',
      'assignment_run' => 'Ran assignment tests',
      'assignment_submitted' => 'Submitted assignment',
      'hint_requested' => 'Requested a hint',
      'solution_revealed' => 'Revealed worked solution',
      'ai_tutor_toggled' => 'Changed AI tutor setting',
      'workspace_tab_changed' => 'Changed workspace panel',
      _ => type.replaceAll('_', ' '),
    };
