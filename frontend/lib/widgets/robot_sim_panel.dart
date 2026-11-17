import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iuse_demo/models/simulation_trace.dart';
import 'package:iuse_demo/widgets/robot_sim_view.dart';

/// Where the Simulation panel is shown in the workspace.
enum SimPanelMode { docked, floating }

/// Square Simulation panel: header with view controls, then the replay.
///
/// It can sit docked above the instructions, float as its own window, open
/// full screen, or collapse to its header. The replay is visual only.
class RobotSimPanel extends StatelessWidget {
  const RobotSimPanel({
    super.key,
    required this.simulation,
    required this.isSimulating,
    required this.onSimulate,
    this.mode = SimPanelMode.docked,
    this.collapsed = false,
    this.onToggleCollapsed,
    this.onToggleMode,
    this.onFullScreen,
    this.onClose,
    this.onHeaderDrag,
  });

  final Future<SimulationResultDto>? simulation;
  final bool isSimulating;
  final VoidCallback? onSimulate;
  final SimPanelMode mode;
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  /// Pop out (docked) or dock again (floating); null hides the button.
  final VoidCallback? onToggleMode;
  final VoidCallback? onFullScreen;

  /// Closes a full-screen view.
  final VoidCallback? onClose;

  /// Drags a floating window by its header.
  final GestureDragUpdateCallback? onHeaderDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = _PanelHeader(
      isSimulating: isSimulating,
      simulation: simulation,
      onSimulate: onSimulate,
      mode: mode,
      collapsed: collapsed,
      onToggleCollapsed: onToggleCollapsed,
      onToggleMode: onToggleMode,
      onFullScreen: onFullScreen,
      onClose: onClose,
      draggable: onHeaderDrag != null,
    );
    return Material(
      key: const Key('robot-sim-panel'),
      color: theme.colorScheme.surface,
      elevation: mode == SimPanelMode.floating ? 8 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: collapsed ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onHeaderDrag != null)
            MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(onPanUpdate: onHeaderDrag, child: header),
            )
          else
            header,
          if (!collapsed)
            Expanded(
              child: SimulationBody(
                simulation: simulation,
                onRetry: onSimulate,
                compact: onClose == null,
              ),
            ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.isSimulating,
    required this.simulation,
    required this.onSimulate,
    required this.mode,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onToggleMode,
    required this.onFullScreen,
    required this.onClose,
    this.draggable = false,
  });

  /// Shows a grip: the header moves the floating window.
  final bool draggable;
  final bool isSimulating;
  final Future<SimulationResultDto>? simulation;
  final VoidCallback? onSimulate;
  final SimPanelMode mode;
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;
  final VoidCallback? onToggleMode;
  final VoidCallback? onFullScreen;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = isSimulating
        ? 'Running'
        : simulation == null
            ? 'Ready'
            : 'Replay';
    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          if (draggable) ...[
            Tooltip(
              message: 'Drag the header to move this window',
              child: Icon(Icons.drag_indicator_rounded,
                  key: const Key('robot-sim-grip'),
                  size: 20,
                  color: theme.colorScheme.outline),
            ),
            const SizedBox(width: 4),
          ],
          Icon(Icons.smart_toy_outlined,
              size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          // Title and status take the free space, so the view buttons stay
          // at the right edge.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text('Simulation',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Container(
                  key: const Key('robot-sim-status'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSimulating
                        ? theme.colorScheme.tertiaryContainer
                        : theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(status, style: theme.textTheme.labelSmall),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('robot-sim-run'),
            tooltip: 'Simulate: watch your node drive the robot. Not graded.',
            visualDensity: VisualDensity.compact,
            onPressed: isSimulating ? null : onSimulate,
            icon: const Icon(Icons.play_circle_outline_rounded),
          ),
          if (onToggleMode != null)
            IconButton(
              key: const Key('robot-sim-pop-out'),
              tooltip: mode == SimPanelMode.docked
                  ? 'Pop out into its own window'
                  : 'Dock above the instructions',
              visualDensity: VisualDensity.compact,
              onPressed: onToggleMode,
              icon: Icon(mode == SimPanelMode.docked
                  ? Icons.open_in_new_rounded
                  : Icons.vertical_align_top_rounded),
            ),
          if (onFullScreen != null)
            IconButton(
              key: const Key('robot-sim-fullscreen'),
              tooltip: 'Full screen',
              visualDensity: VisualDensity.compact,
              onPressed: onFullScreen,
              icon: const Icon(Icons.fullscreen_rounded),
            ),
          if (onToggleCollapsed != null)
            IconButton(
              key: const Key('robot-sim-collapse'),
              tooltip: collapsed ? 'Expand simulation' : 'Collapse simulation',
              visualDensity: VisualDensity.compact,
              onPressed: onToggleCollapsed,
              icon: Icon(collapsed
                  ? Icons.expand_more_rounded
                  : Icons.expand_less_rounded),
            ),
          if (onClose != null)
            IconButton(
              key: const Key('robot-sim-close'),
              tooltip: 'Exit full screen',
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: const Icon(Icons.fullscreen_exit_rounded),
            ),
        ],
      ),
    );
  }
}

/// The replay, or what to do before there is one.
class SimulationBody extends StatelessWidget {
  const SimulationBody({
    super.key,
    required this.simulation,
    required this.onRetry,
    this.compact = true,
  });

  final Future<SimulationResultDto>? simulation;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final future = simulation;
    if (future == null) {
      return _Message(
        icon: Icons.smart_toy_outlined,
        title: 'Watch your robot',
        text: 'Press Simulate to run your node in a small 2D world and replay '
            'how it drives the robot. It is not graded.',
      );
    }
    return FutureBuilder<SimulationResultDto>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Message(
            icon: Icons.hourglass_top_rounded,
            title: 'Running your node on the robot…',
            text: 'The grader builds your package and drives the robot for '
                'up to 8 seconds. This takes about 10 seconds.',
            busy: true,
          );
        }
        if (snap.hasError) {
          final error = snap.error;
          return _Message(
            icon: Icons.cloud_off_rounded,
            title: 'The simulation could not run',
            text: error is Exception
                ? error.toString().replaceFirst('Exception: ', '')
                : 'Check your connection and try again.',
            action: onRetry == null
                ? null
                : TextButton(
                    onPressed: onRetry, child: const Text('Try again')),
          );
        }
        final result = snap.data;
        final replay = result?.replay;
        if (result == null) return const SizedBox.shrink();
        if (replay == null) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Card(
              key: const Key('simulation-error'),
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('The simulation could not start',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SelectableText(result.error.isEmpty
                        ? 'Your node did not drive the robot.'
                        : result.error),
                  ],
                ),
              ),
            ),
          );
        }
        return LayoutBuilder(builder: (context, constraints) {
          // Room under the square for the controls, readout, and summary.
          final reserve = compact ? 190.0 : 260.0;
          final side = math.max(
            120.0,
            math.min(
                constraints.maxWidth - 24, constraints.maxHeight - reserve),
          );
          return SingleChildScrollView(
            key: const Key('simulation-results'),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: RobotSimView(
              replay: replay,
              compact: compact,
              canvasSide: side,
            ),
          );
        });
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.busy = false,
    this.action,
  });

  final IconData icon;
  final String title;
  final String text;
  final bool busy;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox.square(
                  dimension: 32,
                  child: CircularProgressIndicator(strokeWidth: 3))
            else
              Icon(icon, size: 36, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(text,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
