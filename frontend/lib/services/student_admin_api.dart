import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/services/auth_api.dart';

const _studentAdminTimeout = Duration(seconds: 20);

Future<List<Map<String, dynamic>>> fetchAccounts() async {
  final responses = await Future.wait([
    http
        .get(
          Uri.parse('$apiBaseUrl/admin/students'),
          headers: AuthApi.authorizedHeaders(),
        )
        .timeout(_studentAdminTimeout),
    http
        .get(
          Uri.parse('$apiBaseUrl/admin/instructors'),
          headers: AuthApi.authorizedHeaders(),
        )
        .timeout(_studentAdminTimeout),
  ]);
  for (final response in responses) {
    _requireSuccess(response);
  }
  final students = jsonDecode(responses[0].body) as Map<String, dynamic>;
  final instructors = jsonDecode(responses[1].body) as Map<String, dynamic>;
  final accounts = [
    ...(students['students'] as List),
    ...(instructors['instructors'] as List),
  ].map((value) => Map<String, dynamic>.from(value as Map)).toList();
  accounts.sort(
    (left, right) => (left['login_id'] as String).compareTo(
      right['login_id'] as String,
    ),
  );
  return accounts;
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

Future<Map<String, dynamic>> createAccount({
  required String loginId,
  required String role,
  String? temporaryPassword,
  String? email,
  String? participantCode,
  bool sendInvitationEmail = false,
}) async {
  final response = await http
      .post(
        Uri.parse(
            '$apiBaseUrl/admin/${role == 'instructor' ? 'instructors' : 'students'}'),
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

Future<Map<String, dynamic>> updateAccount(
  String accountId, {
  required String role,
  String? email,
  String? participantCode,
  bool? active,
}) async {
  final response = await http
      .patch(
        Uri.parse(
          '$apiBaseUrl/admin/${role == 'instructor' ? 'instructors' : 'students'}/$accountId',
        ),
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

Future<Map<String, dynamic>> resetAccountPassword(
  String accountId, {
  required String role,
  String? temporaryPassword,
  bool sendEmail = false,
}) async {
  final response = await http
      .post(
        Uri.parse(
          '$apiBaseUrl/admin/${role == 'instructor' ? 'instructors' : 'students'}/$accountId/reset-password',
        ),
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
