import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/state/learning_progress_store.dart';
import 'package:iuse_demo/models/assignment_progress.dart';
import 'package:iuse_demo/state/progress_storage_base.dart';

void main() {
  test('learner progress survives a store reload', () async {
    final storage = InMemoryProgressStorage();
    final firstStore = LearningProgressStore();
    await firstStore.load(storage: storage);

    await firstStore.saveDraft(2, 'total_path_length = 12');
    await firstStore.recordAttempt(2, 50);
    await firstStore.recordAttempt(2, 100);
    await firstStore.recordSubmission(2, 'submission-abc');
    await firstStore.recordSolutionReveal(2);

    final reloadedStore = LearningProgressStore();
    await reloadedStore.load(storage: storage);

    expect(reloadedStore.codeDrafts[2], 'total_path_length = 12');
    expect(reloadedStore.latestScores[2], 100);
    expect(reloadedStore.bestScores[2], 100);
    expect(reloadedStore.attemptCounts[2], 2);
    expect(reloadedStore.hasAttempted(2), isTrue);
    expect(reloadedStore.submissionIds[2], 'submission-abc');
    expect(reloadedStore.revealedSolutions, contains(2));
  });

  test('a lower latest score does not replace the best score', () async {
    final store = LearningProgressStore();
    await store.load(storage: InMemoryProgressStorage());

    await store.recordAttempt(1, 100);
    await store.recordAttempt(1, 25);

    expect(store.latestScores[1], 25);
    expect(store.bestScores[1], 100);
  });

  test('demo progress is memory-only and leaves saved student data unchanged',
      () async {
    final persistentStorage = InMemoryProgressStorage();
    final store = LearningProgressStore();
    await store.load(storage: persistentStorage);
    await store.saveDraft(1, 'saved student draft');
    await store.recordAttempt(1, 80);

    store.startEphemeralSession();
    expect(store.codeDrafts, isEmpty);
    expect(store.attemptCounts, isEmpty);

    await store.saveDraft(2, 'temporary demo draft');
    await store.recordAttempt(2, 100);
    expect(store.codeDrafts[2], 'temporary demo draft');

    final restored = LearningProgressStore();
    await restored.load(storage: persistentStorage);
    expect(restored.codeDrafts[1], 'saved student draft');
    expect(restored.latestScores[1], 80);
    expect(restored.codeDrafts, isNot(contains(2)));
    expect(restored.latestScores, isNot(contains(2)));
  });

  test('an invalidated solution reveal is removed from persistence', () async {
    final storage = InMemoryProgressStorage();
    final store = LearningProgressStore();
    await store.load(storage: storage);

    await store.recordSolutionReveal(3);
    await store.clearSolutionReveal(3);

    final reloadedStore = LearningProgressStore();
    await reloadedStore.load(storage: storage);
    expect(reloadedStore.revealedSolutions, isNot(contains(3)));
  });

  test('assignment progress resolves every learner state distinctly', () async {
    final storage = InMemoryProgressStorage();
    final store = LearningProgressStore();
    await store.load(storage: storage);

    expect(
      store.assignmentState(1, starterCode: 'answer = 0'),
      AssignmentProgressState.notStarted,
    );

    await store.saveDraft(1, 'answer = 14');
    expect(
      store.assignmentState(1, starterCode: 'answer = 0'),
      AssignmentProgressState.inProgress,
    );

    await store.recordAttempt(1, 60);
    expect(
      store.assignmentState(1, starterCode: 'answer = 0'),
      AssignmentProgressState.attempted,
    );

    await store.recordAttempt(1, 100);
    expect(
      store.assignmentState(1, starterCode: 'answer = 0'),
      AssignmentProgressState.completed,
    );
  });
}
