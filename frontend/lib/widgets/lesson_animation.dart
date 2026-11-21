import 'package:flutter/material.dart';
import 'package:iuse_demo/theme/app_theme.dart';

/// A lesson animation that starts as a still image and plays only when the
/// reader asks, so moving content can always be stopped (WCAG 2.2.2).
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
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    final url = _playing ? widget.animationUrl : widget.stillUrl;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 460),
        child: Semantics(
          image: true,
          label: '${widget.description} '
              '${_playing ? 'Animation playing.' : 'Animation stopped.'}',
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
        onPressed: () => setState(() => _playing = !_playing),
        icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
        label: Text(_playing ? 'Stop animation' : 'Play animation'),
      ),
    ]);
  }
}
