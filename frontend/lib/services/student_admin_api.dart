import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/services/auth_api.dart';

const _studentAdminTimeout = Duration(seconds: 20);

Future<List<Map<String, dynamic>>> fetchStudents() async {
  final response = await http
      .get(
        Uri.parse('$apiBaseUrl/admin/students'),
        headers: AuthApi.authorizedHeaders(),
      )
      .timeout(_studentAdminTimeout);
  _requireSuccess(response);
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  return (data['students'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList();
}

Future<Map<String, dynamic>> fetchEmailStatus() async {
  final response = await http
      .get(
        Uri.parse('$apiBaseUrl/admin/email/status'),
        headers: AuthApi.authorizedHeaders(),
      )
      .timeout(_studentAdminTimeout);
  _requireSuccess(response);
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

Future<void> sendTestEmail(String recipient) async {
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/admin/email/test'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({'recipient': recipient}),
      )
      .timeout(_studentAdminTimeout);
  _requireSuccess(response);
}

Future<Map<String, dynamic>> createStudent({
  required String loginId,
  String? temporaryPassword,
  String? email,
  String? participantCode,
  bool sendInvitationEmail = false,
}) async {
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/admin/students'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({
          'login_id': loginId,
          if (temporaryPassword != null && temporaryPassword.isNotEmpty)
            'temporary_password': temporaryPassword,
          'email': _nullIfEmpty(email),
          'participant_code': _nullIfEmpty(participantCode),
          'active': true,
          'send_invitation_email': sendInvitationEmail,
        }),
      )
      .timeout(_studentAdminTimeout);
  _requireSuccess(response, expected: {201});
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

Future<Map<String, dynamic>> updateStudent(
  String studentId, {
  String? email,
  String? participantCode,
  bool? active,
}) async {
  final response = await http
      .patch(
        Uri.parse('$apiBaseUrl/admin/students/$studentId'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({
          if (email != null) 'email': _nullIfEmpty(email),
          if (participantCode != null)
            'participant_code': _nullIfEmpty(participantCode),
          if (active != null) 'active': active,
        }),
      )
      .timeout(_studentAdminTimeout);
  _requireSuccess(response);
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

Future<Map<String, dynamic>> resetStudentPassword(
  String studentId, {
  String? temporaryPassword,
  bool sendEmail = false,
}) async {
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/admin/students/$studentId/reset-password'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({
          if (temporaryPassword != null && temporaryPassword.isNotEmpty)
            'temporary_password': temporaryPassword,
          'send_email': sendEmail,
        }),
      )
      .timeout(_studentAdminTimeout);
  _requireSuccess(response);
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

Future<Map<String, dynamic>> importStudyAccounts() async {
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/admin/accounts/import'),
        headers: AuthApi.authorizedHeaders(),
      )
      .timeout(_studentAdminTimeout);
  _requireSuccess(response);
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

String? _nullIfEmpty(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

void _requireSuccess(
  http.Response response, {
  Set<int> expected = const {200},
}) {
  if (!expected.contains(response.statusCode)) {
    throw Exception(AuthApi.errorMessage(response));
  }
}
