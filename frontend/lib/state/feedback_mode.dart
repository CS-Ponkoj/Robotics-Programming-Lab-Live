import 'package:flutter/foundation.dart';

/// The study condition an instructor assigned to the signed-in account.
///
/// The server enforces each mode; the app only uses it to leave out controls
/// the account cannot use and to pick the account's theme colour.
enum FeedbackMode {
  traditional('traditional', 'Traditional'),
  tdd('tdd', 'TDD'),
  tddAi('tdd_ai', 'TDD + AI');

  const FeedbackMode(this.wire, this.label);

  final String wire;
  final String label;

  /// Hints belong to TDD + AI only (owner decision 2026-11-20). The server
  /// switch `TDD_BUILT_IN_HINTS` in feedback_modes.py gives TDD its built-in
  /// hints back; change this getter with it.
  bool get allowsHints => this == tddAi;
  /// Every mode gets the replay; Traditional's has no beam probe or links
  /// from failed checks (server-trimmed).
  bool get allowsSimulation => true;
  bool get allowsAi => this == tddAi;

  static FeedbackMode fromWire(String? value) => FeedbackMode.values.firstWhere(
        (mode) => mode.wire == value,
        orElse: () => FeedbackMode.tdd,
      );
}

/// Instructors always see everything; set from the server at each sign-in.
final currentFeedbackMode = ValueNotifier<FeedbackMode>(FeedbackMode.tddAi);
