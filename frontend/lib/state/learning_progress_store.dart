import 'dart:convert';

import '../models/assignment_progress.dart';
import '../models/server_progress_dto.dart';
import 'progress_storage.dart';
import 'progress_storage_base.dart';

/// The latest run's checks for one assignment: how many passed, of how
/// many, and the first one still failing (empty when none, or when the
/// student's feedback mode shows no check details).
class CheckSummary {
  const CheckSummary({
    required this.passed,
    required this.total,
    this.nextFailing = '',
    this.at = 0,
  });

  final int passed;
  final int total;
  final String nextFailing;

  /// When the run finished, in milliseconds since the epoch (0 = unknown).
  final int at;

  CheckSummary withTime(int at) => CheckSummary(
      passed: passed, total: total, nextFailing: nextFailing, at: at);

  Map<String, Object> toJson() =>
      {'passed': passed, 'total': total, 'next': nextFailing, 'at': at};

  static CheckSummary? fromJson(Object? json) {
    if (json is! Map) return null;
    final passed = json['passed'];
    final total = json['total'];
    if (passed is! num || total is! num || total <= 0) return null;
    return CheckSummary(
      passed: passed.round().clamp(0, total.round()),
      total: total.round(),
      nextFailing: (json['next'] ?? '').toString(),
      at: json['at'] is num ? (json['at'] as num).round() : 0,
    );
  }
}

/// How far a student got in one course topic, on this device only: the
/// lesson read so far, the next heading, and the steps they finished.
class TopicProgress {
  const TopicProgress({
    required this.title,
    this.lessonPercent = 0,
    this.nextHeading = '',
    this.doneKinds = const {},
    this.updatedAt = 0,
  });

  final String title;

  /// The furthest point read in the lesson, 0 to 100.
  final int lessonPercent;
  final String nextHeading;

  /// Section kinds finished: pretest, lesson, exercise, math, quiz.
  final Set<String> doneKinds;

  /// Milliseconds since the epoch of the last change, to find the latest.
  final int updatedAt;

  TopicProgress copyWith({
    String? title,
    int? lessonPercent,
    String? nextHeading,
    Set<String>? doneKinds,
    int? updatedAt,
  }) =>
      TopicProgress(
        title: title ?? this.title,
        lessonPercent: lessonPercent ?? this.lessonPercent,
        nextHeading: nextHeading ?? this.nextHeading,
        doneKinds: doneKinds ?? this.doneKinds,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object> toJson() => {
        'title': title,
        'lesson': lessonPercent,
        'next': nextHeading,
        'done': doneKinds.toList()..sort(),
        'at': updatedAt,
      };

  static TopicProgress? fromJson(Object? json) {
    if (json is! Map || json['title'] is! String) return null;
    final lesson = json['lesson'];
    final at = json['at'];
    final done = json['done'];
    return TopicProgress(
      title: json['title'] as String,
      lessonPercent: lesson is num ? lesson.round().clamp(0, 100) : 0,
      nextHeading: (json['next'] ?? '').toString(),
      doneKinds: done is List ? {for (final kind in done) kind.toString()} : {},
      updatedAt: at is num ? at.round() : 0,
    );
  }
}

class LearningProgressStore {
  static const _latestScoresKey = 'learning.latest_scores.v1';
  static const _bestScoresKey = 'learning.best_scores.v1';
  static const _draftsKey = 'learning.code_drafts.v1';
  static const _draftVersionsKey = 'learning.code_draft_versions.v1';
  static const _attemptCountsKey = 'learning.attempt_counts.v1';
  static const _revealedSolutionsKey = 'learning.revealed_solutions.v1';
  static const _submissionIdsKey = 'learning.submission_ids.v1';
  static const _unsyncedDraftsKey = 'learning.unsynced_drafts.v1';
  static const _earlierDraftsKey = 'learning.earlier_version_drafts.v1';
  static const _checkSummariesKey = 'learning.check_summaries.v1';
  static const _topicProgressKey = 'learning.topic_progress.v1';

  final Map<int, int> latestScores = {};
  final Map<int, int> bestScores = {};
  final Map<int, String> codeDrafts = {};
  final Map<int, int> codeDraftVersions = {};
  final Map<int, int> attemptCounts = {};
  final Set<int> revealedSolutions = {};
  final Map<int, String> submissionIds = {};
  final Set<int> unsyncedDrafts = {};
  // Code written for an older assignment version. It is never loaded into the
  // new version's editor, but the student can still view and copy it.
  final Map<int, String> earlierDrafts = {};

  /// The latest run's checks per assignment, on this device only.
  final Map<int, CheckSummary> checkSummaries = {};

