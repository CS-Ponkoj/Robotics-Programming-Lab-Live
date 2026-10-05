import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/models/code_draft_dto.dart';
import 'package:iuse_demo/models/playground_result_dto.dart';
import 'package:iuse_demo/models/server_progress_dto.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/services/research_api.dart';

/// A request the server answered with an explanation for the student.
class ApiRequestException implements Exception {
  const ApiRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Playground inputs the server rejected, with messages for specific inputs
/// keyed by parameter position.
class PlaygroundInputException extends ApiRequestException {
  const PlaygroundInputException(super.message, {this.fieldErrors = const {}});

  final Map<int, String> fieldErrors;
}

const _requestTimeout = Duration(seconds: 15);
const _executionTimeout = Duration(seconds: 90);

Future<AssignmentDto> fetchAssignment(int id) async {
  final response = await http
      .get(
        Uri.parse('$apiBaseUrl/assignments/$id'),
        headers: AuthApi.authorizedHeaders(),
      )
      .timeout(_requestTimeout);
  if (response.statusCode == 200) {
    return AssignmentDto.fromJson(jsonDecode(response.body));
  }
  throw Exception('Failed to load assignment $id');
}

/// The signed-in student's progress for every attempted assignment.
Future<List<ServerAssignmentProgress>> fetchMyAssignmentProgress({
  Duration timeout = _requestTimeout,
}) async {
  final response = await http
      .get(
        Uri.parse('$apiBaseUrl/me/assignment-progress'),
        headers: AuthApi.authorizedHeaders(),
      )
      .timeout(timeout);
  if (response.statusCode != 200) {
    throw Exception(AuthApi.errorMessage(response));
  }
  final body = jsonDecode(response.body);
  final items = body is Map ? body['assignments'] : null;
  if (items is! List) {
    return const [];
  }
  return items
      .map(ServerAssignmentProgress.fromJson)
      .whereType<ServerAssignmentProgress>()
      .toList();
}

Future<CodeDraftDto> fetchCodeDraft(int assignmentId) async {
  final response = await http
      .get(
        Uri.parse('$apiBaseUrl/assignments/$assignmentId/draft'),
        headers: AuthApi.authorizedHeaders(),
      )
      .timeout(_requestTimeout);
  if (response.statusCode != 200) {
    throw Exception(AuthApi.errorMessage(response));
  }
  return CodeDraftDto.fromJson(
    Map<String, dynamic>.from(jsonDecode(response.body) as Map),
  );
}

Future<CodeDraftDto> saveCodeDraft(
  int assignmentId,
  int assignmentVersion,
  String code,
) async {
  final response = await http
      .put(
        Uri.parse('$apiBaseUrl/assignments/$assignmentId/draft'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({
          'assignment_version': assignmentVersion,
          'code': code,
        }),
      )
      .timeout(_requestTimeout);
  if (response.statusCode != 200) {
    throw Exception(AuthApi.errorMessage(response));
  }
  return CodeDraftDto.fromJson(
    Map<String, dynamic>.from(jsonDecode(response.body) as Map),
  );
}

Future<void> deleteCodeDraft(
  int assignmentId,
  int assignmentVersion,
) async {
  final response = await http
      .delete(
        Uri.parse(
          '$apiBaseUrl/assignments/$assignmentId/draft'
          '?assignment_version=$assignmentVersion',
        ),
        headers: AuthApi.authorizedHeaders(),
      )
      .timeout(_requestTimeout);
  if (response.statusCode != 204) {
    throw Exception(AuthApi.errorMessage(response));
  }
}

Future<CodeFormatDto> formatAssignmentCode(
  int assignmentId,
  String code,
) async {
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/assignments/$assignmentId/format'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({'code': code}),
      )
      .timeout(_requestTimeout);
  if (response.statusCode != 200) {
    throw Exception(AuthApi.errorMessage(response));
  }
  return CodeFormatDto.fromJson(
    Map<String, dynamic>.from(jsonDecode(response.body) as Map),
  );
}

Future<UnittestFeedbackDto> fetchUnittestFeedback(int id, String code,
    {bool useAiTutor = false}) async {
  if (code.isEmpty) {
    return const UnittestFeedbackDto(
      id: -1,
      submissionId: '',
      assignmentVersion: 1,
      score: 0,
      pass: false,
      execSuccess: false,
      codeOutput: '',
      codeExecResult: '',
      testedVals: [],
      unittestFeedback: [],
      unittestPassResults: [],
      hint: '',
    );
  }

  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/assignments/$id/submit'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({
          'code': code,
          'use_ai_tutor': useAiTutor,
          if (researchTracker.studySessionId != null)
            'study_session_id': researchTracker.studySessionId,
        }),
      )
      .timeout(_executionTimeout);
  if (response.statusCode == 200) {
    return UnittestFeedbackDto.fromJson(jsonDecode(response.body));
  }
  if (response.statusCode >= 500) {
    throw Exception('Failed to load feedback for $id');
  }
  throw ApiRequestException(AuthApi.errorMessage(response));
}

