class UnittestFeedbackDto {
  final int id;
  final String submissionId;
  final int assignmentVersion;
  final int score;
  final List<dynamic> testedVals;
  final bool pass;
  final List<dynamic> unittestFeedback;
  final List<bool> unittestPassResults;
  final String codeExecResult;
  final String codeOutput;
  final bool execSuccess;
  final String hint;
  final String tutorSource;
  final String executionStatus;
  final Map<String, dynamic> tutorFeedback;

  const UnittestFeedbackDto(
      {required this.id,
      this.submissionId = '',
      this.assignmentVersion = 1,
      this.score = 0,
      required this.testedVals,
      required this.pass,
      required this.unittestFeedback,
      required this.unittestPassResults,
      required this.codeExecResult,
      required this.codeOutput,
      required this.execSuccess,
      required this.hint,
      this.tutorSource = '',
      this.executionStatus = '',
      this.tutorFeedback = const {}});

  factory UnittestFeedbackDto.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'id': int id,
        'tested_vals': List<dynamic> testedVals,
        'pass': bool pass,
        'ex_success': bool execSuccess,
        'unittest_results': List<dynamic> unittestFeedback,
        'unittest_pass_results': List<dynamic> unittestPassResults,
        'code_exec_result': String codeExecResult,
        'code_output': String codeOutput,
        'hint': String? hint
      } =>
        UnittestFeedbackDto(
          id: id,
          submissionId: json['submission_id'] is String
              ? json['submission_id'] as String
              : '',
          assignmentVersion: json['assignment_version'] is int
              ? json['assignment_version'] as int
              : 1,
          score: json['score'] is int ? json['score'] as int : 0,
          pass: pass,
          testedVals: testedVals,
          unittestFeedback: unittestFeedback,
          unittestPassResults: unittestPassResults.cast<bool>(),
          codeExecResult: codeExecResult,
          codeOutput: codeOutput,
          execSuccess: execSuccess,
          hint: hint ?? "",
          tutorSource: json['tutor_feedback'] is Map
              ? ((json['tutor_feedback'] as Map)['source']?.toString() ?? '')
              : '',
          executionStatus: json['execution_status']?.toString() ?? '',
          tutorFeedback: json['tutor_feedback'] is Map
              ? Map<String, dynamic>.from(json['tutor_feedback'] as Map)
              : const {},
        ),
      _ => throw const FormatException('Failed to load assignment.'),
    };
  }
}
