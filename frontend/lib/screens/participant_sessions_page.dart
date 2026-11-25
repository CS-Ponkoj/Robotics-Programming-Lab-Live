import 'package:flutter/material.dart';
import 'package:iuse_demo/services/study_data_api.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/floating_app_bar.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

typedef SessionsLoader = Future<Map<String, dynamic>> Function(String id);
typedef SessionsDownloader = Future<bool> Function(String id, String label);

/// One participant at a time: every study session as its own table of what
/// happened, in time order (runs, hints, tutor questions, simulations,
/// quizzes, NASA-TLX). Instructor only; the server checks the role.
class ParticipantSessionsPage extends StatefulWidget {
  const ParticipantSessionsPage({
    super.key,
    required this.participants,
    this.initialParticipantId,
    this.loadSessions = fetchParticipantSessions,
    this.downloadSessions = downloadParticipantSessionsCsv,
  });

  /// Catalog participants: id, participant_code, login_id, feedback_mode.
  final List<Map<String, dynamic>> participants;
  final String? initialParticipantId;
  final SessionsLoader loadSessions;
  final SessionsDownloader downloadSessions;

  @override
  State<ParticipantSessionsPage> createState() =>
      _ParticipantSessionsPageState();
}

String participantOptionLabel(Map<String, dynamic> participant) {
  final login = participant['login_id'] as String? ?? '';
  final code = participant['participant_code'] as String? ?? '';
  final mode = _modeLabel(participant['feedback_mode'] as String? ?? '');
  return [login, code, mode].where((part) => part.isNotEmpty).join(' · ');
}

String _modeLabel(String mode) => switch (mode) {
      'traditional' => 'Traditional',
      'tdd' => 'TDD',
      'tdd_ai' => 'TDD + AI',
      _ => mode,
    };

String _duration(Object? seconds) {
  final value = seconds is int ? seconds : int.tryParse('$seconds') ?? 0;
  if (value < 60) return '$value s';
  final minutes = value ~/ 60;
  if (minutes < 60) return '$minutes min ${value % 60} s';
  return '${minutes ~/ 60} h ${minutes % 60} min';
}

String _time(Object? iso) {
  final text = '${iso ?? ''}';
  if (text.length < 19) return text;
  return '${text.substring(0, 10)} ${text.substring(11, 19)} UTC';
}

