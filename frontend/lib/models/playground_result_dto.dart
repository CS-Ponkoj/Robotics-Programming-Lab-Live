/// One labelled value returned by the student's function.
class PlaygroundValueDto {
  const PlaygroundValueDto({required this.label, this.value, this.display = ''});

  final String label;
  final Object? value;

  /// Python's spelling of [value]; web numbers would print 0.0 as 0.
  final String display;

  String get text => display.isNotEmpty ? display : formatPlaygroundValue(value);

  factory PlaygroundValueDto.fromJson(Map<String, dynamic> json) {
    return PlaygroundValueDto(
      label: json['label']?.toString() ?? 'Value',
      value: json['value'],
      display: json['display']?.toString() ?? '',
    );
  }
}

/// Ungraded result of calling the student's function with their own inputs.
class PlaygroundResultDto {
  const PlaygroundResultDto({
    required this.success,
    required this.call,
    this.executionStatus = '',
    this.returned = '',
    this.returnCount,
    this.expectedReturnCount = 0,
    this.values = const [],
    this.output = '',
    this.error = '',
  });

  final bool success;
  final String call;
  final String executionStatus;
  final String returned;
  final int? returnCount;
  final int expectedReturnCount;
  final List<PlaygroundValueDto> values;
  final String output;
  final String error;

  /// True when the function returned a sequence of the wrong length.
  bool get hasWrongReturnCount =>
      success && returnCount != null && returnCount != expectedReturnCount;

  /// True when the function returned one value instead of a sequence.
  bool get returnedSingleValue =>
      success && returnCount == null && expectedReturnCount > 1;

  factory PlaygroundResultDto.fromJson(Map<String, dynamic> json) {
    return PlaygroundResultDto(
      success: json['success'] == true,
      call: json['call']?.toString() ?? '',
      executionStatus: json['execution_status']?.toString() ?? '',
      returned: json['returned']?.toString() ?? '',
      returnCount: json['return_count'] is int ? json['return_count'] as int : null,
      expectedReturnCount: json['expected_return_count'] is int
          ? json['expected_return_count'] as int
          : 0,
      values: json['values'] is List
          ? (json['values'] as List)
              .whereType<Map>()
              .map(
                (item) => PlaygroundValueDto.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
          : const [],
      output: json['output']?.toString() ?? '',
      error: json['error']?.toString() ?? '',
    );
  }
}

/// Show a returned JSON value the way Python would print it.
String formatPlaygroundValue(Object? value) {
  if (value == null) return 'None';
  if (value is bool) return value ? 'True' : 'False';
  if (value is String) return "'$value'";
  if (value is Map && value['repr'] != null) return value['repr'].toString();
  return value.toString();
}
