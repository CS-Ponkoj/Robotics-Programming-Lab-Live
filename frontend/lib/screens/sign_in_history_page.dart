import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/services/auth_api.dart';

/// Instructor-only table of one account's sign-ins, opened from
/// Manage accounts by clicking the account.
class SignInHistoryPage extends StatefulWidget {
  const SignInHistoryPage({
    super.key,
    required this.userId,
    required this.loginId,
  });

  final String userId;
  final String loginId;

  @override
  State<SignInHistoryPage> createState() => _SignInHistoryPageState();
}

class _SignInHistoryPageState extends State<SignInHistoryPage> {
  static const _pageSize = 50;

  int _page = 1;
  int _total = 0;
  List<Map<String, dynamic>> _items = [];
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
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/admin/sign-in-history').replace(
              queryParameters: {
                'user_id': widget.userId,
                'page': '$_page',
                'page_size': '$_pageSize',
              },
            ),
            headers: AuthApi.authorizedHeaders(),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception(response.statusCode == 403
            ? 'Only instructors can view sign-in history.'
            : 'Could not load sign-in history (${response.statusCode}).');
      }
      final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final item in data['items'] as List)
            Map<String, dynamic>.from(item as Map),
        ];
        _total = data['total'] as int;
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

  void _goTo(int page) {
    setState(() => _page = page);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = (_total / _pageSize).ceil();
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.loginId}: sign-ins'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
        children: [
          Text(
            'Newest first. Times are in your local time.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Column(
              children: [
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: _load, child: const Text('Try again')),
              ],
            )
          else if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('This account has not signed in yet.')),
            )
          else ...[
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  key: const Key('sign-in-table'),
                  headingTextStyle: theme.textTheme.titleSmall,
                  columns: const [
                    DataColumn(label: Text('Session'), numeric: true),
                    DataColumn(label: Text('Sign in')),
                    DataColumn(label: Text('Sign out')),
                    DataColumn(label: Text('Device')),
                  ],
                  rows: [
                    for (final (index, item) in _items.indexed)
                      DataRow(cells: [
                        // Sessions are numbered from the first ever sign-in.
                        DataCell(Text(
                            '${_total - (_page - 1) * _pageSize - index}')),
                        DataCell(Text(
                            formatSignInTime(item['signed_in_at'] as String?))),
                        DataCell(Text(_signOutText(item))),
                        DataCell(Text(deviceLabel(item['device'] as String?))),
                      ]),
                  ],
                ),
              ),
            ),
            if (pages > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Newer',
                    onPressed: _page > 1 ? () => _goTo(_page - 1) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text('Page $_page of $pages'),
                  IconButton(
                    tooltip: 'Older',
                    onPressed: _page < pages ? () => _goTo(_page + 1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

String _signOutText(Map<String, dynamic> item) => switch (item['state']) {
      'active' => 'Still signed in',
      'expired' =>
        'Not signed out (expired ${formatSignInTime(item['expires_at'] as String?)})',
      _ => formatSignInTime(item['signed_out_at'] as String?),
    };

String deviceLabel(String? device) => switch (device) {
      'phone' => 'Mobile',
      'tablet' => 'Tablet',
      'computer' => 'Computer',
      _ => 'Not recorded',
    };

/// Local date and time such as `2026-10-23 14:05`.
String formatSignInTime(String? value) {
  final time = value == null ? null : DateTime.tryParse(value)?.toLocal();
  if (time == null) return '—';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}
