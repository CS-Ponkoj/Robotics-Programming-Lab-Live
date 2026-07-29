import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';

const _adminTimeout = Duration(seconds: 20);

Map<String, String> _headers(String token) => {
      'content-type': 'application/json',
      'X-Admin-Token': token,
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

String _errorMessage(http.Response response) {
  try {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['error']?.toString() ??
        'Request failed (${response.statusCode}).';
  } on Object {
    return 'Request failed (${response.statusCode}).';
  }
}
