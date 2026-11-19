import 'package:flutter/material.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/services/instructor_api.dart';
import 'package:iuse_demo/widgets/app_blocks.dart';
import 'package:iuse_demo/widgets/scrollable_center.dart';

typedef InsightsLoader = Future<Map<String, dynamic>> Function(
    String token, int assignmentId);

/// Plain-words names for the patterns the grader observes.
const _patternNames = {
  'speed-too-high': 'Drives faster than 0.3 m/s',
  'speed-too-low': 'Drives slower than 0.1 m/s',
  'infinity-treated-as-obstacle': 'Treats +inf as an obstacle',
  'stops-too-early': 'Stops while the wall is far away',
  'stops-too-late': 'Keeps driving when the wall is close',
  'wrong-threshold-direction': 'Drive and stop branches swapped',
  'must-drive-first': 'Never drives, so stopping cannot count',
  'does-not-resume': 'Does not drive again after the wall moves',
  'turns-while-driving': 'Turns (angular.z is not 0.0)',
  'publishes-too-rarely': 'Publishes fewer than 5 commands a second',
  'build-node-returns-none': 'build_node() does not return the node',
};

const _outcomeNames = {
  'stopped_and_resumed': 'Stopped, then drove again',
  'stopped': 'Stopped, never drove again',
  'collided': 'Hit the wall',
  'kept_driving': 'Still driving at the end',
  'never_moved': 'Never moved',
};

/// Where students get stuck on one assignment version: aggregates only, no
/// names, login IDs, or code.
class AssignmentInsightsPage extends StatefulWidget {
  const AssignmentInsightsPage({
    super.key,
    required this.assignmentId,
    required this.title,
    this.load = fetchAssignmentInsights,
  });

  final int assignmentId;
  final String title;
  final InsightsLoader load;

  @override
  State<AssignmentInsightsPage> createState() => _AssignmentInsightsPageState();
}

class _AssignmentInsightsPageState extends State<AssignmentInsightsPage> {
  late Future<Map<String, dynamic>> _insights;

  @override
  void initState() {
    super.initState();
    _insights = widget.load(AuthApi.token ?? '', widget.assignmentId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Insights · ${widget.title}')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _insights,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(snap.error.toString().replaceFirst('Exception: ', '')),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() => _insights =
                      widget.load(AuthApi.token ?? '', widget.assignmentId)),
                  child: const Text('Retry'),
                ),
              ]),
            );
          }
          final data = snap.data!;
          final attempted = data['students_attempted'] as int? ?? 0;
          String number(Object? value, String unit) => value is num
              ? '${value % 1 == 0 ? value.toInt() : value} $unit'
              : '—';
          return ScrollableCenter(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: ListView(
                key: const Key('insights-list'),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                children: [
                  Text(
                    'Version ${data['version']}. Students only: instructor, '
                    'demo, and inactive accounts are left out. Each student '
                    'counts once, by their latest attempt.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    _Stat('Students attempted', '$attempted'),
                    _Stat('Students passed', '${data['students_passed'] ?? 0}'),
                    _Stat('Attempts', '${data['attempts'] ?? 0}'),
                    _Stat('Median attempts to pass',
                        number(data['median_attempts_to_pass'], '')),
                    _Stat('Median time to pass',
                        number(data['median_minutes_to_pass'], 'min')),
                  ]),
                  if (attempted == 0) ...[
                    const SizedBox(height: 24),
                    const Text('No student has attempted this version yet.'),
                  ] else ...[
                    _Section(
                      title: 'Checks students are failing',
                      empty: 'Every student passes every check.',
                      rows: [
                        for (final item in (data['checks'] as List? ?? []))
                          if (item is Map)
                            (
                              '${item['label']}',
                              item['students_failing'] as int? ?? 0
                            ),
                      ],
                      total: attempted,
                    ),
                    _Section(
                      title: 'What the grader saw the robots do',
                      empty: 'No pattern recognised in failed checks.',
                      rows: [
                        for (final item
                            in (data['observed_patterns'] as List? ?? []))
                          if (item is Map)
                            (
                              _patternNames[item['hint_key']] ??
                                  '${item['hint_key']}',
                              item['students'] as int? ?? 0
                            ),
                      ],
                      total: attempted,
                    ),
                    _Section(
                      title: 'Simulation runs',
                      empty: 'No simulation runs yet.',
                      rows: [
                        for (final item
                            in (data['simulation_outcomes'] as List? ?? []))
                          if (item is Map)
                            (
                              _outcomeNames[item['outcome']] ??
                                  '${item['outcome']}',
                              item['runs'] as int? ?? 0
                            ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: StatTile(label: label, value: value),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.empty,
    required this.rows,
    this.total,
  });

  final String title;
  final String empty;
  final List<(String, int)> rows;

  /// Students attempted; when set, rows read "n of total students".
  final int? total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final most =
        rows.fold<int>(1, (high, row) => row.$2 > high ? row.$2 : high);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (rows.isEmpty) Text(empty, style: theme.textTheme.bodyMedium),
          for (final (label, count) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Semantics(
                label: '$label: $count'
                    '${total == null ? ' runs' : ' of $total students'}',
                excludeSemantics: true,
                child: Row(children: [
                  Expanded(flex: 3, child: Text(label)),
                  Expanded(
                    flex: 2,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: count / (total ?? most),
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: Text(total == null ? '$count' : '$count of $total',
                        textAlign: TextAlign.end),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
