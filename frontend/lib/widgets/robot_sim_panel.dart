import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iuse_demo/models/simulation_trace.dart';
import 'package:iuse_demo/widgets/app_blocks.dart';
import 'package:iuse_demo/widgets/robot_sim_view.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Where the Simulation panel is shown in the workspace.
enum SimPanelMode { docked, floating }

/// Height of the live-readings strip a collapsed panel keeps.
const double kSimStripHeight = 86;

/// Share of the column the docked panel starts with, and its limits.
const double kSimDockDefault = 0.42;
const double kSimDockMin = 0.25;
const double kSimDockMax = 0.7;

/// The bar between the docked Simulation panel and the instructions: drag
/// it, use the arrow keys, or double-click it to reset.
class SimDockDivider extends StatelessWidget {
  const SimDockDivider({
    super.key,
    required this.fraction,
    required this.onChanged,
    required this.columnHeight,
  });

  final double fraction;
  final ValueChanged<double> onChanged;
  final double columnHeight;

  void _set(double value) =>
      onChanged(value.clamp(kSimDockMin, kSimDockMax).toDouble());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      slider: true,
      label: 'Simulation panel height',
      value: '${(fraction * 100).round()} percent',
      increasedValue: '${((fraction + 0.05) * 100).round()} percent',
      decreasedValue: '${((fraction - 0.05) * 100).round()} percent',
      onIncrease: () => _set(fraction + 0.05),
      onDecrease: () => _set(fraction - 0.05),
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.resizeRow,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowUp): _Nudge(-0.05),
          SingleActivator(LogicalKeyboardKey.arrowDown): _Nudge(0.05),
        },
        actions: {
          _Nudge: CallbackAction<_Nudge>(
              onInvoke: (nudge) => _set(fraction + nudge.delta)),
        },
        child: Builder(builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Tooltip(
            message: 'Drag to resize. Double-click to reset.',
            waitDuration: const Duration(milliseconds: 600),
            child: GestureDetector(
              key: const Key('robot-sim-dock-divider'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) =>
                  _set(fraction + details.delta.dy / math.max(columnHeight, 1)),
              onDoubleTap: () => _set(kSimDockDefault),
              child: SizedBox(
                height: 14,
                child: Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: focused
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Nudge extends Intent {
  const _Nudge(this.delta);
  final double delta;
}

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
    this.focus,
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

  /// A moment and view to show, from a failed check's "Watch it".
  final SimFocus? focus;

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
                focus: focus,
              ),
            )
          // Collapsed: live readings once there is a run; before that, the
          // header alone.
          else if (simulation != null)
            SizedBox(
              height: kSimStripHeight,
              child: SimulationBody(
                simulation: simulation,
                onRetry: onSimulate,
                strip: true,
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
    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          if (draggable) ...[
            Tooltip(
              message: 'Drag the header to move this window',
              child: Icon(LucideIcons.gripVertical,
                  key: const Key('robot-sim-grip'),
                  size: 20,
                  color: theme.colorScheme.outline),
            ),
            const SizedBox(width: 4),
          ],
          Icon(LucideIcons.bot,
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
                _StatusChip(isSimulating: isSimulating, simulation: simulation),
              ],
            ),
          ),
          IconButton(
            key: const Key('robot-sim-run'),
            tooltip: 'Simulate: watch your node drive the robot. Not graded.',
            visualDensity: VisualDensity.compact,
            onPressed: isSimulating ? null : onSimulate,
            icon: const Icon(LucideIcons.circlePlay),
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
                  ? LucideIcons.externalLink
                  : LucideIcons.arrowUpToLine),
            ),
          if (onFullScreen != null)
            IconButton(
              key: const Key('robot-sim-fullscreen'),
              tooltip: 'Full screen',
              visualDensity: VisualDensity.compact,
              onPressed: onFullScreen,
              icon: const Icon(LucideIcons.maximize),
            ),
          if (onToggleCollapsed != null)
            IconButton(
              key: const Key('robot-sim-collapse'),
              tooltip: collapsed ? 'Expand simulation' : 'Collapse simulation',
              visualDensity: VisualDensity.compact,
              onPressed: onToggleCollapsed,
              icon: Icon(collapsed
                  ? LucideIcons.chevronDown
                  : LucideIcons.chevronUp),
            ),
          if (onClose != null)
            IconButton(
              key: const Key('robot-sim-close'),
              tooltip: 'Exit full screen',
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: const Icon(LucideIcons.minimize),
            ),
        ],
      ),
    );
  }
}

