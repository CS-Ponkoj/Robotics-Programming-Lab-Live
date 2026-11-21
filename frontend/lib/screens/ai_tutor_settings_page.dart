import 'package:flutter/material.dart';
import 'package:iuse_demo/widgets/floating_app_bar.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/services/instructor_api.dart';
import 'package:iuse_demo/widgets/scrollable_center.dart';

typedef AiSettingsLoader = Future<Map<String, dynamic>> Function(String token);
typedef AiSettingsSaver = Future<Map<String, dynamic>> Function(
  String token, {
  required bool enabled,
  required int dailyLimit,
});

/// The course AI tutor switch and daily limit, with why each assignment can or
/// cannot use the AI tutor. AI stays optional: built-in hints always work.
class AiTutorSettingsPage extends StatefulWidget {
  const AiTutorSettingsPage({
    super.key,
    this.load = fetchAiTutorSettings,
    this.save = saveAiTutorSettings,
  });

  final AiSettingsLoader load;
  final AiSettingsSaver save;

  @override
  State<AiTutorSettingsPage> createState() => _AiTutorSettingsPageState();
}

class _AiTutorSettingsPageState extends State<AiTutorSettingsPage> {
  Map<String, dynamic>? _status;
  String? _error;
  String? _message;
  bool _saving = false;
  bool _enabled = false;
  final _limit = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  void _show(Map<String, dynamic> status) {
    _status = status;
    _enabled = status['enabled'] == true;
    _limit.text = '${status['daily_limit'] ?? 20}';
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final status = await widget.load(AuthApi.token ?? '');
      if (mounted) setState(() => _show(status));
    } on Object catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _save() async {
    final limit = int.tryParse(_limit.text.trim());
    if (limit == null || limit < 1 || limit > 200) {
      setState(
          () => _message = 'Daily limit must be a whole number from 1 to 200.');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final status = await widget.save(AuthApi.token ?? '',
          enabled: _enabled, dailyLimit: limit);
      if (mounted) {
        setState(() {
          _show(status);
          _message = 'Saved.';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
            () => _message = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;
    return Scaffold(
      appBar: FloatingAppBar(AppBar(
        flexibleSpace: const BrandHeaderGradient(),
        title: const Text('AI tutor'))),
      body: _error != null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ]),
            )
          : status == null
              ? const Center(child: CircularProgressIndicator())
              : ScrollableCenter(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                      children: [
                        Text(
                          'Students get an AI answer only when all of these hold. '
                          'Otherwise they get the built-in hints and a short '
                          'reason. AI answers are labelled as AI.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        _Gate(
                          key: const Key('ai-gate-key'),
                          ok: status['key_configured'] == true,
                          title: 'Server key',
                          detail: status['key_configured'] == true
                              ? 'Configured on the server. The key is never shown.'
                              : 'Not configured. On the lab PC run '
                                  'scripts/set-live-secret.ps1, then restart the '
                                  'live stack.',
                        ),
                        Card(
                          child: Column(children: [
                            SwitchListTile(
                              key: const Key('ai-course-switch'),
                              title: const Text('AI tutoring for this course'),
                              subtitle: const Text(
                                  'Off by default. Students still choose to turn '
                                  'it on in each assignment.'),
                              value: _enabled,
                              onChanged: _saving
                                  ? null
                                  : (value) => setState(() => _enabled = value),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              // Wraps on phones instead of overflowing.
                              child: Wrap(
                                spacing: 16,
                                runSpacing: 12,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 220,
                                    child: TextField(
                                      key: const Key('ai-daily-limit'),
                                      controller: _limit,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'AI answers per student per day',
                                      ),
                                    ),
                                  ),
                                  FilledButton(
                                    key: const Key('ai-save'),
                                    onPressed: _saving ? null : _save,
                                    child: Text(_saving ? 'Saving…' : 'Save'),
                                  ),
                                  if (_message != null)
                                    Text(_message!,
                                        key: const Key('ai-save-message')),
                                ],
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        Text('Assignments', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'An assignment can use the AI tutor once a named '
                          'instructor has approved its AI test cases for its '
                          'current version (backend/ai_evaluation_cases).',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        for (final item
                            in (status['assignments'] as List? ?? []))
                          if (item is Map)
                            _Gate(
                              ok: item['reviewed'] == true,
                              title: '${item['title']} · v${item['version']}',
                              detail: item['reviewed'] == true
                                  ? 'AI test cases approved.'
                                  : 'AI test cases waiting for instructor review.',
                            ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate({
    super.key,
    required this.ok,
    required this.title,
    required this.detail,
  });

  final bool ok;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(
          ok ? Icons.check_circle_rounded : Icons.pending_outlined,
          color: ok ? Colors.green.shade700 : scheme.outline,
          semanticLabel: ok ? 'Ready' : 'Not ready',
        ),
        title: Text(title),
        subtitle: Text(detail),
      ),
    );
  }
}
