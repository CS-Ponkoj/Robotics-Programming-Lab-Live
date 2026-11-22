import 'package:flutter/material.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A lesson animation that plays on its own and always offers a Stop button,
/// so moving content can be stopped (WCAG 2.2.2). Readers whose device asks
/// for reduced motion see the still image until they press Play.
class LessonAnimation extends StatefulWidget {
  const LessonAnimation({
    super.key,
    required this.stillUrl,
    required this.animationUrl,
    required this.description,
  });

  final String stillUrl;
  final String animationUrl;
  final String description;

  @override
  State<LessonAnimation> createState() => _LessonAnimationState();
}

class _LessonAnimationState extends State<LessonAnimation> {
  /// The reader's own choice; until they press a button, the device setting decides.
  bool? _chosen;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final playing = _chosen ?? !reducedMotion;
    return _frame(playing);
  }

  Widget _frame(bool playing) {
    final url = playing ? widget.animationUrl : widget.stillUrl;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 460),
        child: Semantics(
          image: true,
          label: '${widget.description} '
              '${playing ? 'Animation playing.' : 'Animation stopped.'}',
          child: ExcludeSemantics(
            child: Image.network(
              url,
              key: ValueKey(url),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) => Padding(
                padding: const EdgeInsets.all(12),
                child: Text('This animation could not be loaded.',
                    style: TextStyle(color: AppColors.inkMuted)),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        key: const Key('lesson-animation-toggle'),
        onPressed: () => setState(() => _chosen = !playing),
        icon: Icon(playing ? LucideIcons.square : LucideIcons.play),
        label: Text(playing ? 'Stop animation' : 'Play animation'),
      ),
    ]);
  }
}
