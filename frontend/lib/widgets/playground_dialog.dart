import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iuse_demo/models/playground_diagram.dart';
import 'package:iuse_demo/models/playground_result_dto.dart';
import 'package:iuse_demo/services/assignment_api.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/playground_diagram.dart';

typedef PlaygroundRunner = Future<PlaygroundResultDto> Function(
  int assignmentId,
  String code,
  String arguments,
);

/// Parameter names of [functionName] in [code], or an empty list.
List<String> playgroundParameterNames(String code, String functionName) {
  final match = RegExp(
    r'def\s+' + RegExp.escape(functionName) + r'\s*\(([^)]*)\)',
  ).firstMatch(code);
  if (match == null) return const [];
  return match
      .group(1)!
      .split(',')
      .map((part) => part.split(RegExp(r'[:=]')).first.trim())
      .where((name) => name.isNotEmpty)
      .toList();
}

/// Lets a student call their own function with inputs they choose.
///
/// Practice only: calls are not graded, not saved, and never count as an
/// attempt, so students can explore edge cases freely.
class PlaygroundDialog extends StatefulWidget {
  const PlaygroundDialog({
    super.key,
    required this.assignmentId,
    required this.functionName,
    required this.code,
    this.initialArguments = '',
    this.onArgumentsChanged,
    this.simulationConfig = const {},
    this.runner = tryAssignmentInputs,
  });

  final int assignmentId;
  final String functionName;
  final String code;
  final String initialArguments;
  final ValueChanged<String>? onArgumentsChanged;

  /// The assignment's simulation configuration; its `diagram` block, when
  /// present, draws the student's inputs and returned values.
  final Map<String, dynamic> simulationConfig;
  final PlaygroundRunner runner;

  @override
  State<PlaygroundDialog> createState() => _PlaygroundDialogState();
}

class _PlaygroundDialogState extends State<PlaygroundDialog> {
  late final TextEditingController _arguments;
  bool _running = false;
  PlaygroundResultDto? _result;
  String? _requestError;

  @override
  void initState() {
    super.initState();
    _arguments = TextEditingController(text: widget.initialArguments);
  }

  @override
  void dispose() {
    _arguments.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _requestError = null;
    });
    try {
      final result = await widget.runner(
        widget.assignmentId,
        widget.code,
        _arguments.text,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on ApiRequestException catch (error) {
      if (!mounted) return;
      setState(() => _requestError = error.message);
    } on TimeoutException {
      if (!mounted) return;
      setState(
        () => _requestError =
            'The code runner took too long to answer. Please try again.',
      );
    } on Object {
      if (!mounted) return;
      setState(
        () => _requestError =
            'Your inputs could not be run. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parameters = playgroundParameterNames(widget.code, widget.functionName);
    final signature = '${widget.functionName}(${parameters.join(', ')})';

    return AlertDialog(
      key: const Key('playground-dialog'),
      title: const Text('Try your own inputs'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Call your function with values you choose and see what it '
                'returns. This is practice only: it is not graded, not saved, '
                'and does not count as an attempt.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              SelectableText(
                signature,
                key: const Key('playground-signature'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'roboto-mono',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('playground-arguments'),
                controller: _arguments,
                enabled: !_running,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                style: const TextStyle(fontFamily: 'roboto-mono'),
                decoration: const InputDecoration(
                  labelText: 'Inputs, separated by commas',
                  hintText: '(0, 0), (4, 0), 2.5, [1, 2]',
                  helperText:
                      'Use numbers, text, tuples, lists, or dictionaries.',
                  border: OutlineInputBorder(),
                ),
                onChanged: widget.onArgumentsChanged,
                onSubmitted: (_) => _run(),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('playground-run-button'),
                  onPressed: _running ? null : _run,
                  icon: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(_running ? 'Running…' : 'Run my function'),
                ),
              ),
              if (_requestError != null) ...[
                const SizedBox(height: AppSpacing.md),
                _PlaygroundMessage(
                  key: const Key('playground-request-error'),
                  icon: Icons.error_outline_rounded,
                  color: theme.colorScheme.error,
                  text: _requestError!,
                ),
              ] else if (_result != null) ...[
                const SizedBox(height: AppSpacing.md),
                _PlaygroundResultView(
                  result: _result!,
                  diagram: buildPlaygroundDiagram(
                    widget.simulationConfig,
                    _result!,
                    parameterNames: parameters,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('playground-close-button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _PlaygroundResultView extends StatelessWidget {
  const _PlaygroundResultView({required this.result, this.diagram});

  final PlaygroundResultDto result;
  final PlaygroundDiagramData? diagram;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'roboto-mono',
      height: 1.4,
    );

    return Column(
      key: const Key('playground-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(result.call, style: mono),
        const SizedBox(height: AppSpacing.sm),
        if (!result.success)
          _PlaygroundMessage(
            icon: Icons.error_outline_rounded,
            color: theme.colorScheme.error,
            text: result.error.isEmpty
                ? 'Your function did not finish running.'
                : result.error,
          )
        else ...[
          if (result.hasWrongReturnCount)
            _PlaygroundMessage(
              key: const Key('playground-return-count-warning'),
              icon: Icons.warning_amber_rounded,
              color: AppColors.performanceMid,
              text:
                  'Your function returned ${result.returnCount} values, but the '
                  'assignment expects ${result.expectedReturnCount} in a fixed order.',
            ),
          if (result.returnedSingleValue)
            _PlaygroundMessage(
              key: const Key('playground-return-count-warning'),
              icon: Icons.warning_amber_rounded,
              color: AppColors.performanceMid,
              text:
                  'Your function returned one value, but the assignment expects '
                  '${result.expectedReturnCount} values returned together.',
            ),
          if (result.values.isEmpty)
            SelectableText('Returned: ${result.returned}', style: mono)
          else
            Table(
              key: const Key('playground-values'),
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(2),
              },
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
              children: [
                for (final item in result.values)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        child: Text(item.label, style: theme.textTheme.bodySmall),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        child: SelectableText(
                          item.text,
                          style: mono?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
        ],
        if (diagram != null) ...[
          const SizedBox(height: AppSpacing.md),
          PlaygroundDiagram(data: diagram!),
        ],
        if (result.output.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('Printed output', style: theme.textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: SingleChildScrollView(
              child: SelectableText(result.output.trimRight(), style: mono),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Compare these values with your own hand calculation. Run tests '
          'when you are ready to be graded.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PlaygroundMessage extends StatelessWidget {
  const _PlaygroundMessage({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SelectableText(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
