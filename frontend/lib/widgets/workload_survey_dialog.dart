import 'package:flutter/material.dart';
import 'package:iuse_demo/services/assignment_api.dart';
import 'package:iuse_demo/services/workload_survey_api.dart';
import 'package:iuse_demo/theme/app_theme.dart';

/// Saves a response; replaced in tests.
typedef WorkloadSubmitter = Future<void> Function(
  int assignmentId, {
  required Map<String, int?> ratings,
  required String trigger,
  required DateTime openedAt,
});

/// Shows the Raw NASA-TLX form. Returns true when the answers were saved.
Future<bool> showWorkloadSurveyDialog(
  BuildContext context, {
  required int assignmentId,
  required WorkloadForm form,
  required String trigger,
  WorkloadSubmitter submitter = submitWorkloadSurvey,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => WorkloadSurveyDialog(
      assignmentId: assignmentId,
      form: form,
      trigger: trigger,
      submitter: submitter,
    ),
  );
  return saved == true;
}

/// The six NASA-TLX scales, identical in every feedback mode. Each scale
/// starts unrated (no preset value); higher is worse on every scale.
class WorkloadSurveyDialog extends StatefulWidget {
  const WorkloadSurveyDialog({
    super.key,
    required this.assignmentId,
    required this.form,
    required this.trigger,
    this.submitter = submitWorkloadSurvey,
  });

  final int assignmentId;
  final WorkloadForm form;
  final String trigger;
  final WorkloadSubmitter submitter;

  @override
  State<WorkloadSurveyDialog> createState() => _WorkloadSurveyDialogState();
}

class _WorkloadSurveyDialogState extends State<WorkloadSurveyDialog> {
  final DateTime _openedAt = DateTime.now();
  final Map<String, int?> _ratings = {};
  bool _saving = false;
  String? _error;

  int get _rated => _ratings.values.whereType<int>().length;

  Future<void> _submit() async {
    if (_saving || _rated == 0) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.submitter(
        widget.assignmentId,
        ratings: {
          for (final item in widget.form.items) item.key: _ratings[item.key],
        },
        trigger: widget.trigger,
        openedAt: _openedAt,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is ApiRequestException
            ? error.message
            : 'Your answers could not be saved. Check your connection and '
                'try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unrated = widget.form.items.length - _rated;
    return AlertDialog(
      key: const Key('workload-survey-dialog'),
      title: const Text('How demanding was this assignment?'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.lg),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.form.instructions, style: theme.textTheme.bodyMedium),
            for (final item in widget.form.items) ...[
              const SizedBox(height: AppSpacing.lg),
              _WorkloadScale(
                item: item,
                step: widget.form.step,
                value: _ratings[item.key],
                enabled: !_saving,
                onChanged: (value) =>
                    setState(() => _ratings[item.key] = value),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            if (unrated > 0 && _rated > 0)
              Text(
                '$unrated ${unrated == 1 ? 'scale is' : 'scales are'} not '
                'rated. You can still submit.',
                key: const Key('workload-unrated-note'),
                style: theme.textTheme.bodySmall,
              ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const Key('workload-survey-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('workload-survey-later'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const Key('workload-survey-submit'),
          onPressed: _saving || _rated == 0 ? null : _submit,
          child: Text(_saving ? 'Saving…' : 'Submit'),
        ),
      ],
    );
  }
}

class _WorkloadScale extends StatelessWidget {
  const _WorkloadScale({
    required this.item,
    required this.step,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final WorkloadItem item;
  final int step;
  final int? value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rated = value != null;
    return Column(
      key: Key('workload-scale-${item.key}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              item.title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            rated ? '$value' : 'Not rated',
            key: Key('workload-value-${item.key}'),
            style: theme.textTheme.labelLarge?.copyWith(
              color: rated ? null : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Text(item.question, style: theme.textTheme.bodyMedium),
        Text(
          item.definition,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        // No preset value: until the student taps or drags, the thumb is
        // hidden and screen readers hear "not rated".
        SliderTheme(
          data: rated
              ? SliderTheme.of(context)
              : SliderTheme.of(context).copyWith(
                  thumbShape: SliderComponentShape.noThumb,
                  overlayColor: Colors.transparent,
                  activeTrackColor:
                      theme.colorScheme.surfaceContainerHighest,
                  inactiveTrackColor:
                      theme.colorScheme.surfaceContainerHighest,
                  activeTickMarkColor: theme.colorScheme.outline,
                  inactiveTickMarkColor: theme.colorScheme.outline,
                ),
          child: Slider(
            key: Key('workload-slider-${item.key}'),
            min: 0,
            max: 100,
            divisions: 100 ~/ step,
            value: (value ?? 50).toDouble(),
            label: rated ? '$value' : null,
            semanticFormatterCallback: (_) => rated
                ? '${item.title} $value of 100'
                : '${item.title} not rated',
            onChanged: enabled
                ? (next) => onChanged((next / step).round() * step)
                : null,
            // A tap on the unrated scale's midpoint changes nothing, so
            // onChanged never fires; the end of the touch still rates it.
            onChangeEnd: enabled && !rated
                ? (next) => onChanged((next / step).round() * step)
                : null,
          ),
        ),
        Row(children: [
          Text(item.low, style: theme.textTheme.labelMedium),
          const Spacer(),
          Text(item.high, style: theme.textTheme.labelMedium),
        ]),
      ],
    );
  }
}
