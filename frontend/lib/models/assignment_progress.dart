enum AssignmentProgressState {
  notStarted('Not started'),
  inProgress('In progress'),
  attempted('Attempted'),
  completed('Completed');

  const AssignmentProgressState(this.label);

  final String label;
}

AssignmentProgressState resolveAssignmentProgress({
  required int attemptCount,
  required int bestScore,
  String? savedDraft,
  String starterCode = '',
  bool hasServerDraft = false,
}) {
  if (bestScore >= 100) {
    return AssignmentProgressState.completed;
  }
  if (attemptCount > 0) {
    return AssignmentProgressState.attempted;
  }
  if (savedDraft != null &&
      savedDraft.trim().isNotEmpty &&
      savedDraft != starterCode) {
    return AssignmentProgressState.inProgress;
  }
  // Saved on the server from another computer, with no copy on this one.
  if (hasServerDraft) {
    return AssignmentProgressState.inProgress;
  }
  return AssignmentProgressState.notStarted;
}
