import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';

Future<AssignmentDto> fetchAssignment(int id) async {
  final response = await http.get(
    Uri.parse('$apiBaseUrl/assignments/$id'),
  );
  if (response.statusCode == 200) {
    return AssignmentDto.fromJson(jsonDecode(response.body));
  }
  throw Exception('Failed to load assignment $id');
}

Future<UnittestFeedbackDto> fetchUnittestFeedback(
  int id,
  String code,
) async {
  if (code.isEmpty) {
    return const UnittestFeedbackDto(
      id: -1,
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

  final response = await http.post(
    Uri.parse('$apiBaseUrl/grade/$id'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'code': code}),
  );
  if (response.statusCode == 200) {
    return UnittestFeedbackDto.fromJson(jsonDecode(response.body));
  }
  throw Exception('Failed to load feedback for $id');
}
