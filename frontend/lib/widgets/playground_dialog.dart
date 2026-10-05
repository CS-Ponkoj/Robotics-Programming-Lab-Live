import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iuse_demo/models/playground_diagram.dart';
import 'package:iuse_demo/models/playground_parameter.dart';
import 'package:iuse_demo/models/playground_result_dto.dart';
import 'package:iuse_demo/services/assignment_api.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/playground_diagram.dart';

typedef PlaygroundRunner =
    Future<PlaygroundResultDto> Function(
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
/// attempt, so students can explore edge cases freely. When the assignment
/// describes its inputs, each one gets its own labelled field.
class PlaygroundDialog extends StatefulWidget {
  const PlaygroundDialog({
    super.key,
    required this.assignmentId,
    required this.functionName,
    required this.code,
    this.initialArguments = '',
    this.sampleArguments = '',
    this.parameters = const [],
    this.onArgumentsChanged,
    this.simulationConfig = const {},
    this.runner = tryAssignmentInputs,
  });

  final int assignmentId;
  final String functionName;
  final String code;

  /// The student's last inputs this session, as one line.
  final String initialArguments;

  /// The assignment's example inputs (the instructions' public example call),
  /// used to prefill empty inputs so a first run works with one click.
  final String sampleArguments;

  /// Described inputs; when present each gets its own labelled field.
  final List<PlaygroundParameterSpec> parameters;
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
  late final List<TextEditingController> _fields;
  bool _oneLine = false;
  bool _running = false;
  PlaygroundResultDto? _result;
  String? _requestError;
  String? _modeNote;
  Map<int, String> _fieldErrors = const {};

  bool get _hasFields => widget.parameters.isNotEmpty;

  bool get _useFields => _hasFields && !_oneLine;

  String get _currentArguments => _useFields
      ? joinPlaygroundArguments(_fields.map((field) => field.text))
      : _arguments.text;

  @override
  void initState() {
    super.initState();
    final start = widget.initialArguments.isNotEmpty
        ? widget.initialArguments
        : widget.sampleArguments;
    _arguments = TextEditingController(text: start);
    final parts = splitPlaygroundArguments(start);
    final fits = parts != null && parts.length == widget.parameters.length;
    _fields = [
      for (var index = 0; index < widget.parameters.length; index++)
        TextEditingController(
          text: fits ? parts[index] : widget.parameters[index].example,
        ),
    ];
    // Earlier inputs that do not fit the fields stay editable as one line.
    _oneLine = _hasFields && widget.initialArguments.isNotEmpty && !fits;
  }

  @override
  void dispose() {
    _arguments.dispose();
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  bool get _differsFromExample => _useFields
      ? [
          for (var index = 0; index < _fields.length; index++)
            _fields[index].text.trim() != widget.parameters[index].example,
        ].contains(true)
      : _arguments.text != widget.sampleArguments;

  void _inputsChanged({int? field}) {
    setState(() {
      _modeNote = null;
      if (field != null && _fieldErrors.containsKey(field)) {
        _fieldErrors = Map.of(_fieldErrors)..remove(field);
      }
    });
    widget.onArgumentsChanged?.call(_currentArguments);
  }

  void _useSample() {
    for (var index = 0; index < _fields.length; index++) {
      _fields[index].text = widget.parameters[index].example;
    }
    _arguments.text = widget.sampleArguments;
    setState(() {
      _fieldErrors = const {};
      _modeNote = null;
    });
    widget.onArgumentsChanged?.call(_currentArguments);
  }

  void _toggleMode() {
    if (_useFields) {
      _arguments.text = joinPlaygroundArguments(_fields.map((f) => f.text));
      setState(() {
        _oneLine = true;
        _fieldErrors = const {};
      });
      return;
    }
    final parts = splitPlaygroundArguments(_arguments.text);
    if (parts == null || parts.length != _fields.length) {
      setState(
        () => _modeNote =
            'Could not split this line into ${_fields.length} inputs. '
            'Check the commas and brackets, then try again.',
      );
      return;
    }
    for (var index = 0; index < parts.length; index++) {
      _fields[index].text = parts[index];
    }
    setState(() {
      _oneLine = false;
      _modeNote = null;
    });
  }

  Future<void> _run() async {
    if (_running) return;
    if (_useFields) {
      final empty = <int, String>{
        for (var index = 0; index < _fields.length; index++)
          if (_fields[index].text.trim().isEmpty)
            index: 'Enter a value for ${widget.parameters[index].label}.',
      };
      if (empty.isNotEmpty) {
        setState(() {
          _fieldErrors = empty;
          _requestError = null;
          _result = null;
        });
        return;
      }
    }
    setState(() {
      _running = true;
      _requestError = null;
      _fieldErrors = const {};
    });
    try {
      final result = await widget.runner(
        widget.assignmentId,
        widget.code,
        _currentArguments,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on PlaygroundInputException catch (error) {
      if (!mounted) return;
      setState(() {
        _result = null;
        if (_useFields && error.fieldErrors.isNotEmpty) {
          // Show each problem on the field it belongs to.
          _fieldErrors = error.fieldErrors;
        } else {
          _requestError = error.message;
        }
      });
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

  Widget _field(int index) {
    final spec = widget.parameters[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        key: Key('playground-field-${spec.name}'),
        controller: _fields[index],
        enabled: !_running,
        minLines: 1,
        maxLines: spec.kind == 'angle_map' || spec.kind == 'list_of_points'
            ? 3
            : 1,
        maxLength: 400,
        style: const TextStyle(fontFamily: 'roboto-mono'),
        decoration: InputDecoration(
          labelText: spec.label,
          helperText: spec.helper,
          helperMaxLines: 3,
          errorText: _fieldErrors[index],
          errorMaxLines: 3,
          counterText: '',
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => _inputsChanged(field: index),
        onSubmitted: (_) => _run(),
      ),
    );
  }

  List<Widget> _fieldList(ThemeData theme) {
    final groups = <String>[];
    for (final spec in widget.parameters) {
      if (!groups.contains(spec.group)) groups.add(spec.group);
    }
    final grouped = groups.length > 1 || groups.single.isNotEmpty;
    return [
      for (final group in groups) ...[
        if (grouped && group.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Semantics(
              header: true,
              child: Text(group, style: theme.textTheme.titleSmall),
            ),
          ),
        for (var index = 0; index < widget.parameters.length; index++)
          if (widget.parameters[index].group == group) _field(index),
      ],
    ];
  }

  Widget _oneLineField() {
    return TextField(
      key: const Key('playground-arguments'),
      controller: _arguments,
      enabled: !_running,
      minLines: 1,
      maxLines: 4,
      maxLength: 2000,
      style: const TextStyle(fontFamily: 'roboto-mono'),
      decoration: InputDecoration(
        labelText: 'Inputs, separated by commas',
        hintText: '(0, 0), (4, 0), 2.5, [1, 2]',
        helperText: widget.sampleArguments.isEmpty
            ? 'Use numbers, text, tuples, lists, or dictionaries.'
            : 'Starts with the example from the instructions. Edit freely.',
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => _inputsChanged(),
      onSubmitted: (_) => _run(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parameters = playgroundParameterNames(
      widget.code,
      widget.functionName,
    );
    final signature = '${widget.functionName}(${parameters.join(', ')})';
    final showExampleButton =
        widget.sampleArguments.isNotEmpty && _differsFromExample;

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
              Text('Function', style: theme.textTheme.labelMedium),
              SelectableText(
                signature,
                key: const Key('playground-signature'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'roboto-mono',
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_useFields)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'Each box starts with the example from the instructions. '
                    'Edit freely.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              if (_useFields) ..._fieldList(theme) else _oneLineField(),
              if (_modeNote != null)
                _PlaygroundMessage(
                  key: const Key('playground-mode-note'),
                  icon: Icons.info_outline_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  text: _modeNote!,
                ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      if (_hasFields)
                        TextButton.icon(
                          key: const Key('playground-mode-toggle'),
                          onPressed: _running ? null : _toggleMode,
                          icon: Icon(
                            _useFields
                                ? Icons.short_text_rounded
                                : Icons.view_list_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _useFields ? 'Edit as one line' : 'Edit each input',
                          ),
                        ),
                      // Offer the example back once the student has changed it.
                      if (showExampleButton)
                        TextButton.icon(
                          key: const Key('playground-use-example'),
                          onPressed: _running ? null : _useSample,
                          icon: const Icon(Icons.restore_rounded, size: 18),
                          label: const Text('Use example inputs'),
                        ),
                    ],
                  ),
                  FilledButton.icon(
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
                ],
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
                        child: Text(
                          item.label,
                          style: theme.textTheme.bodySmall,
                        ),
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
