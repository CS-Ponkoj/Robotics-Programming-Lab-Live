import 'dart:math' as math;

/// A replay of the student's ROS 2 node driving a robot in a small 2D world.
///
/// Visual only: the server stores no submission or score for it. Distances
/// are metres, angles radians, and a null reading means nothing in range.
class SimulationFrame {
  const SimulationFrame({
    required this.t,
    required this.x,
    required this.y,
    required this.theta,
    required this.linear,
    required this.angular,
    this.front,
    this.ranges = const [],
  });

  final double t;
  final double x;
  final double y;
  final double theta;
  final double linear;
  final double angular;
  final double? front;
  final List<double?> ranges;

  static SimulationFrame? fromJson(Object? json) {
    if (json is! Map) return null;
    final values = [
      for (final key in ['t', 'x', 'y', 'theta', 'linear', 'angular'])
        _number(json[key])
    ];
    if (values.any((value) => value == null)) return null;
    final ranges = json['ranges'];
    return SimulationFrame(
      t: values[0]!,
      x: values[1]!,
      y: values[2]!,
      theta: values[3]!,
      linear: values[4]!,
      angular: values[5]!,
      front: _number(json['front']),
      ranges: ranges is List
          ? [for (final value in ranges) _number(value)]
          : const [],
    );
  }
}

class SimulationEvent {
  const SimulationEvent(
      {required this.t, required this.type, this.front, this.walls});

  final double t;
  final String type;
  final double? front;

  /// Every wall's position after a `wall_moved` event.
  final List<List<double>>? walls;

  static SimulationEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final t = _number(json['t']);
    final type = json['type'];
    if (t == null || type is! String) return null;
    return SimulationEvent(
      t: t,
      type: type,
      front: _number(json['front']),
      walls: json['walls'] == null ? null : _walls(json['walls']),
    );
  }
}

class SimulationReplay {
  const SimulationReplay({
    required this.walls,
    required this.frames,
    required this.events,
    required this.outcome,
    required this.robotRadius,
    required this.angleMinDeg,
    required this.angleIncrementDeg,
    required this.durationSeconds,
  });

  final List<List<double>> walls;
  final List<SimulationFrame> frames;
  final List<SimulationEvent> events;
  final String outcome;
  final double robotRadius;
  final double angleMinDeg;
  final double angleIncrementDeg;
  final double durationSeconds;

  double get endTime => frames.isEmpty ? 0 : frames.last.t;

  /// The last frame at or before [time].
  SimulationFrame frameAt(double time) {
    var low = 0;
    var high = frames.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (frames[middle].t <= time) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return frames[low];
  }

  /// Wall positions at [time], following any `wall_moved` events.
  List<List<double>> wallsAt(double time) {
    var current = walls;
    for (final event in events) {
      if (event.t > time) break;
      if (event.type == 'wall_moved' && event.walls != null) {
        current = event.walls!;
      }
    }
    return current;
  }

  /// A plain-language account of the run, for the summary line and screen readers.
  String get summary {
    final start = frames.first;
    final end = frames.last;
    final travelled = _distance(start.x, start.y, end.x, end.y);
    SimulationEvent? first(String type) {
      for (final event in events) {
        if (event.type == type) return event;
      }
      return null;
    }

    final stopped = first('stopped');
    final collided = first('collided');
    String metres(double? value) =>
        value == null ? 'nothing in range' : '${value.toStringAsFixed(2)} m';
    switch (outcome) {
      case 'collided':
        final hit = collided?.t ?? end.t;
        // A stop before the crash is part of the story: say so.
        if (stopped != null && stopped.t < hit) {
          final resumed = first('resumed');
          final again = resumed != null && resumed.t < hit
              ? 'drove again after the wall moved away, '
              : '';
          return 'The robot stopped ${metres(stopped.front)} from the wall at '
              '${stopped.t.toStringAsFixed(1)} s, ${again}then hit the wall at '
              '${hit.toStringAsFixed(1)} s.';
        }
        return 'The robot hit the wall at ${hit.toStringAsFixed(1)} s '
            'without stopping.';
      case 'never_moved':
        return 'The robot never moved: every command had linear.x = 0.0.';
      case 'stopped_and_resumed':
        return 'The robot stopped ${metres(stopped?.front)} from the wall at ${stopped?.t.toStringAsFixed(1)} s, '
            'then drove again after the wall moved away.';
      case 'stopped':
        return 'The robot stopped ${metres(stopped?.front)} from the wall at ${stopped?.t.toStringAsFixed(1)} s, '
            'but did not drive again after the wall moved away.';
      default:
        return 'The robot was still driving when the replay ended '
            '(${travelled.toStringAsFixed(2)} m travelled, ${metres(end.front)} ahead).';
    }
  }

  static SimulationReplay? fromJson(Object? json) {
    if (json is! Map) return null;
    final frames = <SimulationFrame>[
      if (json['frames'] is List)
        for (final item in json['frames'] as List)
          if (SimulationFrame.fromJson(item) case final frame?) frame,
    ];
    final walls = _walls(json['walls']);
    final outcome = json['outcome'];
    if (frames.isEmpty || walls.isEmpty || outcome is! String) return null;
    final scan = json['scan'] is Map ? json['scan'] as Map : const {};
    return SimulationReplay(
      walls: walls,
      frames: frames,
      events: [
        if (json['events'] is List)
          for (final item in json['events'] as List)
            if (SimulationEvent.fromJson(item) case final event?) event,
      ],
      outcome: outcome,
      robotRadius: _number(json['robot_radius']) ?? 0.15,
      angleMinDeg: _number(scan['angle_min_deg']) ?? -135,
      angleIncrementDeg: _number(scan['angle_increment_deg']) ?? 9,
      durationSeconds: _number(json['duration_seconds']) ?? frames.last.t,
    );
  }
}

class SimulationResultDto {
  const SimulationResultDto({
    required this.assignmentVersion,
    required this.success,
    this.error = '',
    this.output = '',
    this.replay,
  });

  final int assignmentVersion;
  final bool success;
  final String error;
  final String output;
  final SimulationReplay? replay;

  factory SimulationResultDto.fromJson(Map<String, dynamic> json) {
    final version = json['assignment_version'];
    final success = json['success'];
    if (version is! int || success is! bool) {
      throw const FormatException('Unexpected simulation response.');
    }
    return SimulationResultDto(
      assignmentVersion: version,
      success: success,
      error: json['error']?.toString() ?? '',
      output: json['output']?.toString() ?? '',
      replay: SimulationReplay.fromJson(json['simulation']),
    );
  }
}

double? _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

List<List<double>> _walls(Object? value) => [
      if (value is List)
        for (final wall in value)
          if (wall is List &&
              wall.length == 4 &&
              wall.every((item) => item is num))
            [for (final item in wall) (item as num).toDouble()],
    ];

double _distance(double x1, double y1, double x2, double y2) =>
    math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
