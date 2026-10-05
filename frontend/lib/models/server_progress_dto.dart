/// One assignment's progress as recorded on the server for the signed-in
/// student, so history follows the student across browsers and devices.
class ServerAssignmentProgress {
  const ServerAssignmentProgress({
    required this.assignmentId,
    required this.attemptCount,
    required this.bestScore,
    required this.latestScore,
    this.latestSubmissionId,
    this.solutionRevealed = false,
  });

  final int assignmentId;
  final int attemptCount;
  final int bestScore;
  final int latestScore;

  /// Present only when the newest submission belongs to the current
  /// assignment version, because hints and reveals are version-scoped.
  final String? latestSubmissionId;
  final bool solutionRevealed;

  static ServerAssignmentProgress? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['assignment_id'];
    if (id is! int) {
      return null;
    }
    int count(Object? value) => value is num ? value.round() : 0;
    final submissionId = json['latest_submission_id'];
    return ServerAssignmentProgress(
      assignmentId: id,
      attemptCount: count(json['attempt_count']),
      bestScore: count(json['best_score']),
      latestScore: count(json['latest_score']),
      latestSubmissionId:
          submissionId is String && submissionId.isNotEmpty ? submissionId : null,
      solutionRevealed: json['solution_revealed'] == true,
    );
  }
}