  /// Reading and step progress per course topic, on this device only.
  final Map<String, TopicProgress> topicProgress = {};

  /// The topic read most recently whose lesson is not finished, if any.
  MapEntry<String, TopicProgress>? get lessonToResume {
    MapEntry<String, TopicProgress>? latest;
    for (final entry in topicProgress.entries) {
      final value = entry.value;
      if (value.lessonPercent <= 0 || value.lessonPercent >= 100) continue;
      if (latest == null || value.updatedAt > latest.value.updatedAt) {
        latest = entry;
      }
    }
    return latest;
  }

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

  /// Code this device kept from an older version of the assignment.
  String? earlierDraftFor(int assignmentId, int assignmentVersion) {
    final draftVersion = codeDraftVersions[assignmentId];
    if (draftVersion != null && draftVersion < assignmentVersion) {
      return codeDrafts[assignmentId];
    }
    return earlierDrafts[assignmentId];
  }

  Future<void> dismissEarlierDraft(
    int assignmentId,
    int assignmentVersion,
  ) async {
    final draftVersion = codeDraftVersions[assignmentId];
    if (draftVersion != null && draftVersion < assignmentVersion) {
      await clearDraft(assignmentId);
    }
    if (earlierDrafts.remove(assignmentId) != null) {
      await _storeEarlierDrafts();
    }
  }

  Future<void> _storeEarlierDrafts() async {
    await _storage?.setString(
      _scopedKey(_earlierDraftsKey),
      _encodeMap(earlierDrafts),
    );
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
    earlierDrafts.addAll(_decodeStringMap(_getStringSafely(_earlierDraftsKey)));
    checkSummaries.addAll(_decodeCheckSummaries(
      _getStringSafely(_checkSummariesKey),
    ));
    topicProgress.addAll(_decodeTopicProgress(
      _getStringSafely(_topicProgressKey),
    ));
  }

  static Map<String, TopicProgress> _decodeTopicProgress(String? source) {
    if (source == null) return {};
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) return {};
      return {
        for (final entry in decoded.entries)
          if (TopicProgress.fromJson(entry.value) case final value?)
            entry.key: value,
      };
    } on Object {
      return {};
    }
  }

  /// Records reading progress (only ever forward) and finished steps.
  Future<void> updateTopicProgress(
    String topicId, {
    required String title,
    int? lessonPercent,
    String? nextHeading,
    String? doneKind,
  }) async {
    final current = topicProgress[topicId] ?? TopicProgress(title: title);
    var percent = current.lessonPercent;
    if (lessonPercent != null && lessonPercent > percent) {
      percent = lessonPercent.clamp(0, 100);
    }
    final done = {...current.doneKinds};
    if (doneKind != null) done.add(doneKind);
    if (percent >= 100) done.add('lesson');
    final next = TopicProgress(
      title: title,
      lessonPercent: percent,
      nextHeading: nextHeading ?? current.nextHeading,
      doneKinds: done,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (current.lessonPercent == next.lessonPercent &&
        current.nextHeading == next.nextHeading &&
        current.title == next.title &&
        current.doneKinds.length == next.doneKinds.length &&
        topicProgress.containsKey(topicId)) {
      return;
    }
    topicProgress[topicId] = next;
    await _storage?.setString(
      _scopedKey(_topicProgressKey),
      jsonEncode(topicProgress.map(
        (key, value) => MapEntry(key, value.toJson()),
      )),
    );
  }

  static Map<int, CheckSummary> _decodeCheckSummaries(String? source) {
    if (source == null) return {};
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) return {};
      return {
        for (final entry in decoded.entries)
          if (int.tryParse(entry.key) case final id?)
            if (CheckSummary.fromJson(entry.value) case final summary?)
              id: summary,
      };
    } on Object {
      return {};
    }
  }

  Future<void> recordCheckSummary(int assignmentId, CheckSummary summary) async {
    checkSummaries[assignmentId] = summary;
    await _storage?.setString(
      _scopedKey(_checkSummariesKey),
      jsonEncode(checkSummaries.map(
        (key, value) => MapEntry(key.toString(), value.toJson()),
      )),
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
    earlierDrafts.clear();
    checkSummaries.clear();
    topicProgress.clear();
  }

  Future<void> saveDraft(
    int assignmentId,
    int assignmentVersion,
    String code,
  ) async {
    final previousVersion = codeDraftVersions[assignmentId];
    final previousCode = codeDrafts[assignmentId];
    // Keep older-version work aside instead of overwriting it.
    if (previousVersion != null &&
        previousVersion < assignmentVersion &&
        previousCode != null &&
        previousCode.trim().isNotEmpty) {
      earlierDrafts[assignmentId] = previousCode;
      await _storeEarlierDrafts();
    }
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
