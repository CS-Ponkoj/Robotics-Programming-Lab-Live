class AssignmentDto {
  final int id;
  final String title;
  final String description;
  final String htmlDesc;
  final String code;
  final Map<dynamic, dynamic> vals;

  const AssignmentDto(
      {required this.id,
      required this.title,
      required this.description,
      required this.htmlDesc,
      required this.code,
      required this.vals});

  factory AssignmentDto.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'id': int id,
        'title': String title,
        'description': String description,
        'assignment_html': String htmlDesc,
        'starter_code': String code,
        'vals': Map<dynamic, dynamic> vals
      } =>
        AssignmentDto(
            id: id,
            title: title,
            description: description,
            htmlDesc: htmlDesc,
            code: code,
            vals: vals),
      _ => throw const FormatException('Failed to load assignment.'),
    };
  }
}
