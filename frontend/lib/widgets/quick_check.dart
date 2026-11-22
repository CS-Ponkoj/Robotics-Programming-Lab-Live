import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// One ungraded multiple-choice question inside a lesson. The answer is
/// checked here in the browser and never stored.
class QuickCheck extends StatefulWidget {
  const QuickCheck({
    super.key,
    required this.prompt,
    required this.options,
    required this.answer,
    this.explanation = '',
  });

  final String prompt;
  final List<String> options;
  final int answer;
  final String explanation;

  /// Reads the `data-check` attribute the server writes; null if malformed.
  static QuickCheck? fromAttribute(String? source) {
    if (source == null) return null;
    try {
      final data = jsonDecode(source);
      if (data is! Map) return null;
      final options = data['options'];
      final answer = data['answer'];
      if (data['prompt'] is! String ||
          options is! List ||
          options.length < 2 ||
          answer is! int ||
          answer < 0 ||
          answer >= options.length) {
        return null;
      }
      return QuickCheck(
        prompt: data['prompt'] as String,
        options: [for (final option in options) option.toString()],
        answer: answer,
        explanation: (data['explanation'] ?? '').toString(),
      );
    } on Object {
      return null;
    }
  }

  @override
  State<QuickCheck> createState() => _QuickCheckState();
}

class _QuickCheckState extends State<QuickCheck> {
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = _picked;
    final correct = picked == widget.answer;
    return Container(
      key: const Key('lesson-quick-check'),
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(LucideIcons.circleHelp, size: 16, color: AppColors.brand),
            const SizedBox(width: 6),
            Text(
              'QUICK CHECK · NOT GRADED',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.brand,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w800,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            widget.prompt,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (index, option) in widget.options.indexed)
              _OptionButton(
                key: Key('quick-check-option-$index'),
                label: option,
                state: picked == null
                    ? _OptionState.idle
                    : index == widget.answer && picked == index
                        ? _OptionState.correct
                        : index == picked
                            ? _OptionState.wrong
                            : _OptionState.idle,
                onTap: () => setState(() => _picked = index),
              ),
          ]),
          if (picked != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Row(
                key: const Key('quick-check-feedback'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    correct ? LucideIcons.circleCheck : LucideIcons.circleX,
                    size: 18,
                    color: correct ? AppColors.success : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      correct
                          ? (widget.explanation.isEmpty
                              ? 'Correct.'
                              : 'Correct. ${widget.explanation}')
                          : 'Not quite. Try another answer.',
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _OptionState { idle, correct, wrong }

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    super.key,
    required this.label,
    required this.state,
    required this.onTap,
  });

  final String label;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final (border, fill, ink) = switch (state) {
      _OptionState.correct =>
        (AppColors.success, AppColors.successContainer, AppColors.success),
      _OptionState.wrong =>
        (error, error.withValues(alpha: 0.08), error),
      _OptionState.idle => (AppColors.borderStrong, Colors.white, AppColors.ink),
    };
    return Semantics(
      button: true,
      selected: state != _OptionState.idle,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          side: BorderSide(
              color: border, width: state == _OptionState.idle ? 1 : 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                label,
                style: TextStyle(
                  color: ink,
                  fontWeight: state == _OptionState.idle
                      ? FontWeight.w500
                      : FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
