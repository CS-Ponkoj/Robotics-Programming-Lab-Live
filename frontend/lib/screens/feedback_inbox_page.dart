import 'package:flutter/material.dart';
import 'package:iuse_demo/services/feedback_api.dart';

/// Instructor view of feedback sent from the Feedback button on any page.
class FeedbackInboxPage extends StatefulWidget {
  const FeedbackInboxPage({super.key});

  @override
  State<FeedbackInboxPage> createState() => _FeedbackInboxPageState();
}

class _FeedbackInboxPageState extends State<FeedbackInboxPage> {
  static const _pageSize = 50;

  String? _status = 'new';
  int _page = 1;
  int _total = 0;
  int _newCount = 0;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  final Set<String> _updating = {};

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
      final data = await fetchFeedback(
          status: _status, page: _page, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final item in data['items'] as List)
            Map<String, dynamic>.from(item as Map),
        ];
        _total = data['total'] as int;
        _newCount = data['new_count'] as int;
      });
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(Map<String, dynamic> item, String status) async {
    final id = item['id'] as String;
    setState(() => _updating.add(id));
    try {
      await updateFeedbackStatus(id, status);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _updating.remove(id));
    }
  }

  void _filter(String? status) {
    setState(() {
      _status = status;
      _page = 1;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = (_total / _pageSize).ceil();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedback'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const Key('feedback-filter-new'),
                    label: Text('New ($_newCount)'),
                    selected: _status == 'new',
                    onSelected: (_) => _filter('new'),
                  ),
                  ChoiceChip(
                    label: const Text('Resolved'),
                    selected: _status == 'resolved',
                    onSelected: (_) => _filter('resolved'),
                  ),
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _status == null,
                    onSelected: (_) => _filter(null),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Column(
                  children: [
                    Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                    const SizedBox(height: 8),
                    OutlinedButton(
                        onPressed: _load, child: const Text('Try again')),
                  ],
                )
              else if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No feedback here yet.')),
                )
              else ...[
                for (final item in _items)
                  _FeedbackCard(
                    item: item,
                    busy: _updating.contains(item['id']),
                    onToggle: () => _setStatus(
                        item, item['status'] == 'new' ? 'resolved' : 'new'),
                  ),
                if (pages > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: _page > 1
                            ? () {
                                setState(() => _page--);
                                _load();
                              }
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Text('Page $_page of $pages'),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: _page < pages
                            ? () {
                                setState(() => _page++);
                                _load();
                              }
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.item,
    required this.busy,
    required this.onToggle,
  });

  final Map<String, dynamic> item;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final created =
        DateTime.tryParse(item['created_at'] as String? ?? '')?.toLocal();
    final sender = item['sender_login_id'] as String? ??
        (item['sender_role'] == 'demo' ? 'Demo visitor' : 'Unknown');
    final resolved = item['status'] == 'resolved';
    final when = created == null
        ? ''
        : '${created.year}-${_two(created.month)}-${_two(created.day)} '
            '${_two(created.hour)}:${_two(created.minute)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  label: Text(feedbackCategories[item['category']] ??
                      item['category'].toString()),
                  visualDensity: VisualDensity.compact,
                ),
                Text(item['page'] as String, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(item['message'] as String,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$sender (${item['sender_role']}) · $when',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                TextButton.icon(
                  onPressed: busy ? null : onToggle,
                  icon: Icon(resolved
                      ? Icons.undo_rounded
                      : Icons.check_circle_outline_rounded),
                  label: Text(resolved ? 'Reopen' : 'Mark resolved'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');
