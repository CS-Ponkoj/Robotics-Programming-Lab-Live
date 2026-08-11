class AssignmentProjectFile {
  final String path;
  final String content;
  final bool editable;

  const AssignmentProjectFile({
    required this.path,
    this.content = '',
    this.editable = false,
  });

  factory AssignmentProjectFile.fromJson(Map<String, dynamic> json) {
    return AssignmentProjectFile(
      path: json['path'] is String ? json['path'] as String : '',
      content: json['content'] is String ? json['content'] as String : '',
      editable: json['editable'] == true,
    );
  }
}

class AssignmentDto {
  final int id;
  final String stableId;
  final int version;
  final String title;
  final String description;
  final String htmlDesc;
  final String solutionHtml;
  final bool hasSolution;
  final String code;
  final String language;
  final List<String> learningObjectives;
  final List<dynamic> publicTests;
  final List<dynamic> rubric;
  final Map<String, dynamic> simulationConfig;
  final List<AssignmentProjectFile> projectFiles;
  final String? editableFilePath;
  final Map<dynamic, dynamic> vals;

  const AssignmentDto({
    required this.id,
    this.stableId = '',
    this.version = 1,
    required this.title,
    required this.description,
    required this.htmlDesc,
    this.solutionHtml = '',
    this.hasSolution = false,
    required this.code,
    this.language = 'python',
    this.learningObjectives = const [],
    this.publicTests = const [],
    this.rubric = const [],
    this.simulationConfig = const {},
    this.projectFiles = const [],
    this.editableFilePath,
    required this.vals,
  });

  factory AssignmentDto.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'id': int id,
        'title': String title,
        'description': String description,
        'assignment_html': String htmlDesc,
        'starter_code': String code,
        'vals': Map<dynamic, dynamic> vals,
      } =>
        AssignmentDto(
          id: id,
          stableId: json['stable_id'] is String
              ? json['stable_id'] as String
              : 'assignment-$id',
          version: json['version'] is int ? json['version'] as int : 1,
          title: title,
          description: description,
          htmlDesc: htmlDesc,
          solutionHtml: json['solution_html'] is String
              ? json['solution_html'] as String
              : '',
          hasSolution:
              json['has_solution'] == true ||
              (json['solution_html'] is String &&
                  (json['solution_html'] as String).isNotEmpty),
          code: code,
          language: json['language'] is String
              ? json['language'] as String
              : 'python',
          learningObjectives: json['learning_objectives'] is List
              ? (json['learning_objectives'] as List)
                    .map((value) => value.toString())
                    .toList()
              : const [],
          publicTests: json['public_tests'] is List
              ? json['public_tests'] as List
              : const [],
          rubric: json['rubric'] is List ? json['rubric'] as List : const [],
          simulationConfig: json['simulation_config'] is Map
              ? Map<String, dynamic>.from(json['simulation_config'] as Map)
              : const {},
          projectFiles: json['project_files'] is List
              ? (json['project_files'] as List)
                    .whereType<Map>()
                    .map(
                      (value) => AssignmentProjectFile.fromJson(
                        Map<String, dynamic>.from(value),
                      ),
                    )
                    .where((value) => value.path.isNotEmpty)
                    .toList()
              : const [],
          editableFilePath: json['editable_file_path'] is String
              ? json['editable_file_path'] as String
              : null,
          vals: vals,
        ),
      _ => throw const FormatException('Failed to load assignment.'),
    };
  }
}
