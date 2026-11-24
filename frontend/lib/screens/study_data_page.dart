import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iuse_demo/services/study_data_api.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/floating_app_bar.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

typedef CatalogLoader = Future<Map<String, dynamic>> Function({
  bool includeTestAccounts,
});
typedef TableLoader = Future<Map<String, dynamic>> Function(
  String table, {
  required StudyDataFilters filters,
  int page,
  int pageSize,
  String? sort,
  bool descending,
});
typedef CsvDownloader = Future<bool> Function(
  String table, {
  required StudyDataFilters filters,
  String? sort,
  bool descending,
});
typedef CodeLoader = Future<Map<String, dynamic>> Function(String attemptId);

const _modeLabels = {
  'traditional': 'Traditional',
  'tdd': 'TDD',
  'tdd_ai': 'TDD + AI',
};

/// Instructor view of every table the app collects, with CSV download.
class StudyDataPage extends StatefulWidget {
  const StudyDataPage({
    super.key,
    this.loadCatalog = fetchStudyDataCatalog,
    this.loadTable = fetchStudyDataTable,
    this.downloadCsv = downloadStudyDataCsv,
    this.loadCode = fetchAttemptCode,
    this.initialTable = 'ai_questions_and_hints',
  });

  final CatalogLoader loadCatalog;
  final TableLoader loadTable;
  final CsvDownloader downloadCsv;
  final CodeLoader loadCode;
  final String initialTable;

  @override
  State<StudyDataPage> createState() => _StudyDataPageState();
}

class _StudyDataPageState extends State<StudyDataPage> {
  static const _pageSize = 50;

  List<Map<String, dynamic>> _tables = [];
  List<Map<String, dynamic>> _participants = [];
  List<Map<String, dynamic>> _assignments = [];
  String? _catalogError;
  bool _catalogLoading = true;

