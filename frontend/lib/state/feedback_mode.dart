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

  bool get allowsHints => this != traditional;
  bool get allowsSimulation => this != traditional;
  bool get allowsAi => this == tddAi;

  static FeedbackMode fromWire(String? value) => FeedbackMode.values.firstWhere(
        (mode) => mode.wire == value,
        orElse: () => FeedbackMode.tdd,
      );
}

/// Instructors always see everything; set from the server at each sign-in.
final currentFeedbackMode = ValueNotifier<FeedbackMode>(FeedbackMode.tddAi);
