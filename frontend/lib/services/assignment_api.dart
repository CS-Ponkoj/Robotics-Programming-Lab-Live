import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/services/auth_api.dart';

const _requestTimeout = Duration(seconds: 15);

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
        }),
      )
      .timeout(_requestTimeout);
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