  late String _table = widget.initialTable;
  StudyDataFilters _filters = const StudyDataFilters();
  String? _sort;
  bool _descending = true;
  int _page = 1;

  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;
  bool _downloading = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    try {
      final catalog = await widget.loadCatalog(
          includeTestAccounts: _filters.includeTestAccounts);
      if (!mounted) return;
      List<Map<String, dynamic>> list(String key) => [
            for (final item in (catalog[key] as List? ?? const []))
              Map<String, dynamic>.from(item as Map),
          ];
      setState(() {
        _tables = list('tables');
        _participants = list('participants');
        _assignments = list('assignments');
        if (_tables.isNotEmpty &&
            !_tables.any((table) => table['name'] == _table)) {
          _table = _tables.first['name'] as String;
        }
      });
      await _loadTable();
    } catch (error) {
      if (mounted) setState(() => _catalogError = _message(error));
    } finally {
      if (mounted) setState(() => _catalogLoading = false);
    }
  }

  Future<void> _loadTable() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.loadTable(
        _table,
        filters: _filters,
        page: _page,
        pageSize: _pageSize,
        sort: _sort,
        descending: _descending,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() => _data = data);
    } catch (error) {
      if (mounted && requestId == _requestId) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Map<String, dynamic>? get _tableInfo {
    for (final table in _tables) {
      if (table['name'] == _table) return table;
    }
    return null;
  }

  void _selectTable(String name) {
    if (name == _table) return;
    setState(() {
      _table = name;
      _sort = null;
      _descending = true;
      _page = 1;
      _data = null;
    });
    _loadTable();
  }

  void _applyFilters(StudyDataFilters filters, {bool reloadCatalog = false}) {
    setState(() {
      _filters = filters;
      _page = 1;
    });
    if (reloadCatalog) {
      _loadCatalog();
    } else {
      _loadTable();
    }
  }

  void _sortBy(String key) {
    setState(() {
      if (_sort == key) {
        _descending = !_descending;
      } else {
        _sort = key;
        _descending = false;
      }
      _page = 1;
    });
    _loadTable();
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await widget.downloadCsv(
        _table,
        filters: _filters,
        sort: _sort,
        descending: _descending,
      );
      messenger.showSnackBar(SnackBar(
        content: Text(saved
            ? 'Downloaded $_table.csv'
            : 'CSV download is available in the web app.'),
      ));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(_message(error))));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FloatingAppBar(AppBar(
        flexibleSpace: const BrandHeaderGradient(),
        title: const Text('Study data'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadTable,
            icon: const Icon(LucideIcons.refreshCw),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Builder(builder: (context) {
              final onPressed =
                  _downloading || _catalogLoading || _tables.isEmpty
                      ? null
                      : _download;
              final icon = _downloading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.download, size: 18);
              // Phones keep the page title readable with an icon button.
              if (MediaQuery.sizeOf(context).width < 600) {
                return IconButton.filled(
                  key: const Key('study-data-download'),
                  tooltip: 'Download CSV',
                  onPressed: onPressed,
                  icon: icon,
                );
              }
              return FilledButton.icon(
                key: const Key('study-data-download'),
                onPressed: onPressed,
                icon: icon,
                label: const Text('Download CSV'),
              );
            }),
          ),
        ],
      )),
      body: _catalogError != null
          ? _ErrorState(message: _catalogError!, onRetry: _loadCatalog)
          : _catalogLoading && _tables.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 960;
                  final content = _TableArea(
                    info: _tableInfo,
                    data: _data,
                    loading: _loading,
                    error: _error,
                    filters: _filters,
                    participants: _participants,
                    assignments: _assignments,
                    sort: _sort,
                    descending: _descending,
                    page: _page,
                    pageSize: _pageSize,
                    tablePicker: wide
                        ? null
                        : _TableDropdown(
                            tables: _tables,
                            selected: _table,
                            onSelected: _selectTable,
                          ),
                    onFilters: _applyFilters,
                    onSort: _sortBy,
                    onRetry: _loadTable,
                    onPage: (page) {
                      setState(() => _page = page);
                      _loadTable();
                    },
                    onOpenRow: _openRow,
                  );
                  if (!wide) return content;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 260,
                        child: _TableList(
                          tables: _tables,
                          selected: _table,
                          onSelected: _selectTable,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: content),
                    ],
                  );
                }),
    );
  }

  void _openRow(Map<String, dynamic> row, List<Map<String, dynamic>> columns) {
    showDialog<void>(
      context: context,
      builder: (context) => _RowDialog(
        row: row,
        columns: columns,
        loadCode: widget.loadCode,
      ),
    );
  }
}

String formatCell(Object? value) {
  if (value == null) return '';
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is Map || value is List) {
    if (value is Map && value.isEmpty) return '';
    return jsonEncode(value);
  }
  return '$value';
}

class _TableList extends StatelessWidget {
  const _TableList({
    required this.tables,
    required this.selected,
    required this.onSelected,
  });

  final List<Map<String, dynamic>> tables;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
          child: Text('Tables',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.inkMuted,
                  )),
        ),
        for (final table in tables)
          ListTile(
            key: Key('study-table-${table['name']}'),
            dense: true,
            selected: table['name'] == selected,
            selectedTileColor: AppColors.brandTint,
            title: Text(table['title'] as String),
            onTap: () => onSelected(table['name'] as String),
          ),
      ],
    );
  }
}

class _TableDropdown extends StatelessWidget {
  const _TableDropdown({
    required this.tables,
    required this.selected,
    required this.onSelected,
  });

  final List<Map<String, dynamic>> tables;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: const Key('study-table-picker'),
      initialValue: selected,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Table'),
      items: [
        for (final table in tables)
          DropdownMenuItem(
            value: table['name'] as String,
            child: Text(table['title'] as String),
          ),
      ],
      onChanged: (value) {
        if (value != null) onSelected(value);
      },
    );
  }
}

class _TableArea extends StatelessWidget {
  const _TableArea({
    required this.info,
    required this.data,
    required this.loading,
    required this.error,
    required this.filters,
    required this.participants,
    required this.assignments,
    required this.sort,
    required this.descending,
    required this.page,
    required this.pageSize,
    required this.tablePicker,
    required this.onFilters,
    required this.onSort,
    required this.onRetry,
    required this.onPage,
    required this.onOpenRow,
  });

