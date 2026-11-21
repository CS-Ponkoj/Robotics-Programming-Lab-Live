import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/services/auth_api.dart';

const _contentTimeout = Duration(seconds: 15);

class ContentSessionExpired implements Exception {
  const ContentSessionExpired();
}

/// The server already has this student's single pre-test attempt.
class PretestAlreadyTaken implements Exception {
  const PretestAlreadyTaken();
}

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
      if (response.statusCode == 401) throw const ContentSessionExpired();
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

  /// The worked answer of an exercise or math page, loaded only when asked.
  static Future<String> workedAnswer(String topicId, String sectionId) async {
    final result = await _get('/contents/${Uri.encodeComponent(topicId)}'
        '/sections/${Uri.encodeComponent(sectionId)}/answer');
    return result['html'] as String;
  }

  /// Whether the student has taken the topic's pre-test, and the score.
  static Future<Map<String, dynamic>> pretestStatus(String topicId) =>
      _get('/contents/${Uri.encodeComponent(topicId)}/pretest');

  /// Submits the one-attempt pre-test; the server returns only the score.
  static Future<Map<String, dynamic>> submitPretest(
      String topicId, String version, Map<String, String> choices) async {
    final uri = Uri.parse(
        '$apiBaseUrl/contents/${Uri.encodeComponent(topicId)}/pretest/submit');
    final headers = AuthApi.authorizedHeaders(json: true);
    final body = jsonEncode({'quiz_version': version, 'choices': choices});
    final response =
        await (testClient?.post(uri, headers: headers, body: body) ??
                http.post(uri, headers: headers, body: body))
            .timeout(_contentTimeout);
    if (response.statusCode == 409) {
      throw const PretestAlreadyTaken();
    }
    if (response.statusCode != 200) {
      throw Exception('Could not submit the pre-test. Please try again.');
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

/// Per-question flags from a graded quiz submit, keyed by question ID.
/// An older server without `results` yields an empty map.
Map<String, bool> quizResultMarks(Map<String, dynamic> result) {
  final results = result['results'];
  if (results is! List) return const {};
  return {
    for (final item in results)
      if (item is Map &&
          item['question_id'] is String &&
          item['correct'] is bool)
        item['question_id'] as String: item['correct'] as bool,
  };
}

/// The correct option and, when the topic gives one, the explanation of
/// each question, which the server sends only after a complete submit.
Map<String, ({String option, String? explanation})> quizResultReview(
    Map<String, dynamic> result) {
  final results = result['results'];
  if (results is! List) return const {};
  return {
    for (final item in results)
      if (item is Map &&
          item['question_id'] is String &&
          item['correct_option'] is String)
        item['question_id'] as String: (
          option: item['correct_option'] as String,
          explanation: item['explanation'] is String
              ? item['explanation'] as String
              : null,
        ),
  };
}
