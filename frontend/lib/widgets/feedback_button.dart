import 'package:flutter/material.dart';
import 'package:iuse_demo/services/feedback_api.dart';
import 'package:iuse_demo/state/feedback_page_tracker.dart';

/// Small "Feedback" button shown on every signed-in page.
class FeedbackButton extends StatelessWidget {
  const FeedbackButton({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Report a problem or send feedback about this page',
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 3,
        shape: StadiumBorder(
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          key: const Key('feedback-button'),
          customBorder: const StadiumBorder(),
          onTap: () {
            final navigatorContext = navigatorKey.currentContext;
            if (navigatorContext == null) return;
            showDialog<void>(
              context: navigatorContext,
              builder: (_) => FeedbackDialog(page: feedbackPages.currentPage),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.feedback_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Feedback',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({super.key, required this.page});

  final String page;

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _message = TextEditingController();
  String _category = 'bug';
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Please describe the problem or idea.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await submitFeedback(
          page: widget.page, category: _category, message: text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        const SnackBar(content: Text('Thank you. Your feedback was sent.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Send feedback'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Page: ${widget.page}',
                  key: const Key('feedback-page-label'),
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('feedback-category'),
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final entry in feedbackCategories.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _sending
                    ? null
                    : (value) => setState(() => _category = value ?? 'bug'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('feedback-message'),
                controller: _message,
                enabled: !_sending,
                minLines: 4,
                maxLines: 8,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'What happened, or what would help?',
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null)
                Text(_error!,
                    key: const Key('feedback-error'),
                    style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('feedback-send'),
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send'),
        ),
      ],
    );
  }
}
