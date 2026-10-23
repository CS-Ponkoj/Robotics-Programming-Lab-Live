import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/services/auth_api.dart';

/// Admin-only list of when accounts signed in and out.
///
/// With [userId] it shows one account; otherwise every account.
class SignInHistoryPage extends StatefulWidget {
  const SignInHistoryPage({super.key, this.userId, this.loginId});

  final String? userId;
  final String? loginId;

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
                'page': '$_page',
                'page_size': '$_pageSize',
                if (widget.userId != null) 'user_id': widget.userId!,
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
    final title = widget.loginId == null
        ? 'Sign-in history'
        : 'Sign-in history: ${widget.loginId}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
              Text(
                'Each row is one sign-in. Times are shown in your local time. '
                'Demo visitors are not recorded.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                  child: Center(child: Text('No sign-ins recorded yet.')),
                )
              else ...[
                for (final item in _items)
                  _SessionCard(item: item, showLogin: widget.userId == null),
                if (pages > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: _page > 1 ? () => _goTo(_page - 1) : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Text('Page $_page of $pages'),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed:
                            _page < pages ? () => _goTo(_page + 1) : null,
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

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.item, required this.showLogin});

  final Map<String, dynamic> item;
  final bool showLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = item['state'] as String;
    final (label, color) = switch (state) {
      'active' => ('Active', Colors.green.shade700),
      'expired' => ('Expired', theme.colorScheme.onSurfaceVariant),
      _ => ('Signed out', theme.colorScheme.primary),
    };
    final signedOut = state == 'signed_out'
        ? formatSignInTime(item['signed_out_at'] as String?)
        : state == 'expired'
            ? 'Session expired ${formatSignInTime(item['expires_at'] as String?)}'
            : 'Still signed in';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (showLogin)
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Login ID: '),
                        TextSpan(
                          text: item['login_id'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: '  ·  ${item['role']}'),
                      ]),
                    ),
                  )
                else
                  const Spacer(),
                Text(label,
                    style: theme.textTheme.labelLarge?.copyWith(color: color)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                'Signed in: ${formatSignInTime(item['signed_in_at'] as String?)}'),
            Text('Signed out: $signedOut'),
            Text(
              'Last active: ${formatSignInTime(item['last_active_at'] as String?)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Local date and time such as `2026-10-23 14:05`.
String formatSignInTime(String? value) {
  final time = value == null ? null : DateTime.tryParse(value)?.toLocal();
  if (time == null) return '—';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}
