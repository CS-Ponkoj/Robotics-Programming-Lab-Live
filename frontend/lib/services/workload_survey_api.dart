import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/services/assignment_api.dart';
import 'package:iuse_demo/services/auth_api.dart';

const _surveyTimeout = Duration(seconds: 15);

/// One NASA-TLX scale as the server defines it.
class WorkloadItem {
  const WorkloadItem({
    required this.key,
    required this.title,
    required this.question,
    required this.definition,
    required this.low,
    required this.high,
  });

  final String key;
  final String title;
  final String question;
  final String definition;
  final String low;
  final String high;

  static WorkloadItem? fromJson(Object? json) {
    if (json is! Map) return null;
    String text(String name) => json[name]?.toString() ?? '';
    if (text('key').isEmpty || text('title').isEmpty) return null;
    return WorkloadItem(
      key: text('key'),
      title: text('title'),
      question: text('question'),
      definition: text('definition'),
      low: text('low'),
      high: text('high'),
    );
  }
}

class WorkloadForm {
  const WorkloadForm({
    required this.formVersion,
    required this.instructions,
    required this.items,
    this.step = 5,
  });

  final String formVersion;
  final String instructions;
  final List<WorkloadItem> items;
  final int step;

  static WorkloadForm? fromJson(Object? json) {
    if (json is! Map || json['items'] is! List) return null;
    final items = (json['items'] as List)
        .map(WorkloadItem.fromJson)
        .whereType<WorkloadItem>()
        .toList();
    if (items.isEmpty) return null;
    return WorkloadForm(
      formVersion: json['form_version']?.toString() ?? '',
      instructions: json['instructions']?.toString() ?? '',
      items: items,
      step: json['step'] is int ? json['step'] as int : 5,
    );
  }
}

/// Whether this student is asked the workload survey for an assignment.
class WorkloadSurveyStatus {
  const WorkloadSurveyStatus({
    required this.offered,
    required this.completed,
    required this.hasAttempt,
    this.form,
  });

  final bool offered;
  final bool completed;
  final bool hasAttempt;
  final WorkloadForm? form;

  /// The survey can be answered now.
  bool get open => offered && !completed && form != null;

  WorkloadSurveyStatus copyWith({bool? completed, bool? hasAttempt}) =>
      WorkloadSurveyStatus(
        offered: offered,
        completed: completed ?? this.completed,
        hasAttempt: hasAttempt ?? this.hasAttempt,
        form: form,
      );

  static WorkloadSurveyStatus fromJson(Map<String, dynamic> json) =>
      WorkloadSurveyStatus(
        offered: json['offered'] == true,
        completed: json['completed'] == true,
        hasAttempt: json['has_attempt'] == true,
        form: WorkloadForm.fromJson(json['form']),
      );
}

/// The survey status, or null when this assignment has none or the server
/// cannot be reached (the survey never blocks the assignment).
Future<WorkloadSurveyStatus?> fetchWorkloadSurveyStatus(
    int assignmentId) async {
  try {
    final response = await http
        .get(
          Uri.parse('$apiBaseUrl/assignments/$assignmentId/workload-survey'),
          headers: AuthApi.authorizedHeaders(),
        )
        .timeout(_surveyTimeout);
    if (response.statusCode != 200) return null;
    return WorkloadSurveyStatus.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  } on Object {
    return null;
  }
}

/// Saves a response; unrated scales are sent as null.
Future<void> submitWorkloadSurvey(
  int assignmentId, {
  required Map<String, int?> ratings,
  required String trigger,
  required DateTime openedAt,
}) async {
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/assignments/$assignmentId/workload-survey'),
        headers: AuthApi.authorizedHeaders(json: true),
        body: jsonEncode({
          'ratings': ratings,
          'trigger': trigger,
          'opened_at': openedAt.toUtc().toIso8601String(),
        }),
      )
      .timeout(_surveyTimeout);
  if (response.statusCode == 201) return;
  if (response.statusCode == 409) {
    String message = 'Your answers were already saved.';
    try {
      final detail = (jsonDecode(response.body) as Map)['detail'];
      if (detail is String && detail.isNotEmpty) message = detail;
    } on Object {
      // Keep the general message.
    }
    throw ApiRequestException(message);
  }
  throw const ApiRequestException(
      'Your answers could not be saved. Check your connection and try again.');
}
