import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/models/code_draft_dto.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/services/research_api.dart';

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
  throw Exception('Failed to load feedback for $id');
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
  int assignmentId,
  String submissionId,
  int hintLevel,
) async {
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/assignments/$assignmentId/hint'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({
          'submission_id': submissionId,
          'hint_level': hintLevel,
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