class _ParticipantSessionsPageState extends State<ParticipantSessionsPage> {
  String? _participantId;
  Map<String, dynamic>? _data;
  bool _loading = false;
  bool _downloading = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    final ids = widget.participants.map((item) => item['id']).toSet();
    _participantId = ids.contains(widget.initialParticipantId)
        ? widget.initialParticipantId
        : (widget.participants.isEmpty
            ? null
            : widget.participants.first['id'] as String);
    if (_participantId != null) _load();
  }

  Future<void> _load() async {
    final id = _participantId;
    if (id == null) return;
    final request = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.loadSessions(id);
      if (!mounted || request != _requestId) return;
      setState(() => _data = data);
    } catch (error) {
      if (!mounted || request != _requestId) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && request == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    final id = _participantId;
    if (id == null || _downloading) return;
    final person =
        Map<String, dynamic>.from((_data?['participant'] as Map?) ?? const {});
    final label = (person['login_id'] as String?)?.isNotEmpty == true
        ? person['login_id'] as String
        : id.substring(0, 8);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _downloading = true);
    try {
      final saved = await widget.downloadSessions(id, label);
      messenger.showSnackBar(SnackBar(
        content: Text(saved
            ? 'Downloaded sessions_$label.csv'
            : 'CSV download is available in the web app.'),
      ));
    } catch (error) {
      messenger.showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = [
      for (final item in (_data?['sessions'] as List? ?? const []))
        Map<String, dynamic>.from(item as Map),
    ];
    final outside = [
      for (final item in (_data?['outside_sessions'] as List? ?? const []))
        Map<String, dynamic>.from(item as Map),
    ];
    final columns = [
      for (final item in (_data?['columns'] as List? ?? const []))
        Map<String, dynamic>.from(item as Map),
    ];
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: FloatingAppBar(AppBar(
        flexibleSpace: const BrandHeaderGradient(),
        title: const Text('Participant sessions'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(LucideIcons.refreshCw),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: narrow
                ? IconButton.filled(
                    key: const Key('sessions-download'),
                    tooltip: 'Download CSV',
                    onPressed: _data == null || _downloading ? null : _download,
                    icon: const Icon(LucideIcons.download, size: 18),
                  )
                : FilledButton.icon(
                    key: const Key('sessions-download'),
                    onPressed: _data == null || _downloading ? null : _download,
                    icon: const Icon(LucideIcons.download, size: 18),
                    label: const Text('Download CSV'),
                  ),
          ),
        ],
      )),
      body: ListView(
        key: const Key('sessions-list'),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Each study session is its own table of everything the student '
            'did, in time order. Hints, quizzes and NASA-TLX responses do not '
            'store their session, so they are placed in the session that was '
            'running at that time.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (widget.participants.isEmpty)
            const Text('No participants yet.')
          else
            KeyedSubtree(
              key: ValueKey(_participantId),
              child: DropdownButtonFormField<String>(
                key: const Key('sessions-participant'),
                initialValue: _participantId,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Participant', isDense: true),
                items: [
                  for (final participant in widget.participants)
                    DropdownMenuItem<String>(
                      value: participant['id'] as String,
                      child: Text(participantOptionLabel(participant),
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  if (value == null || value == _participantId) return;
                  setState(() {
                    _participantId = value;
                    _data = null;
                  });
                  _load();
                },
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          if (_loading && _data == null)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error!,
                    key: const Key('sessions-error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                TextButton(onPressed: _load, child: const Text('Try again')),
              ],
            ),
          if (_data != null && _error == null) ...[
            _ParticipantHeader(
              participant: Map<String, dynamic>.from(
                  (_data!['participant'] as Map?) ?? const {}),
              sessionCount: sessions.length,
            ),
            const SizedBox(height: AppSpacing.md),
            if (sessions.isEmpty && outside.isEmpty)
              const Text('This participant has no recorded sessions yet.',
                  key: Key('sessions-empty')),
            for (final item in sessions.reversed) ...[
              _SessionCard(
                title: 'Session ${item['number']}',
                subtitle: 'Started ${_time(item['started_at'])} · last active '
                    '${_time(item['last_active_at'])}'
                    '${(item['ended_at'] as String? ?? '').isEmpty ? '' : ' · ended ${_time(item['ended_at'])}'}'
                    ' · active ${_duration(item['active_seconds'])}',
                rows: [
                  for (final row in (item['rows'] as List? ?? const []))
                    Map<String, dynamic>.from(row as Map),
                ],
                columns: columns,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (outside.isNotEmpty)
              _SessionCard(
                title: 'Outside a recorded session',
                subtitle: 'Activity before the first recorded session.',
                rows: outside,
                columns: columns,
              ),
          ],
        ],
      ),
    );
  }
}

class _ParticipantHeader extends StatelessWidget {
  const _ParticipantHeader({
    required this.participant,
    required this.sessionCount,
  });

  final Map<String, dynamic> participant;
  final int sessionCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String field(String key) => participant[key] as String? ?? '';
    return Wrap(
      key: const Key('sessions-participant-header'),
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: [
        for (final (label, value) in [
          ('Login ID', field('login_id')),
          ('Participant code', field('participant_code')),
          ('Mode', _modeLabel(field('feedback_mode'))),
          ('Sessions', '$sessionCount'),
        ])
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.inkMuted)),
              SelectableText(value.isEmpty ? '—' : value,
                  style: theme.textTheme.titleSmall),
            ],
          ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.columns,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> columns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = columns.where((column) => column['key'] != 'attempt_id');
    return Card(
      key: Key('session-card-$title'),
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: rows.isNotEmpty,
        title: Text('$title · ${rows.length} '
            '${rows.length == 1 ? 'activity' : 'activities'}'),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
        children: [
          if (rows.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No recorded activity in this session.'),
            )
          else
            // Text in the table can still be selected and copied.
            SelectionArea(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 40,
                  showCheckboxColumn: false,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 60,
                  columns: [
                    for (final column in shown)
                      DataColumn(label: Text(column['label'] as String)),
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(
                          // Long details are cut in the table; a tap shows
                          // the whole row.
                          onSelectChanged: (_) => showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title:
                                      Text('${row['activity'] ?? 'Activity'}'),
                                  content: SizedBox(
                                    width: 560,
                                    child: SingleChildScrollView(
                                      child: SelectableText([
                                        for (final column in columns)
                                          '${column['label']}: ${row[column['key']] ?? ''}',
                                      ].join(String.fromCharCodes([10, 10]))),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                              ),
                          cells: [
                            for (final column in shown)
                              DataCell(
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxWidth: column['key'] == 'details'
                                          ? 520
                                          : 220),
                                  child: Text(
                                    column['key'] == 'time'
                                        ? '${row['time'] ?? ''}'
                                            .replaceFirst('T', ' ')
                                            .replaceFirst('+00:00', '')
                                        : '${row[column['key']] ?? ''}',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
