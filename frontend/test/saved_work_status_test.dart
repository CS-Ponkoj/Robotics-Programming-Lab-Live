import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/models/assignment_dto.dart';
import 'package:iuse_demo/models/assignment_progress.dart';

void main() {
  group('saved work status', () {
    test('saved work on the server shows as in progress on a new computer', () {
      expect(
        resolveAssignmentProgress(attemptCount: 0, bestScore: 0),
        AssignmentProgressState.notStarted,
      );
      expect(
        resolveAssignmentProgress(
          attemptCount: 0,
          bestScore: 0,
          hasServerDraft: true,
        ),
        AssignmentProgressState.inProgress,
      );
    });

    test('attempts and completion still take priority over saved work', () {
      expect(
        resolveAssignmentProgress(
          attemptCount: 2,
          bestScore: 50,
          hasServerDraft: true,
        ),
        AssignmentProgressState.attempted,
      );
      expect(
        resolveAssignmentProgress(
          attemptCount: 3,
          bestScore: 100,
          hasServerDraft: true,
        ),
        AssignmentProgressState.completed,
      );
    });

    test('an untouched starter copy on this device is not saved work', () {
      expect(
        resolveAssignmentProgress(
          attemptCount: 0,
          bestScore: 0,
          savedDraft: 'starter',
          starterCode: 'starter',
        ),
        AssignmentProgressState.notStarted,
      );
    });

    test('the assignment list reports saved work from the server', () {
      final base = {
        'id': 1,
        'title': 'A1',
        'description': '',
        'assignment_html': '',
        'starter_code': '',
        'vals': {},
      };
      expect(AssignmentDto.fromJson({...base, 'has_saved_draft': true}).hasSavedDraft,
          isTrue);
      expect(AssignmentDto.fromJson(base).hasSavedDraft, isFalse);
    });
  });
}
