import 'dart:convert';

import '../models/assignment_progress.dart';
import '../models/server_progress_dto.dart';
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
  static const _unsyncedDraftsKey = 'learning.unsynced_drafts.v1';

  final Map<int, int> latestScores = {};
  final Map<int, int> bestScores = {};
  final Map<int, String> codeDrafts = {};
  final Map<int, int> codeDraftVersions = {};
  final Map<int, int> attemptCounts = {};
  final Set<int> revealedSolutions = {};
  final Map<int, String> submissionIds = {};
  final Set<int> unsyncedDrafts = {};

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
    bool hasServerDraft = false,
  }) {
    return resolveAssignmentProgress(
      attemptCount: attemptCounts[assignmentId] ?? 0,
      bestScore: bestScores[assignmentId] ?? 0,
      savedDraft: assignmentVersion == null
          ? null
          : draftFor(assignmentId, assignmentVersion),
      starterCode: starterCode,
      hasServerDraft: hasServerDraft,
    );
  }

  /// True when this device holds draft code the server has not confirmed.
  bool hasUnsyncedDraft(int assignmentId) =>
      unsyncedDrafts.contains(assignmentId);

  Future<void> setDraftSynced(int assignmentId, bool synced) async {
    final changed = synced
        ? unsyncedDrafts.remove(assignmentId)
        : unsyncedDrafts.add(assignmentId);
    if (changed) {
      await _storeUnsyncedDrafts();
    }
  }

  Future<void> _storeUnsyncedDrafts() async {
    await _storage?.setString(
      _scopedKey(_unsyncedDraftsKey),
      jsonEncode(unsyncedDrafts.toList()..sort()),
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
    unsyncedDrafts.addAll(
      _decodeIntList(_getStringSafely(_unsyncedDraftsKey))
          .map(int.tryParse)
          .whereType<int>(),
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
    unsyncedDrafts.clear();
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
    if (unsyncedDrafts.remove(assignmentId)) {
      await _storeUnsyncedDrafts();
    }
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

  /// Load the server's record for a signed-in student and merge it. A slow
  /// or unreachable server leaves this browser's progress unchanged.
  Future<void> syncFromServer(
    Future<List<ServerAssignmentProgress>> Function() fetch, {
    Duration limit = const Duration(seconds: 6),
  }) async {
    try {
      await mergeServerProgress(await fetch().timeout(limit));
    } on Object {
      // Progress still shows from this browser; the next sign-in retries.
    }
  }

  /// Combine the server's record with this browser's copy. Each value keeps
  /// the larger history, so work done here but not yet seen by the server
  /// (or done elsewhere) is never hidden.
  Future<void> mergeServerProgress(
    Iterable<ServerAssignmentProgress> serverProgress,
  ) async {
    var changed = false;
    for (final item in serverProgress) {
      final id = item.assignmentId;
      final localAttempts = attemptCounts[id] ?? 0;
      if (item.attemptCount > localAttempts) {
        attemptCounts[id] = item.attemptCount;
        latestScores[id] = item.latestScore;
        changed = true;
      }
      if (item.bestScore > (bestScores[id] ?? -1)) {
        bestScores[id] = item.bestScore;
        changed = true;
      }
      final submissionId = item.latestSubmissionId;
      if (submissionId != null && submissionIds[id] != submissionId &&
          item.attemptCount >= localAttempts) {
        submissionIds[id] = submissionId;
        changed = true;
      }
      if (item.solutionRevealed && revealedSolutions.add(id)) {
        changed = true;
      }
    }
    if (!changed || _storage == null) {
      return;
    }
    await Future.wait([
      _storage!.setString(_scopedKey(_latestScoresKey), _encodeMap(latestScores)),
      _storage!.setString(_scopedKey(_bestScoresKey), _encodeMap(bestScores)),
      _storage!.setString(_scopedKey(_attemptCountsKey), _encodeMap(attemptCounts)),
      _storage!.setString(_scopedKey(_submissionIdsKey), _encodeMap(submissionIds)),
      _storage!.setString(
        _scopedKey(_revealedSolutionsKey),
        jsonEncode(revealedSolutions.toList()..sort()),
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
