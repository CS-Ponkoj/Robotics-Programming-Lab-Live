import 'dart:convert';

import '../models/assignment_progress.dart';
import 'progress_storage.dart';
import 'progress_storage_base.dart';

class LearningProgressStore {
  static const _latestScoresKey = 'learning.latest_scores.v1';
  static const _bestScoresKey = 'learning.best_scores.v1';
  static const _draftsKey = 'learning.code_drafts.v1';
  static const _draftVersionsKey = 'learning.code_draft_versions.v1';
  static const _attemptCountsKey = 'learning.attempt_counts.v1';
  static const _revealedSolutionsKey = 'learning.revealed_solutions.v1';
  static const _submissionIdsKey = 'learning.submission_ids.v1';

  final Map<int, int> latestScores = {};
  final Map<int, int> bestScores = {};
  final Map<int, String> codeDrafts = {};
  final Map<int, int> codeDraftVersions = {};
  final Map<int, int> attemptCounts = {};
  final Set<int> revealedSolutions = {};
  final Map<int, String> submissionIds = {};

  ProgressStorage? _storage;
  String? _userScope;

  bool get isLoaded => _storage != null;

  void startEphemeralSession() {
    _storage = InMemoryProgressStorage();
    _userScope = null;
    _clearState();
  }

  bool hasAttempted(int assignmentId) => (attemptCounts[assignmentId] ?? 0) > 0;

  AssignmentProgressState assignmentState(
    int assignmentId, {
    int? assignmentVersion,
    String starterCode = '',
  }) {
    return resolveAssignmentProgress(
      attemptCount: attemptCounts[assignmentId] ?? 0,
      bestScore: bestScores[assignmentId] ?? 0,
      savedDraft: assignmentVersion == null
          ? null
          : draftFor(assignmentId, assignmentVersion),
      starterCode: starterCode,
    );
  }

  String? draftFor(int assignmentId, int assignmentVersion) {
    if (codeDraftVersions[assignmentId] != assignmentVersion) {
      return null;
    }
    return codeDrafts[assignmentId];
  }

  Future<void> load({ProgressStorage? storage}) async {
    _storage = storage ?? createProgressStorage();
    await _storage!.initialize();
    _userScope = null;

    _readState();
  }

  Future<void> loadForUser(
    String userId, {
    ProgressStorage? storage,
    bool migrateLegacy = false,
  }) async {
    _storage = storage ?? createProgressStorage();
    await _storage!.initialize();
    _userScope = userId;

    if (migrateLegacy && _getStringSafely(_latestScoresKey) == null) {
      await _copyLegacyProgress();
    }
    _readState();
  }

  void _readState() {
    _clearState();
    latestScores.addAll(_decodeIntMap(_getStringSafely(_latestScoresKey)));
    bestScores.addAll(_decodeIntMap(_getStringSafely(_bestScoresKey)));
    codeDrafts.addAll(_decodeStringMap(_getStringSafely(_draftsKey)));
    codeDraftVersions.addAll(
      _decodeIntMap(_getStringSafely(_draftVersionsKey)),
    );
    attemptCounts.addAll(_decodeIntMap(_getStringSafely(_attemptCountsKey)));
    revealedSolutions.addAll(
      _decodeIntList(_getStringSafely(_revealedSolutionsKey))
          .map(int.tryParse)
          .whereType<int>(),
    );
    submissionIds.addAll(
      _decodeStringMap(_getStringSafely(_submissionIdsKey)),
    );
  }

  Future<void> _copyLegacyProgress() async {
    for (final key in [
      _latestScoresKey,
      _bestScoresKey,
      _draftsKey,
      _draftVersionsKey,
      _attemptCountsKey,
      _revealedSolutionsKey,
      _submissionIdsKey,
    ]) {
      final legacyValue = _storage?.getString(key);
      if (legacyValue != null) {
        await _storage?.setString(_scopedKey(key), legacyValue);
      }
    }
  }

  void _clearState() {
    latestScores.clear();
    bestScores.clear();
    codeDrafts.clear();
    codeDraftVersions.clear();
    attemptCounts.clear();
    revealedSolutions.clear();
    submissionIds.clear();
  }

  Future<void> saveDraft(
    int assignmentId,
    int assignmentVersion,
    String code,
  ) async {
    codeDrafts[assignmentId] = code;
    codeDraftVersions[assignmentId] = assignmentVersion;
    await Future.wait([
      if (_storage != null)
        _storage!.setString(_scopedKey(_draftsKey), _encodeMap(codeDrafts)),
      if (_storage != null)
        _storage!.setString(
          _scopedKey(_draftVersionsKey),
          _encodeMap(codeDraftVersions),
        ),
    ]);
  }

  Future<void> clearDraft(int assignmentId) async {
    codeDrafts.remove(assignmentId);
    codeDraftVersions.remove(assignmentId);
    await Future.wait([
      if (_storage != null)
        _storage!.setString(_scopedKey(_draftsKey), _encodeMap(codeDrafts)),
      if (_storage != null)
        _storage!.setString(
          _scopedKey(_draftVersionsKey),
          _encodeMap(codeDraftVersions),
        ),
    ]);
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
        _storage!.setString(
          _scopedKey(_latestScoresKey),
          _encodeMap(latestScores),
        ),
      if (_storage != null)
        _storage!.setString(
          _scopedKey(_bestScoresKey),
          _encodeMap(bestScores),
        ),
      if (_storage != null)
        _storage!.setString(
          _scopedKey(_attemptCountsKey),
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
      _scopedKey(_submissionIdsKey),
      _encodeMap(submissionIds),
    );
  }

  Future<void> recordSolutionReveal(int assignmentId) async {
    revealedSolutions.add(assignmentId);
    await _storage?.setString(
      _scopedKey(_revealedSolutionsKey),
      jsonEncode(revealedSolutions.toList()..sort()),
    );
  }

  Future<void> clearSolutionReveal(int assignmentId) async {
    revealedSolutions.remove(assignmentId);
    await _storage?.setString(
      _scopedKey(_revealedSolutionsKey),
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
      return _storage?.getString(_scopedKey(key));
    } on Object {
      return null;
    }
  }

  String _scopedKey(String key) {
    final scope = _userScope;
    return scope == null ? key : 'learning.user.$scope.$key';
  }
}