  final Map<String, dynamic>? info;
  final Map<String, dynamic>? data;
  final bool loading;
  final String? error;
  final StudyDataFilters filters;
  final List<Map<String, dynamic>> participants;
  final List<Map<String, dynamic>> assignments;
  final String? sort;
  final bool descending;
  final int page;
  final int pageSize;
  final Widget? tablePicker;
  final void Function(StudyDataFilters, {bool reloadCatalog}) onFilters;
  final ValueChanged<String> onSort;
  final VoidCallback onRetry;
  final ValueChanged<int> onPage;
  final void Function(Map<String, dynamic>, List<Map<String, dynamic>>)
      onOpenRow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = (data?['total'] as int?) ?? 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
      children: [
        if (tablePicker != null) ...[
          tablePicker!,
          const SizedBox(height: AppSpacing.md),
        ],
        Text(info?['title'] as String? ?? '',
            style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(info?['description'] as String? ?? '',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.inkMuted)),
        const SizedBox(height: AppSpacing.md),
        _FilterBar(
          filters: filters,
          participants: participants,
          assignments: assignments,
          showAssignment: info?['has_assignment'] == true,
          showDates: info?['has_dates'] != false,
          onChanged: onFilters,
        ),
        const SizedBox(height: AppSpacing.md),
        if (error != null)
          _ErrorState(message: error!, onRetry: onRetry)
        else if (data == null)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (data!['truncated'] == true)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'This table is cut short at its size limit. Narrow the '
                'filters to see every row.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          _DataGrid(
            columns: [
              for (final column in data!['columns'] as List)
                Map<String, dynamic>.from(column as Map),
            ],
            rows: [
              for (final row in data!['rows'] as List)
                Map<String, dynamic>.from(row as Map),
            ],
            sort: sort,
            descending: descending,
            onSort: onSort,
            onOpenRow: onOpenRow,
          ),
          const SizedBox(height: AppSpacing.sm),
          _Pager(
            page: page,
            pageSize: pageSize,
            total: total,
            onPage: loading ? null : onPage,
          ),
        ],
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.participants,
    required this.assignments,
    required this.showAssignment,
    required this.showDates,
    required this.onChanged,
  });

  final StudyDataFilters filters;
  final List<Map<String, dynamic>> participants;
  final List<Map<String, dynamic>> assignments;
  final bool showAssignment;
  final bool showDates;
  final void Function(StudyDataFilters, {bool reloadCatalog}) onChanged;

  StudyDataFilters _copy({
    Object? studentId = _keep,
    Object? assignmentId = _keep,
    Object? feedbackMode = _keep,
    Object? dateFrom = _keep,
    Object? dateTo = _keep,
    bool? includeTestAccounts,
  }) =>
      StudyDataFilters(
        studentId:
            studentId == _keep ? filters.studentId : studentId as String?,
        assignmentId:
            assignmentId == _keep ? filters.assignmentId : assignmentId as int?,
        feedbackMode: feedbackMode == _keep
            ? filters.feedbackMode
            : feedbackMode as String?,
        dateFrom: dateFrom == _keep ? filters.dateFrom : dateFrom as DateTime?,
        dateTo: dateTo == _keep ? filters.dateTo : dateTo as DateTime?,
        includeTestAccounts: includeTestAccounts ?? filters.includeTestAccounts,
      );

  static String _day(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickDates(BuildContext context) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: DateTime(now.year + 1),
      initialDateRange: filters.dateFrom != null && filters.dateTo != null
          ? DateTimeRange(start: filters.dateFrom!, end: filters.dateTo!)
          : null,
    );
    if (range != null) {
      onChanged(_copy(dateFrom: range.start, dateTo: range.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFilters = filters.studentId != null ||
        filters.assignmentId != null ||
        filters.feedbackMode != null ||
        filters.dateFrom != null;
    final participantIds = {for (final p in participants) p['id'] as String};
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          // Keyed by value so Clear filters also resets what is shown.
          child: KeyedSubtree(
            key: ValueKey('participant-${filters.studentId}'),
            child: DropdownButtonFormField<String?>(
              key: const Key('study-filter-participant'),
              initialValue: participantIds.contains(filters.studentId)
                  ? filters.studentId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Participant', isDense: true),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('All participants')),
                for (final participant in participants)
                  DropdownMenuItem<String?>(
                    value: participant['id'] as String,
                    child: Text(participant['participant_code'] as String,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => onChanged(_copy(studentId: value)),
            ),
          ),
        ),
        if (showAssignment)
          SizedBox(
            width: 220,
            child: KeyedSubtree(
              key: ValueKey('assignment-${filters.assignmentId}'),
              child: DropdownButtonFormField<int?>(
                key: const Key('study-filter-assignment'),
                initialValue: filters.assignmentId,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Assignment', isDense: true),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('All assignments')),
                  for (final assignment in assignments)
                    DropdownMenuItem<int?>(
                      value: assignment['id'] as int,
                      child: Text(assignment['label'] as String,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => onChanged(_copy(assignmentId: value)),
              ),
            ),
          ),
        SizedBox(
          width: 170,
          child: KeyedSubtree(
            key: ValueKey('mode-${filters.feedbackMode}'),
            child: DropdownButtonFormField<String?>(
              key: const Key('study-filter-mode'),
              initialValue: filters.feedbackMode,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Mode', isDense: true),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('All modes')),
                for (final entry in _modeLabels.entries)
                  DropdownMenuItem<String?>(
                      value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) => onChanged(_copy(feedbackMode: value)),
            ),
          ),
        ),
        if (showDates)
          OutlinedButton.icon(
            key: const Key('study-filter-dates'),
            onPressed: () => _pickDates(context),
            icon: const Icon(LucideIcons.calendar, size: 18),
            label: Text(filters.dateFrom == null
                ? 'Any date'
                : '${_day(filters.dateFrom!)} to ${_day(filters.dateTo!)}'),
          )
        else
          Text(
            'Whole study: the date filter does not apply here.',
            key: const Key('study-filter-no-dates'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.inkMuted),
          ),
        FilterChip(
          key: const Key('study-filter-test-accounts'),
          label: const Text('Include test accounts'),
          side: const BorderSide(color: AppColors.border),
          selected: filters.includeTestAccounts,
          onSelected: (value) => onChanged(
            _copy(includeTestAccounts: value, studentId: null),
            reloadCatalog: true,
          ),
        ),
        if (hasFilters)
          TextButton(
            key: const Key('study-filter-clear'),
            onPressed: () => onChanged(StudyDataFilters(
                includeTestAccounts: filters.includeTestAccounts)),
            child: const Text('Clear filters'),
          ),
      ],
    );
  }
}

const _keep = Object();

class _DataGrid extends StatelessWidget {
  const _DataGrid({
    required this.columns,
    required this.rows,
    required this.sort,
    required this.descending,
    required this.onSort,
    required this.onOpenRow,
  });

  final List<Map<String, dynamic>> columns;
  final List<Map<String, dynamic>> rows;
  final String? sort;
  final bool descending;
  final ValueChanged<String> onSort;
  final void Function(Map<String, dynamic>, List<Map<String, dynamic>>)
      onOpenRow;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        key: const Key('study-data-empty'),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: const Center(
          child: Text('No records match these filters yet.'),
        ),
      );
    }
    final sortIndex = columns.indexWhere((column) => column['key'] == sort);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('study-data-table'),
          showCheckboxColumn: false,
          headingRowColor: WidgetStatePropertyAll(AppColors.brandTint),
          dataRowMinHeight: 40,
          dataRowMaxHeight: 64,
          sortColumnIndex: sortIndex >= 0 ? sortIndex : null,
          sortAscending: !descending,
          columns: [
            for (final column in columns)
              DataColumn(
                label: Tooltip(
                  message: column['help'] as String? ?? '',
                  child: Text(column['label'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                onSort: (_, __) => onSort(column['key'] as String),
              ),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                onSelectChanged: (_) => onOpenRow(row, columns),
                cells: [
                  for (final column in columns)
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        _cellText(column['key'] as String, row[column['key']]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static String _cellText(String key, Object? value) {
    if (key == 'feedback_mode' && value is String) {
      return _modeLabels[value] ?? value;
    }
    // Long record IDs: the first block is enough to tell rows apart here;
    // the record dialog and the CSV keep the full ID.
    if (key.endsWith('_id') && value is String && value.length > 12) {
      return '${value.substring(0, 8)}…';
    }
    return formatCell(value);
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.onPage,
  });

  final int page;
  final int pageSize;
  final int total;
  final ValueChanged<int>? onPage;

  @override
  Widget build(BuildContext context) {
    final pages = total == 0 ? 1 : (total / pageSize).ceil();
    final first = total == 0 ? 0 : (page - 1) * pageSize + 1;
    final last = (page * pageSize).clamp(0, total);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('$first–$last of $total',
            key: const Key('study-data-count'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.inkMuted)),
        const SizedBox(width: AppSpacing.sm),
        IconButton(
          tooltip: 'Previous page',
          onPressed:
              page > 1 && onPage != null ? () => onPage!(page - 1) : null,
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        IconButton(
          key: const Key('study-data-next'),
          tooltip: 'Next page',
          onPressed:
              page < pages && onPage != null ? () => onPage!(page + 1) : null,
          icon: const Icon(LucideIcons.chevronRight),
        ),
      ],
    );
  }
}

class _RowDialog extends StatefulWidget {
  const _RowDialog({
    required this.row,
    required this.columns,
    required this.loadCode,
  });

  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> columns;
  final CodeLoader loadCode;

  @override
  State<_RowDialog> createState() => _RowDialogState();
}

class _RowDialogState extends State<_RowDialog> {
  String? _code;
  String? _codeError;
  bool _codeLoading = false;

  String? get _attemptId {
    final value = widget.row['attempt_id'];
    return value is String && value.isNotEmpty ? value : null;
  }

  Future<void> _showCode() async {
    setState(() {
      _codeLoading = true;
      _codeError = null;
    });
    try {
      final data = await widget.loadCode(_attemptId!);
      if (mounted) setState(() => _code = data['code'] as String? ?? '');
    } catch (error) {
      if (mounted) {
        setState(() =>
            _codeError = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _codeLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Record'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final column in widget.columns)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(column['label'] as String,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: AppColors.inkMuted)),
                      SelectableText(
                        DataGridText.full(
                            column['key'] as String, widget.row[column['key']]),
                      ),
                    ],
                  ),
                ),
              if (_attemptId != null) ...[
                const Divider(),
                if (_code == null)
                  OutlinedButton.icon(
                    key: const Key('study-data-view-code'),
                    onPressed: _codeLoading ? null : _showCode,
                    icon: const Icon(LucideIcons.code, size: 18),
                    label: Text(_codeLoading
                        ? 'Loading code…'
                        : 'View the code of this attempt'),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            'Code of this attempt (shown here only, never '
                            'in a CSV)',
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: AppColors.inkMuted)),
                      ),
                      IconButton(
                        tooltip: 'Copy code',
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: _code!)),
                        icon: const Icon(LucideIcons.copy, size: 18),
                      ),
                    ],
                  ),
                  Container(
                    key: const Key('study-data-code'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16222E),
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: SelectableText(
                      _code!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        color: Color(0xFFE6EDF3),
                      ),
                    ),
                  ),
                ],
                if (_codeError != null)
                  Text(_codeError!,
                      style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Full (untruncated) cell text for the record dialog.
abstract final class DataGridText {
  static String full(String key, Object? value) {
    if (key == 'feedback_mode' && value is String) {
      return _modeLabels[value] ?? value;
    }
    if (value is Map || value is List) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    final text = formatCell(value);
    return text.isEmpty ? '—' : text;
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
