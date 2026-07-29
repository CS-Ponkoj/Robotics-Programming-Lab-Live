import 'learning_progress_store.dart';

final learningProgress = LearningProgressStore();

Map<int, int> get lastAttemptAccuracy => learningProgress.latestScores;

Set<int> get solutionRevealedAssignments => learningProgress.revealedSolutions;