/// Ready, Running, Replay, or No replay when the node could not drive.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isSimulating, required this.simulation});

  final bool isSimulating;
  final Future<SimulationResultDto>? simulation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<SimulationResultDto>(
      future: simulation,
      builder: (context, snap) {
        final failed = !isSimulating &&
            snap.connectionState == ConnectionState.done &&
            (snap.hasError || snap.data?.replay == null);
        final (label, color, text) = isSimulating ||
                (simulation != null &&
                    snap.connectionState == ConnectionState.waiting)
            ? ('Running', scheme.tertiaryContainer, scheme.onTertiaryContainer)
            : simulation == null
                ? (
                    'Ready',
                    scheme.secondaryContainer,
                    scheme.onSecondaryContainer
                  )
                : failed
                    ? (
                        'No replay',
                        scheme.errorContainer,
                        scheme.onErrorContainer
                      )
                    : (
                        'Replay',
                        scheme.secondaryContainer,
                        scheme.onSecondaryContainer
                      );
        return StatusPill(
          key: const Key('robot-sim-status'),
          label: label,
          color: text,
          background: color,
          dot: true,
          size: PillSize.small,
        );
      },
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
    this.strip = false,
    this.focus,
  });

  final Future<SimulationResultDto>? simulation;
  final VoidCallback? onRetry;
  final bool compact;

  /// A collapsed panel: one line of live readings, or one line of status.
  final bool strip;

  /// A moment and view to show, from a failed check's "Watch it".
  final SimFocus? focus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final future = simulation;
    if (strip) {
      return FutureBuilder<SimulationResultDto>(
        future: future,
        builder: (context, snap) {
          final replay = snap.data?.replay;
          if (replay != null) return _body(theme, snap);
          final text = future == null
              ? 'Press Simulate (▶) to watch your robot.'
              : snap.connectionState == ConnectionState.waiting
                  ? 'Running your node on the robot…'
                  : 'No replay. Expand the panel for details.';
          return Center(
            child: Text(text,
                key: const Key('robot-sim-strip-status'),
                style: theme.textTheme.bodyMedium),
          );
        },
      );
    }
    if (future == null) {
      return _Message(
        icon: LucideIcons.bot,
        title: 'Watch your robot',
        text: 'Press Simulate (▶) to run your node in a small 2D world and replay '
            'how it drives the robot. It is not graded.',
      );
    }
    return FutureBuilder<SimulationResultDto>(
      future: future,
      builder: (context, snap) => _body(theme, snap),
    );
  }

  Widget _body(ThemeData theme, AsyncSnapshot<SimulationResultDto> snap) {
    if (snap.connectionState == ConnectionState.waiting) {
      return const _Message(
        icon: LucideIcons.hourglass,
        title: 'Running your node on the robot…',
        text: 'The grader builds your package and drives the robot for '
            'up to 8 seconds. This takes about 10 seconds.',
        busy: true,
      );
    }
    if (snap.hasError) {
      final error = snap.error;
      return _Message(
        icon: LucideIcons.cloudOff,
        title: 'The simulation could not run',
        text: error is Exception
            ? error.toString().replaceFirst('Exception: ', '')
            : 'Check your connection and try again.',
        action: onRetry == null
            ? null
            : TextButton(onPressed: onRetry, child: const Text('Try again')),
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
      if (strip) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: RobotSimView(
              replay: replay, compact: true, layout: SimViewLayout.strip),
        );
      }
      // Wide and short, as when docked: picture beside the readings, so
      // a short panel still gets a large square.
      if (constraints.maxWidth >= 560 &&
          constraints.maxWidth > constraints.maxHeight * 1.3) {
        final side = math.max(
          160.0,
          math.min(constraints.maxHeight - 76, constraints.maxWidth * 0.58),
        );
        return SingleChildScrollView(
          key: const Key('simulation-results'),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: RobotSimView(
            replay: replay,
            compact: true,
            canvasSide: side,
            layout: SimViewLayout.sideBySide,
            focus: focus,
          ),
        );
      }
      // Room for the telemetry cards and view switch above the square,
      // and the controls and summary under it.
      final reserve = compact ? 266.0 : 326.0;
      final side = math.max(
        120.0,
        math.min(constraints.maxWidth - 24, constraints.maxHeight - reserve),
      );
      return SingleChildScrollView(
        key: const Key('simulation-results'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: RobotSimView(
          replay: replay,
          compact: compact,
          canvasSide: side,
          focus: focus,
        ),
      );
    });
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
