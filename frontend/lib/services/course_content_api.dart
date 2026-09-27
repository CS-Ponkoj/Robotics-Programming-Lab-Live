import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/services/auth_api.dart';

const _contentTimeout = Duration(seconds: 15);

class CourseContentApi {
  @visibleForTesting
  static http.Client? testClient;

  static Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final response =
        await (testClient?.get(uri, headers: AuthApi.authorizedHeaders()) ??
                http.get(uri, headers: AuthApi.authorizedHeaders()))
            .timeout(_contentTimeout);
    if (response.statusCode != 200) {
      throw Exception(
          'Could not load course content (${response.statusCode}).');
    }
    return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }

  static Future<List<Map<String, dynamic>>> topics() async {
    final result = await _get('/contents');
    return (result['topics'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> topic(String id) =>
      _get('/contents/${Uri.encodeComponent(id)}');

  static Future<
      Map<String,
          dynamic>> section(String topicId, String id) => _get(
      '/contents/${Uri.encodeComponent(topicId)}/sections/${Uri.encodeComponent(id)}');

  static Future<Map<String, dynamic>> submitQuiz(
      String topicId, String version, Map<String, String> choices) async {
    final uri = Uri.parse(
        '$apiBaseUrl/contents/${Uri.encodeComponent(topicId)}/quiz/submit');
    final headers = AuthApi.authorizedHeaders(json: true);
    final body = jsonEncode({'quiz_version': version, 'choices': choices});
    final response =
        await (testClient?.post(uri, headers: headers, body: body) ??
                http.post(uri, headers: headers, body: body))
            .timeout(_contentTimeout);
    if (response.statusCode != 200) {
      throw Exception('Could not submit your quiz. Please try again.');
    }
    return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }

  static Future<List<Map<String, dynamic>>> quizAttempts(String topicId) async {
    final result =
        await _get('/contents/${Uri.encodeComponent(topicId)}/quiz/attempts');
    return (result['attempts'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }
}
