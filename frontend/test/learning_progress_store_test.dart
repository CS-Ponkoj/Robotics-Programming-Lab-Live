import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/state/learning_progress_store.dart';
import 'package:iuse_demo/models/assignment_progress.dart';
import 'package:iuse_demo/models/server_progress_dto.dart';
import 'package:iuse_demo/state/progress_storage_base.dart';

void main() {
  test('learner progress survives a store reload', () async {
    final storage = InMemoryProgressStorage();
    final firstStore = LearningProgressStore();
    await firstStore.load(storage: storage);

    await firstStore.saveDraft(2, 4, 'total_path_length = 12');
    await firstStore.recordAttempt(2, 50);
    await firstStore.recordAttempt(2, 100);
    await firstStore.recordSubmission(2, 'submission-abc');
    await firstStore.recordSolutionReveal(2);

    final reloadedStore = LearningProgressStore();
    await reloadedStore.load(storage: storage);

    expect(reloadedStore.codeDrafts[2], 'total_path_length = 12');
    expect(reloadedStore.codeDraftVersions[2], 4);
    expect(
      reloadedStore.draftFor(2, 4),
      'total_path_length = 12',
    );
    expect(reloadedStore.draftFor(2, 5), isNull);
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

  test('persistent progress is isolated by authenticated user', () async {
    final storage = InMemoryProgressStorage();
    final firstStudent = LearningProgressStore();
    await firstStudent.loadForUser('student-a', storage: storage);
    await firstStudent.recordAttempt(5, 100);
    await firstStudent.recordAttempt(6, 100);

    final secondStudent = LearningProgressStore();
    await secondStudent.loadForUser('student-b', storage: storage);
    expect(secondStudent.attemptCounts, isEmpty);
    expect(secondStudent.bestScores, isEmpty);

    await secondStudent.recordAttempt(1, 50);

    final restoredFirstStudent = LearningProgressStore();
    await restoredFirstStudent.loadForUser('student-a', storage: storage);
    expect(restoredFirstStudent.bestScores, {5: 100, 6: 100});
    expect(restoredFirstStudent.attemptCounts, {5: 1, 6: 1});
  });

  test('demo progress is memory-only and leaves saved student data unchanged',
      () async {
    final persistentStorage = InMemoryProgressStorage();
    final store = LearningProgressStore();
    await store.load(storage: persistentStorage);
    await store.saveDraft(1, 5, 'saved student draft');
    await store.recordAttempt(1, 80);

    store.startEphemeralSession();
    expect(store.codeDrafts, isEmpty);
    expect(store.attemptCounts, isEmpty);

    await store.saveDraft(2, 4, 'temporary demo draft');
    await store.recordAttempt(2, 100);
    expect(store.codeDrafts[2], 'temporary demo draft');

    final restored = LearningProgressStore();
    await restored.load(storage: persistentStorage);
    expect(restored.codeDrafts[1], 'saved student draft');
    expect(restored.codeDraftVersions[1], 5);
    expect(restored.latestScores[1], 80);
    expect(restored.codeDrafts, isNot(contains(2)));
    expect(restored.latestScores, isNot(contains(2)));
  });

  test('legacy and older-version drafts are not reused', () async {
    final storage = InMemoryProgressStorage();
    await storage.initialize();
    await storage.setString(
      'learning.code_drafts.v1',
      '{"1":"legacy assignment code"}',
    );

    final store = LearningProgressStore();
    await store.load(storage: storage);

    expect(store.draftFor(1, 5), isNull);
    expect(
      store.assignmentState(
        1,
        assignmentVersion: 5,
        starterCode: 'current starter code',
      ),
      AssignmentProgressState.notStarted,
    );

    await store.saveDraft(1, 5, 'version 5 draft');
    expect(store.draftFor(1, 5), 'version 5 draft');
    expect(store.draftFor(1, 6), isNull);
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

  test('clearing a draft removes its code and assignment version', () async {
    final storage = InMemoryProgressStorage();
    final store = LearningProgressStore();
    await store.load(storage: storage);
    await store.saveDraft(4, 3, 'temporary answer');

    await store.clearDraft(4);

    final reloaded = LearningProgressStore();
    await reloaded.load(storage: storage);
    expect(reloaded.draftFor(4, 3), isNull);
    expect(reloaded.codeDrafts, isNot(contains(4)));
    expect(reloaded.codeDraftVersions, isNot(contains(4)));
  });

  test('assignment progress resolves every learner state distinctly', () async {
    final storage = InMemoryProgressStorage();
    final store = LearningProgressStore();
    await store.load(storage: storage);

    expect(
      store.assignmentState(
        1,
        assignmentVersion: 3,
        starterCode: 'answer = 0',
      ),
      AssignmentProgressState.notStarted,
    );

    await store.saveDraft(1, 3, 'answer = 14');
    expect(
      store.assignmentState(
        1,
        assignmentVersion: 3,
        starterCode: 'answer = 0',
      ),
      AssignmentProgressState.inProgress,
    );

    await store.recordAttempt(1, 60);
    expect(
      store.assignmentState(
        1,
        assignmentVersion: 3,
        starterCode: 'answer = 0',
      ),
      AssignmentProgressState.attempted,
    );

    await store.recordAttempt(1, 100);
    expect(
      store.assignmentState(
        1,
        assignmentVersion: 3,
        starterCode: 'answer = 0',
      ),
      AssignmentProgressState.completed,
    );
  });

  test('an unsynced draft is remembered until the server confirms it',
      () async {
    final storage = InMemoryProgressStorage();
    final store = LearningProgressStore();
    await store.load(storage: storage);

    await store.saveDraft(3, 2, 'offline edit');
    await store.setDraftSynced(3, false);

    final reloaded = LearningProgressStore();
    await reloaded.load(storage: storage);
    expect(reloaded.hasUnsyncedDraft(3), isTrue);
    expect(reloaded.draftFor(3, 2), 'offline edit');

    await reloaded.setDraftSynced(3, true);
    final synced = LearningProgressStore();
    await synced.load(storage: storage);
    expect(synced.hasUnsyncedDraft(3), isFalse);

    await synced.setDraftSynced(3, false);
    await synced.clearDraft(3);
    final cleared = LearningProgressStore();
    await cleared.load(storage: storage);
    expect(cleared.hasUnsyncedDraft(3), isFalse);
  });

  test('server progress fills a new browser for a signed-in student', () async {
    final storage = InMemoryProgressStorage();
    final store = LearningProgressStore();
    await store.loadForUser('user-1', storage: storage);

    await store.syncFromServer(() async => [
          ServerAssignmentProgress.fromJson({
            'assignment_id': 1,
            'attempt_count': 3,
            'best_score': 100,
            'latest_score': 75,
            'latest_submission_id': 'submission-current',
            'solution_revealed': true,
          })!,
        ]);

    expect(store.attemptCounts[1], 3);
    expect(store.bestScores[1], 100);
    expect(store.latestScores[1], 75);
    expect(store.submissionIds[1], 'submission-current');
    expect(store.revealedSolutions, contains(1));
    expect(store.assignmentState(1), AssignmentProgressState.completed);

    // The merged history is saved for this browser and user.
    final reloaded = LearningProgressStore();
    await reloaded.loadForUser('user-1', storage: storage);
    expect(reloaded.attemptCounts[1], 3);
    expect(reloaded.bestScores[1], 100);
  });

  test('server progress never hides newer work from this browser', () async {
    final store = LearningProgressStore();
    await store.loadForUser('user-2', storage: InMemoryProgressStorage());
    await store.recordAttempt(4, 60);
    await store.recordAttempt(4, 80);
    await store.recordAttempt(4, 40);
    await store.recordSubmission(4, 'submission-local');

    await store.mergeServerProgress([
      ServerAssignmentProgress.fromJson({
        'assignment_id': 4,
        'attempt_count': 2,
        'best_score': 90,
        'latest_score': 90,
        'latest_submission_id': 'submission-older',
      })!,
    ]);

    expect(store.attemptCounts[4], 3);
    expect(store.latestScores[4], 40);
    expect(store.bestScores[4], 90);
    expect(store.submissionIds[4], 'submission-local');
  });

  test('an unreachable server leaves local progress unchanged', () async {
    final store = LearningProgressStore();
    await store.loadForUser('user-3', storage: InMemoryProgressStorage());
    await store.recordAttempt(2, 50);

    await store.syncFromServer(() async => throw Exception('offline'));
    await store.syncFromServer(
      () => Future.delayed(const Duration(seconds: 1), () => const []),
      limit: const Duration(milliseconds: 10),
    );

    expect(store.attemptCounts[2], 1);
    expect(store.bestScores[2], 50);
  });

  test('server progress parsing ignores malformed items', () {
    expect(ServerAssignmentProgress.fromJson('bad'), isNull);
    expect(ServerAssignmentProgress.fromJson({'assignment_id': '1'}), isNull);
    final parsed = ServerAssignmentProgress.fromJson({
      'assignment_id': 5,
      'latest_submission_id': '',
    })!;
    expect(parsed.attemptCount, 0);
    expect(parsed.latestSubmissionId, isNull);
    expect(parsed.solutionRevealed, isFalse);
  });
}
