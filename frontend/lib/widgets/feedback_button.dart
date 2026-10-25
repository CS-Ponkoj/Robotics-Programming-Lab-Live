import 'package:flutter/material.dart';
import 'package:iuse_demo/services/feedback_api.dart';
import 'package:iuse_demo/state/feedback_page_tracker.dart';

/// "Feedback" button shown on every signed-in page.
class FeedbackButton extends StatelessWidget {
  const FeedbackButton({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _HoverHint(
      message: 'Report a problem or send feedback about this page',
      child: Material(
        color: colors.primary,
        elevation: 6,
        shadowColor: colors.primary.withValues(alpha: 0.5),
        shape: StadiumBorder(
          side: BorderSide(color: colors.onPrimary.withValues(alpha: 0.6)),
        ),
        child: InkWell(
          key: const Key('feedback-button'),
          customBorder: const StadiumBorder(),
          onTap: () {
            final navigatorContext = navigatorKey.currentContext;
            if (navigatorContext == null) return;
            showFeedbackDialog(navigatorContext, feedbackPages.currentPage);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.feedback_rounded, size: 20, color: colors.onPrimary),
                const SizedBox(width: 8),
                Text(
                  'Feedback',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The button floats above the app's navigator, where there is no overlay
/// for a hover tooltip; screen readers still get the description.
class _HoverHint extends StatelessWidget {
  const _HoverHint({required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Overlay.maybeOf(context) == null) {
      return Semantics(tooltip: message, child: child);
    }
    return Tooltip(message: message, child: child);
  }
}

/// True while the feedback form is open, so the floating button can hide.
final feedbackFormOpen = ValueNotifier<bool>(false);

/// Opens the form full screen on phones, where the on-screen keyboard would
/// otherwise squeeze a small dialog, and as a dialog on wider screens.
Future<void> showFeedbackDialog(BuildContext context, String page) async {
  final narrow = MediaQuery.sizeOf(context).width < 600;
  feedbackFormOpen.value = true;
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => FeedbackDialog(page: page, fullScreen: narrow),
    );
  } finally {
    feedbackFormOpen.value = false;
  }
}

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({
    super.key,
    required this.page,
    this.fullScreen = false,
  });

  final String page;
  final bool fullScreen;

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
        const SnackBar(
          content: Text('Thank you. Your feedback was sent.'),
          behavior: SnackBarBehavior.floating,
          // Float above the Feedback button in the bottom-left corner.
          margin: EdgeInsets.fromLTRB(16, 0, 16, 72),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _form(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Page: ${widget.page}',
            key: const Key('feedback-page-label'),
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('feedback-category'),
          // `value` works on CI's Flutter 3.32.8 (`initialValue` needs 3.33+).
          value: _category,
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
          textInputAction: TextInputAction.newline,
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
    );
  }

  Widget _sendButton() {
    return FilledButton(
      key: const Key('feedback-send'),
      onPressed: _sending ? null : _send,
      child: _sending
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Send'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.fullScreen) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Cancel',
              onPressed: _sending ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
            title: const Text('Send feedback'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _sendButton(),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _form(theme),
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      title: const Text('Send feedback'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(child: _form(theme)),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        _sendButton(),
      ],
    );
  }
}
