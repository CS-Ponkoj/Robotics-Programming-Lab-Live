import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/services/research_api.dart';

void main() {
  test('research tracker excludes time after the 15 minute idle window', () {
    var now = DateTime.utc(2026, 8, 26, 12);
    final tracker = ResearchTracker(
      clock: () => now,
      pageVisible: () => true,
    );

    expect(tracker.isRecentlyActive(), isTrue);
    now = now.add(const Duration(minutes: 15));
    expect(tracker.isRecentlyActive(), isTrue);
    now = now.add(const Duration(seconds: 1));
    expect(tracker.isRecentlyActive(), isFalse);

    tracker.recordUserInteraction();
    expect(tracker.isRecentlyActive(), isTrue);
  });
}
