import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:iuse_demo/api_config.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _authTimeout = Duration(seconds: 75);
const _tokenStorageKey = 'auth_session_token';

class AuthSession {
  const AuthSession({
    required this.token,
    required this.user,
  });

  final String token;
  final AuthenticatedUser user;
}

class AuthApi {
  static String? _token;

  static String? get token => _token;

  static Map<String, String> authorizedHeaders({bool json = false}) {
    return {
      if (json) 'content-type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
  }

  static Future<AuthSession> login(String loginId, String password) async {
    final response = await http
        .post(
          Uri.parse('$apiBaseUrl/auth/login'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'login_id': loginId, 'password': password}),
        )
        .timeout(_authTimeout);
    if (response.statusCode != 200) {
      throw Exception(errorMessage(response));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final session = AuthSession(
      token: data['token'] as String,
      user: AuthenticatedUser.fromJson(
        Map<String, dynamic>.from(data['user'] as Map),
      ),
    );
    _token = session.token;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_tokenStorageKey, session.token);
    return session;
  }

  static Future<AuthenticatedUser?> restore() async {
    final preferences = await SharedPreferences.getInstance();
    final storedToken = preferences.getString(_tokenStorageKey);
    if (storedToken == null || storedToken.isEmpty) {
      return null;
    }

    _token = storedToken;
    try {
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/auth/me'),
            headers: authorizedHeaders(),
          )
          .timeout(_authTimeout);
      if (response.statusCode == 200) {
        return AuthenticatedUser.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map),
        );
      }
    } on Object {
      // A stale or unreachable session is cleared so the user can sign in.
    }
    await clearLocalSession();
    return null;
  }

  static Future<void> logout() async {
    try {
      if (_token != null) {
        await http
            .post(
              Uri.parse('$apiBaseUrl/auth/logout'),
              headers: authorizedHeaders(),
            )
            .timeout(_authTimeout);
      }
    } on Object {
      // Local logout must still succeed if the backend is unavailable.
    } finally {
      await clearLocalSession();
    }
  }

  static Future<void> clearLocalSession() async {
    _token = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenStorageKey);
  }

  static Future<String> forgotPassword(String identifier) async {
    final response = await http
        .post(
          Uri.parse('$apiBaseUrl/auth/forgot-password'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'identifier': identifier}),
        )
        .timeout(_authTimeout);
    if (response.statusCode != 202) {
      throw Exception(errorMessage(response));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['message'] as String;
  }

  static Future<void> resetPassword(
    String resetToken,
    String newPassword,
  ) async {
    final response = await http
        .post(
          Uri.parse('$apiBaseUrl/auth/reset-password'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'token': resetToken,
            'new_password': newPassword,
          }),
        )
        .timeout(_authTimeout);
    if (response.statusCode != 200) {
      throw Exception(errorMessage(response));
    }
    await clearLocalSession();
  }

  static String errorMessage(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['detail']?.toString() ??
          data['error']?.toString() ??
          'Request failed (${response.statusCode}).';
    } on Object {
      return 'Request failed (${response.statusCode}).';
    }
  }
}
