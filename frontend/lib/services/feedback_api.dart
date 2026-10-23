import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/services/auth_api.dart';

const _feedbackTimeout = Duration(seconds: 20);

const feedbackCategories = {
  'bug': 'Something is broken',
  'content': 'Content or instructions issue',
  'suggestion': 'Suggestion',
  'other': 'Other',
};

Future<void> submitFeedback({
  required String page,
  required String category,
  required String message,
}) async {
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/feedback'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({
          'page': page,
          'category': category,
          'message': message,
        }),
      )
      .timeout(_feedbackTimeout);
  _requireSuccess(response);
}

Future<Map<String, dynamic>> fetchFeedback({
  String? status,
  int page = 1,
  int pageSize = 50,
}) async {
  final query = {
    'page': '$page',
    'page_size': '$pageSize',
    if (status != null) 'status': status,
  };
  final response = await http
      .get(
        Uri.parse('$apiBaseUrl/admin/feedback').replace(queryParameters: query),
        headers: AuthApi.authorizedHeaders(),
      )
      .timeout(_feedbackTimeout);
  _requireSuccess(response);
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

Future<void> updateFeedbackStatus(String id, String status) async {
  final response = await http
      .patch(
        Uri.parse('$apiBaseUrl/admin/feedback/$id'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({'status': status}),
      )
      .timeout(_feedbackTimeout);
  _requireSuccess(response);
}

void _requireSuccess(http.Response response) {
  if (response.statusCode >= 200 && response.statusCode < 300) {
    return;
  }
  if (response.statusCode == 429) {
    throw Exception('Too many feedback messages. Please wait a minute.');
  }
  String message = 'Request failed (${response.statusCode}).';
  try {
    final body = jsonDecode(response.body);
    if (body is Map && body['detail'] is String) {
      message = body['detail'] as String;
    }
  } catch (_) {}
  throw Exception(message);
}
