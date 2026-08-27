import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/services/research_download.dart';
import 'package:iuse_demo/services/research_visibility.dart';

const _researchTimeout = Duration(seconds: 20);
const _heartbeatInterval = Duration(seconds: 30);
const _researchIdleWindow = Duration(minutes: 15);

Future<Map<String, dynamic>> fetchMyResearchData() async {
  final responses = await Future.wait([
    http
        .get(
          Uri.parse('$apiBaseUrl/research/me'),
          headers: AuthApi.authorizedHeaders(),
        )
        .timeout(_researchTimeout),
    http
        .get(
          Uri.parse('$apiBaseUrl/research/metrics'),
          headers: AuthApi.authorizedHeaders(),
        )
        .timeout(_researchTimeout),
  ]);
  _requireResearchSuccess(responses[0]);
  _requireResearchSuccess(responses[1]);
  final data = Map<String, dynamic>.from(
    jsonDecode(responses[0].body) as Map,
  );
  data['metric_catalog'] = Map<String, dynamic>.from(
    jsonDecode(responses[1].body) as Map,
  );
  return data;
}

Future<List<Map<String, dynamic>>> fetchResearchParticipants() async {
  final data = await fetchInstructorResearchData();
  return (data['participants'] as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
}

Future<Map<String, dynamic>> fetchInstructorResearchData() async {
  final responses = await Future.wait([
    http
        .get(
          Uri.parse('$apiBaseUrl/admin/research/summary'),
          headers: AuthApi.authorizedHeaders(),
        )
        .timeout(_researchTimeout),
    http
        .get(
          Uri.parse('$apiBaseUrl/research/metrics'),
          headers: AuthApi.authorizedHeaders(),
        )
        .timeout(_researchTimeout),
  ]);
  _requireResearchSuccess(responses[0]);
  _requireResearchSuccess(responses[1]);
  final data = Map<String, dynamic>.from(
    jsonDecode(responses[0].body) as Map,
  );
  data['metric_catalog'] = Map<String, dynamic>.from(
    jsonDecode(responses[1].body) as Map,
  );
  return data;
}

Future<Map<String, dynamic>> fetchMetricCatalog() async {
  final response = await http
      .get(
        Uri.parse('$apiBaseUrl/research/metrics'),
        headers: AuthApi.authorizedHeaders(),
      )
      .timeout(_researchTimeout);
  _requireResearchSuccess(response);
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

Future<Map<String, dynamic>> fetchMyAttemptHistory({
  int page = 1,
  int pageSize = 50,
  int? assignmentId,
  int? assignmentVersion,
}) async {
  final uri = Uri.parse('$apiBaseUrl/research/me/attempts').replace(
    queryParameters: {
      'page': '$page',
      'page_size': '$pageSize',
      if (assignmentId != null) 'assignment_id': '$assignmentId',
      if (assignmentVersion != null) 'assignment_version': '$assignmentVersion',
    },
  );
  final response = await http
      .get(uri, headers: AuthApi.authorizedHeaders())
      .timeout(_researchTimeout);
  _requireResearchSuccess(response);
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

Future<Map<String, dynamic>> fetchStudentAttemptHistory(
  String studentId, {
  int page = 1,
  int pageSize = 50,
}) async {
  final uri = Uri.parse(
    '$apiBaseUrl/admin/research/students/$studentId/attempts',
  ).replace(
    queryParameters: {'page': '$page', 'page_size': '$pageSize'},
  );
  final response = await http
      .get(uri, headers: AuthApi.authorizedHeaders())
      .timeout(_researchTimeout);
  _requireResearchSuccess(response);
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

Future<Map<String, dynamic>> fetchStudentResearchData(String studentId) async {
  final response = await http
      .get(
        Uri.parse('$apiBaseUrl/admin/research/students/$studentId'),
        headers: AuthApi.authorizedHeaders(),
      )
      .timeout(_researchTimeout);
  _requireResearchSuccess(response);
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

Future<bool> downloadResearchDataset({
  String datasetName = 'student_summary',
  String format = 'csv',
}) async {
  final uri = Uri.parse('$apiBaseUrl/admin/research/export').replace(
    queryParameters: {'dataset_name': datasetName, 'format': format},
  );
  final response = await http
      .get(uri, headers: AuthApi.authorizedHeaders())
      .timeout(_researchTimeout);
  _requireResearchSuccess(response);
  final filename =
      format == 'xlsx' ? 'robotics_study_dataset.xlsx' : '$datasetName.csv';
  final mimeType = format == 'xlsx'
      ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      : 'text/csv';
  return saveResearchDownload(response.bodyBytes, filename, mimeType);
}

class ResearchTracker {
  ResearchTracker({
    this.heartbeatInterval = _heartbeatInterval,
    this.idleWindow = _researchIdleWindow,
    bool Function()? pageVisible,
    DateTime Function()? clock,
  })  : _pageVisible = pageVisible ?? isResearchPageVisible,
        _clock = clock ?? DateTime.now {
    _lastInteractionAt = _clock();
  }

  final Duration heartbeatInterval;
  final Duration idleWindow;
  final bool Function() _pageVisible;
  final DateTime Function() _clock;
  String? _studySessionId;
  Future<void>? _starting;
  Timer? _heartbeatTimer;
  int? _assignmentId;
  int? _assignmentVersion;
  late DateTime _lastInteractionAt;

  String? get studySessionId => _studySessionId;

  void recordUserInteraction() {
    _lastInteractionAt = _clock();
  }

  bool isRecentlyActive([DateTime? now]) {
    return (now ?? _clock()).difference(_lastInteractionAt) <= idleWindow;
  }

  Future<void> start() async {
    if (_studySessionId != null) {
      return;
    }
    if (_starting != null) {
      return _starting;
    }
    final operation = _startNewSession();
    _starting = operation;
    try {
      await operation;
    } finally {
      _starting = null;
    }
  }

  Future<void> _startNewSession() async {
    final clientId = 'browser-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final response = await http
        .post(
          Uri.parse('$apiBaseUrl/research/sessions'),
          headers: AuthApi.authorizedHeaders(json: true),
          body: jsonEncode({'client_session_id': clientId}),
        )
        .timeout(_researchTimeout);
    _requireResearchSuccess(response, expected: const {201});
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _studySessionId = data['id'] as String;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      heartbeatInterval,
      (_) => unawaited(_heartbeat()),
    );
  }

  Future<void> startSafely() async {
    try {
      await start();
    } on Object {
      // Research capture must never block the learning application.
    }
  }

  void setActiveAssignment(int assignmentId, int assignmentVersion) {
    _assignmentId = assignmentId;
    _assignmentVersion = assignmentVersion;
  }

  void clearActiveAssignment(int assignmentId) {
    if (_assignmentId == assignmentId) {
      _assignmentId = null;
      _assignmentVersion = null;
    }
  }

  Future<void> trackEvent(
    String eventType, {
    int? assignmentId,
    int? assignmentVersion,
    Map<String, dynamic> eventData = const {},
  }) async {
    try {
      await start();
      final sessionId = _studySessionId;
      if (sessionId == null) {
        return;
      }
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/research/sessions/$sessionId/events'),
            headers: AuthApi.authorizedHeaders(json: true),
            body: jsonEncode({
              'event_type': eventType,
              if (assignmentId != null) 'assignment_id': assignmentId,
              if (assignmentVersion != null)
                'assignment_version': assignmentVersion,
              'event_data': eventData,
              'client_occurred_at': DateTime.now().toUtc().toIso8601String(),
            }),
          )
          .timeout(_researchTimeout);
      _requireResearchSuccess(response, expected: const {201});
    } on Object {
      // Telemetry failure is deliberately non-fatal for students.
    }
  }

  Future<void> _heartbeat() async {
    if (!_pageVisible() || !isRecentlyActive()) {
      return;
    }
    final sessionId = _studySessionId;
    if (sessionId == null) {
      return;
    }
    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/research/sessions/$sessionId/heartbeat'),
            headers: AuthApi.authorizedHeaders(json: true),
            body: jsonEncode({
              'active_seconds': heartbeatInterval.inSeconds.clamp(1, 60),
              if (_assignmentId != null) 'assignment_id': _assignmentId,
              if (_assignmentVersion != null)
                'assignment_version': _assignmentVersion,
            }),
          )
          .timeout(_researchTimeout);
      _requireResearchSuccess(response);
    } on Object {
      // A later heartbeat can recover without affecting the assignment.
    }
  }

  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final sessionId = _studySessionId;
    _studySessionId = null;
    _assignmentId = null;
    _assignmentVersion = null;
    if (sessionId == null) {
      return;
    }
    try {
      await http
          .post(
            Uri.parse('$apiBaseUrl/research/sessions/$sessionId/end'),
            headers: AuthApi.authorizedHeaders(),
          )
          .timeout(_researchTimeout);
    } on Object {
      // Logout must succeed even when the study endpoint is unavailable.
    }
  }
}

final researchTracker = ResearchTracker();

void _requireResearchSuccess(
  http.Response response, {
  Set<int> expected = const {200},
}) {
  if (!expected.contains(response.statusCode)) {
    throw Exception(AuthApi.errorMessage(response));
  }
}
