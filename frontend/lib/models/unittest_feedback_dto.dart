class UnittestFeedbackDto {
  final int id;
  final List<dynamic> testedVals;
  final bool pass;
  final List<dynamic> unittestFeedback;
  final List<bool> unittestPassResults;
  final String codeExecResult;
  final String codeOutput;
  final bool execSuccess;
  final String hint;

  const UnittestFeedbackDto(
      {required this.id,
      required this.testedVals,
      required this.pass,
      required this.unittestFeedback,
      required this.unittestPassResults,
      required this.codeExecResult,
      required this.codeOutput,
      required this.execSuccess,
      required this.hint});

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
          pass: pass,
          testedVals: testedVals,
          unittestFeedback: unittestFeedback,
          unittestPassResults: unittestPassResults.cast<bool>(),
          codeExecResult: codeExecResult,
          codeOutput: codeOutput,
          execSuccess: execSuccess,
          hint: hint ?? "",
        ),
      _ => throw const FormatException('Failed to load assignment.'),
    };
  }
}
