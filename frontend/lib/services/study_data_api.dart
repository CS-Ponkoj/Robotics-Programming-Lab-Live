import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/services/research_download.dart';

const _studyDataTimeout = Duration(seconds: 30);

/// Filters shared by the on-screen table and its CSV download.
class StudyDataFilters {
  const StudyDataFilters({
    this.studentId,
    this.assignmentId,
    this.feedbackMode,
    this.dateFrom,
    this.dateTo,
    this.includeTestAccounts = false,
  });

  final String? studentId;
  final int? assignmentId;
  final String? feedbackMode;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final bool includeTestAccounts;

  static String _day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Map<String, String> toQuery() => {
        if (studentId != null) 'student_id': studentId!,
        if (assignmentId != null) 'assignment_id': '$assignmentId',
        if (feedbackMode != null) 'feedback_mode': feedbackMode!,
        if (dateFrom != null) 'date_from': _day(dateFrom!),
        if (dateTo != null) 'date_to': _day(dateTo!),
        if (includeTestAccounts) 'include_test_accounts': 'true',
      };
}

Map<String, dynamic> _decode(http.Response response) {
  if (response.statusCode != 200) {
    throw Exception(AuthApi.errorMessage(response));
  }
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

/// The table list plus the students and assignments for the filters.
Future<Map<String, dynamic>> fetchStudyDataCatalog({
  bool includeTestAccounts = false,
}) async {
  final uri = Uri.parse('$apiBaseUrl/admin/study-data').replace(
    queryParameters: {
      if (includeTestAccounts) 'include_test_accounts': 'true',
    },
  );
  final response = await http
      .get(uri, headers: AuthApi.authorizedHeaders())
      .timeout(_studyDataTimeout);
  return _decode(response);
}

/// One page of a table: columns, rows, and the total row count.
Future<Map<String, dynamic>> fetchStudyDataTable(
  String table, {
  required StudyDataFilters filters,
  int page = 1,
  int pageSize = 50,
  String? sort,
  bool descending = true,
}) async {
  final uri = Uri.parse('$apiBaseUrl/admin/study-data/$table').replace(
    queryParameters: {
      ...filters.toQuery(),
      'page': '$page',
      'page_size': '$pageSize',
      if (sort != null) 'sort': sort,
      'order': descending ? 'desc' : 'asc',
    },
  );
  final response = await http
      .get(uri, headers: AuthApi.authorizedHeaders())
      .timeout(_studyDataTimeout);
  return _decode(response);
}

/// Downloads the whole filtered table as CSV; false where the browser
/// download is unavailable.
Future<bool> downloadStudyDataCsv(
  String table, {
  required StudyDataFilters filters,
  String? sort,
  bool descending = true,
}) async {
  final uri = Uri.parse('$apiBaseUrl/admin/study-data/$table').replace(
    queryParameters: {
      ...filters.toQuery(),
      'format': 'csv',
      if (sort != null) 'sort': sort,
      'order': descending ? 'desc' : 'asc',
    },
  );
  final response = await http
      .get(uri, headers: AuthApi.authorizedHeaders())
      .timeout(const Duration(seconds: 60));
  if (response.statusCode != 200) {
    throw Exception(AuthApi.errorMessage(response));
  }
  return saveResearchDownload(response.bodyBytes, '$table.csv', 'text/csv');
}

/// One attempt's code, shown in the app only.
Future<Map<String, dynamic>> fetchAttemptCode(String attemptId) async {
  final response = await http
      .get(
        Uri.parse('$apiBaseUrl/admin/study-data/attempts/$attemptId/code'),
        headers: AuthApi.authorizedHeaders(),
      )
      .timeout(_studyDataTimeout);
  return _decode(response);
}

/// One participant's study sessions, each with its timeline of activity.
Future<Map<String, dynamic>> fetchParticipantSessions(String studentId) async {
  final response = await http
      .get(
        Uri.parse(
            '$apiBaseUrl/admin/study-data/participants/$studentId/sessions'),
        headers: AuthApi.authorizedHeaders(),
      )
      .timeout(_studyDataTimeout);
  return _decode(response);
}

/// Downloads one participant's session timelines as CSV.
Future<bool> downloadParticipantSessionsCsv(
  String studentId,
  String fileLabel,
) async {
  final uri = Uri.parse(
          '$apiBaseUrl/admin/study-data/participants/$studentId/sessions')
      .replace(queryParameters: {'format': 'csv'});
  final response = await http
      .get(uri, headers: AuthApi.authorizedHeaders())
      .timeout(const Duration(seconds: 60));
  if (response.statusCode != 200) {
    throw Exception(AuthApi.errorMessage(response));
  }
  final safe = fileLabel.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return saveResearchDownload(
      response.bodyBytes, 'sessions_$safe.csv', 'text/csv');
}
