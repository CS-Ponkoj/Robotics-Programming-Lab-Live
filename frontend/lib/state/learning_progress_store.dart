import 'dart:convert';

import '../models/assignment_progress.dart';
import 'progress_storage.dart';
import 'progress_storage_base.dart';

class LearningProgressStore {
  static const _latestScoresKey = 'learning.latest_scores.v1';
  static const _bestScoresKey = 'learning.best_scores.v1';
  static const _draftsKey = 'learning.code_drafts.v1';
  static const _attemptCountsKey = 'learning.attempt_counts.v1';
  static const _revealedSolutionsKey = 'learning.revealed_solutions.v1';
  static const _submissionIdsKey = 'learning.submission_ids.v1';

  final Map<int, int> latestScores = {};
  final Map<int, int> bestScores = {};
  final Map<int, String> codeDrafts = {};
  final Map<int, int> attemptCounts = {};
  final Set<int> revealedSolutions = {};
  final Map<int, String> submissionIds = {};

  ProgressStorage? _storage;

  bool get isLoaded => _storage != null;

  bool hasAttempted(int assignmentId) => (attemptCounts[assignmentId] ?? 0) > 0;

  AssignmentProgressState assignmentState(
    int assignmentId, {
    String starterCode = '',
  }) {
    return resolveAssignmentProgress(
      attemptCount: attemptCounts[assignmentId] ?? 0,
      bestScore: bestScores[assignmentId] ?? 0,
      savedDraft: codeDrafts[assignmentId],
      starterCode: starterCode,
    );
  }

  Future<void> load({ProgressStorage? storage}) async {
    _storage = storage ?? createProgressStorage();
    await _storage!.initialize();

    latestScores
      ..clear()
      ..addAll(_decodeIntMap(_getStringSafely(_latestScoresKey)));
    bestScores
      ..clear()
      ..addAll(_decodeIntMap(_getStringSafely(_bestScoresKey)));
    codeDrafts
      ..clear()
      ..addAll(_decodeStringMap(_getStringSafely(_draftsKey)));
    attemptCounts
      ..clear()
      ..addAll(_decodeIntMap(_getStringSafely(_attemptCountsKey)));
    revealedSolutions
      ..clear()
      ..addAll(
        _decodeIntList(_getStringSafely(_revealedSolutionsKey))
            .map(int.tryParse)
            .whereType<int>(),
      );
    submissionIds
      ..clear()
      ..addAll(_decodeStringMap(_getStringSafely(_submissionIdsKey)));
  }

  Future<void> saveDraft(int assignmentId, String code) async {
    codeDrafts[assignmentId] = code;
    await _storage?.setString(_draftsKey, _encodeMap(codeDrafts));
  }

  Future<void> recordAttempt(int assignmentId, int score) async {
    latestScores[assignmentId] = score;
    final previousBest = bestScores[assignmentId];
    if (previousBest == null || score > previousBest) {
      bestScores[assignmentId] = score;
    }
    attemptCounts[assignmentId] = (attemptCounts[assignmentId] ?? 0) + 1;

    await Future.wait([
      if (_storage != null)
        _storage!.setString(_latestScoresKey, _encodeMap(latestScores)),
      if (_storage != null)
        _storage!.setString(_bestScoresKey, _encodeMap(bestScores)),
      if (_storage != null)
        _storage!.setString(
          _attemptCountsKey,
          _encodeMap(attemptCounts),
        ),
    ]);
  }

  Future<void> recordSubmission(int assignmentId, String submissionId) async {
    if (submissionId.isEmpty) {
      return;
    }
    submissionIds[assignmentId] = submissionId;
    await _storage?.setString(
      _submissionIdsKey,
      _encodeMap(submissionIds),
    );
  }

  Future<void> recordSolutionReveal(int assignmentId) async {
    revealedSolutions.add(assignmentId);
    await _storage?.setString(
      _revealedSolutionsKey,
      jsonEncode(revealedSolutions.toList()..sort()),
    );
  }

  Future<void> clearSolutionReveal(int assignmentId) async {
    revealedSolutions.remove(assignmentId);
    await _storage?.setString(
      _revealedSolutionsKey,
      jsonEncode(revealedSolutions.toList()..sort()),
    );
  }

  static Map<int, int> _decodeIntMap(String? source) {
    if (source == null) {
      return {};
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        return {};
      }
      return decoded.map(
        (key, value) => MapEntry(int.parse(key), (value as num).round()),
      );
    } on Object {
      return {};
    }
  }

  static String _encodeMap(Map<int, Object> source) {
    return jsonEncode(
      source.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  static List<String> _decodeIntList(String? source) {
    if (source == null) {
      return [];
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List<dynamic>) {
        return [];
      }
      return decoded.map((value) => value.toString()).toList();
    } on Object {
      return [];
    }
  }

  static Map<int, String> _decodeStringMap(String? source) {
    if (source == null) {
      return {};
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        return {};
      }
      return decoded.map(
        (key, value) => MapEntry(int.parse(key), value.toString()),
      );
    } on Object {
      return {};
    }
  }

  String? _getStringSafely(String key) {
    try {
      return _storage?.getString(key);
    } on Object {
      return null;
    }
  }
}
