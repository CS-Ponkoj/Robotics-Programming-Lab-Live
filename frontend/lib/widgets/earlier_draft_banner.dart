import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Offers code written for an older version of the assignment. It is never
/// loaded into the new version automatically; the student views and copies it.
class EarlierVersionDraftBanner extends StatelessWidget {
  const EarlierVersionDraftBanner({
    super.key,
    required this.code,
    required this.onDismiss,
  });

  final String code;
  final VoidCallback onDismiss;

  Future<void> _view(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('earlier-draft-dialog'),
        title: const Text('Your code from the earlier version'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: SelectableText(
              code,
              key: const Key('earlier-draft-code'),
              style: const TextStyle(fontFamily: 'Courier-New', fontSize: 14),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            key: const Key('earlier-draft-copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('Earlier code copied.')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy all'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('earlier-draft-banner'),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Icon(
              Icons.history_rounded,
              size: 20,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            Text(
              'This assignment was updated. Your code from the earlier '
              'version was kept but not loaded.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
            TextButton(
              key: const Key('earlier-draft-view'),
              onPressed: () => _view(context),
              child: const Text('View and copy'),
            ),
            TextButton(
              key: const Key('earlier-draft-dismiss'),
              onPressed: onDismiss,
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
    );
  }
}
