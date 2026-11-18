import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// [Center] for a page whose content is a width-limited scrolling column.
///
/// The mouse wheel also scrolls the column when the pointer is over the empty
/// margins beside it. Scrolling over the column itself is left to the column.
class ScrollableCenter extends StatelessWidget {
  const ScrollableCenter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        // A scrollable under the pointer registers first and wins; this only
        // runs when the pointer is over the margins.
        GestureBinding.instance.pointerSignalResolver.register(event, (event) {
          final position = _firstVerticalScrollable(context)?.position;
          if (position == null) return;
          position.pointerScroll((event as PointerScrollEvent).scrollDelta.dy);
        });
      },
      child: Center(child: child),
    );
  }

  static ScrollableState? _firstVerticalScrollable(BuildContext context) {
    ScrollableState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement &&
          element.state is ScrollableState &&
          (element.state as ScrollableState).position.axis == Axis.vertical) {
        found = element.state as ScrollableState;
        return;
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return found;
  }
}
