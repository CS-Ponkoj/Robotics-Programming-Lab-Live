class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.loginId,
    required this.role,
    this.email,
    this.participantCode,
    this.isDemo = false,
    this.mustChangePassword = false,
    this.feedbackMode = 'tdd',
  });

  final String id;
  final String loginId;
  final String role;
  final String? email;
  final String? participantCode;
  final bool isDemo;
  final bool mustChangePassword;

  /// Server-assigned study condition: traditional, tdd, or tdd_ai.
  final String feedbackMode;

  bool get isInstructor => role == 'instructor';

  factory AuthenticatedUser.fromJson(Map<String, dynamic> json) {
    return AuthenticatedUser(
      id: json['id'] as String,
      loginId: json['login_id'] as String,
      role: json['role'] as String,
      email: json['email'] as String?,
      participantCode: json['participant_code'] as String?,
      isDemo: json['is_demo'] as bool? ?? false,
      mustChangePassword: json['must_change_password'] as bool? ?? false,
      feedbackMode: json['feedback_mode'] as String? ?? 'tdd',
    );
  }
}
