class CodeDraftDto {
  const CodeDraftDto({
    required this.assignmentId,
    required this.assignmentVersion,
    this.code,
    this.saved = false,
  });

  final int assignmentId;
  final int assignmentVersion;
  final String? code;
  final bool saved;

  factory CodeDraftDto.fromJson(Map<String, dynamic> json) {
    return CodeDraftDto(
      assignmentId: json['assignment_id'] as int,
      assignmentVersion: json['assignment_version'] as int,
      code: json['code'] as String?,
      saved: json['saved'] == true,
    );
  }
}

class CodeFormatDto {
  const CodeFormatDto({required this.code, required this.changed});

  final String code;
  final bool changed;

  factory CodeFormatDto.fromJson(Map<String, dynamic> json) {
    return CodeFormatDto(
      code: json['code'] as String,
      changed: json['changed'] == true,
    );
  }
}