/// Call the student's function with their own inputs. Practice only: the
/// server never grades or saves these calls.
Future<PlaygroundResultDto> tryAssignmentInputs(
  int assignmentId,
  String code,
  String arguments,
) async {
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/assignments/$assignmentId/playground'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({'code': code, 'arguments': arguments}),
      )
      .timeout(_executionTimeout);
  if (response.statusCode == 200) {
    return PlaygroundResultDto.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }
  if (response.statusCode >= 500) {
    throw const ApiRequestException(
      'The code runner is unavailable right now. Please try again shortly.',
    );
  }
  if (response.statusCode == 400) {
    final fieldErrors = <int, String>{};
    try {
      final body = jsonDecode(response.body);
      final details = body is Map ? body['details'] : null;
      if (details is List) {
        for (final item in details.whereType<Map>()) {
          final index = item['parameter_index'];
          final message = item['message'];
          if (index is int && message is String) {
            fieldErrors.putIfAbsent(index, () => message);
          }
        }
      }
    } on FormatException {
      // Fall back to the general message below.
    }
    throw PlaygroundInputException(
      AuthApi.errorMessage(response),
      fieldErrors: fieldErrors,
    );
  }
  throw ApiRequestException(AuthApi.errorMessage(response));
}

Future<String> fetchWorkedSolution(
  int assignmentId,
  String submissionId,
) async {
  if (submissionId.isEmpty) {
    throw Exception('Run the assignment before revealing its solution.');
  }
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/assignments/$assignmentId/solution'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({'submission_id': submissionId}),
      )
      .timeout(_requestTimeout);
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['solution_html'] as String? ?? '';
  }
  throw Exception('The worked solution could not be unlocked.');
}

Future<Map<String, dynamic>> fetchProgressiveHint(
    int assignmentId, String submissionId, int hintLevel,
    {bool useAiTutor = false}) async {
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/assignments/$assignmentId/hint'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({
          'submission_id': submissionId,
          'hint_level': hintLevel,
          'use_ai_tutor': useAiTutor,
        }),
      )
      .timeout(_requestTimeout);
  if (response.statusCode == 200) {
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }
  throw Exception('Could not load the next hint.');
}

Future<Map<String, dynamic>> askTutorQuestion(
  int assignmentId,
  String submissionId,
  String question,
  int hintLevel,
) async {
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/assignments/$assignmentId/tutor'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({
          'submission_id': submissionId,
          'question': question,
          'hint_level': hintLevel,
        }),
      )
      .timeout(_requestTimeout);
  if (response.statusCode == 200) {
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }
  if (response.statusCode == 429) {
    throw Exception(
        'Tutor request limit reached. Wait a moment and try again.');
  }
  throw Exception('The tutor could not answer this question.');
}
