import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/services/auth_api.dart';

const _adminTimeout = Duration(seconds: 20);

Map<String, String> _headers(String token) => {
      'content-type': 'application/json',
      'Authorization': 'Bearer $token',
    };

Future<List<Map<String, dynamic>>> fetchAdminAssignments(String token) async {
  final response = await http
      .get(
        Uri.parse('$apiBaseUrl/admin/assignments'),
        headers: _headers(token),
      )
      .timeout(_adminTimeout);
  if (response.statusCode != 200) {
    throw Exception(_errorMessage(response));
  }
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  return (data['assignments'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList();
}

Future<Map<String, dynamic>> saveAdminAssignment(
  String token,
  Map<String, dynamic> assignment,
) async {
  final id = assignment['id'];
  final uri = id is int
      ? Uri.parse('$apiBaseUrl/admin/assignments/$id')
      : Uri.parse('$apiBaseUrl/admin/assignments');
  final response = id is int
      ? await http
          .put(
            uri,
            headers: _headers(token),
            body: jsonEncode(assignment),
          )
          .timeout(_adminTimeout)
      : await http
          .post(
            uri,
            headers: _headers(token),
            body: jsonEncode(assignment),
          )
          .timeout(_adminTimeout);
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception(_errorMessage(response));
  }
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

Future<Map<String, dynamic>> validateAdminAssignment(
  String token,
  int assignmentId,
) async {
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/admin/assignments/$assignmentId/validate'),
        headers: _headers(token),
      )
      .timeout(_adminTimeout);
  if (response.statusCode != 200) {
    throw Exception(_errorMessage(response));
  }
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

Future<void> publishAdminAssignment(
  String token,
  int assignmentId,
) async {
  final response = await http
      .post(
        Uri.parse('$apiBaseUrl/admin/assignments/$assignmentId/publish'),
        headers: _headers(token),
      )
      .timeout(_adminTimeout);
  if (response.statusCode != 200) {
    throw Exception(_errorMessage(response));
  }
}

/// The shared auth helper also flags an expired sign-in, so the app shows
/// its "Please sign in again" dialog instead of a raw error on the page.
String _errorMessage(http.Response response) => AuthApi.errorMessage(response);

/// The course AI tutor switch, daily limit, whether a key is configured on the
/// server (never the key), and each assignment's AI review state.
Future<Map<String, dynamic>> fetchAiTutorSettings(String token) async {
  final response = await http
      .get(
        Uri.parse('$apiBaseUrl/admin/course-settings/ai-tutor'),
        headers: _headers(token),
      )
      .timeout(_adminTimeout);
  if (response.statusCode != 200) {
    throw Exception(_errorMessage(response));
  }
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

Future<Map<String, dynamic>> saveAiTutorSettings(
  String token, {
  required bool enabled,
  required int dailyLimit,
}) async {
  final response = await http
      .put(
        Uri.parse('$apiBaseUrl/admin/course-settings/ai-tutor'),
        headers: _headers(token),
        body: jsonEncode({'enabled': enabled, 'daily_limit': dailyLimit}),
      )
      .timeout(_adminTimeout);
  if (response.statusCode != 200) {
    throw Exception(_errorMessage(response));
  }
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

/// Stable IDs grouped under Old assignments, and whether they come from the
/// repository file or an instructor's choice.
Future<Map<String, dynamic>> fetchCatalogSettings(String token) async {
  final response = await http
      .get(
        Uri.parse('$apiBaseUrl/admin/course-settings/catalog'),
        headers: _headers(token),
      )
      .timeout(_adminTimeout);
  if (response.statusCode != 200) {
    throw Exception(_errorMessage(response));
  }
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

/// Saves the Old assignments list; null returns to the repository file.
Future<Map<String, dynamic>> saveCatalogSettings(
  String token,
  List<String>? oldStableIds,
) async {
  final response = await http
      .put(
        Uri.parse('$apiBaseUrl/admin/course-settings/catalog'),
        headers: _headers(token),
        body: jsonEncode({'old_stable_ids': oldStableIds}),
      )
      .timeout(_adminTimeout);
  if (response.statusCode != 200) {
    throw Exception(_errorMessage(response));
  }
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}

/// Aggregate teaching insights for one assignment version (no student IDs).
Future<Map<String, dynamic>> fetchAssignmentInsights(
  String token,
  int assignmentId,
) async {
  final response = await http
      .get(
        Uri.parse('$apiBaseUrl/admin/assignments/$assignmentId/insights'),
        headers: _headers(token),
      )
      .timeout(_adminTimeout);
  if (response.statusCode != 200) {
    throw Exception(_errorMessage(response));
  }
  return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
}
