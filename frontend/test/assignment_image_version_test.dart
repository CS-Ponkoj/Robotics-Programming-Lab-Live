import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/screens/assignment_workspace.dart';

void main() {
  test('assignment diagrams have a version-specific URL without changing alt',
      () {
    const html = '<img src="/images/2" alt="Robot route">';
    final old = versionAssignmentImages(html, 8);
    final current = versionAssignmentImages(html, 9);
    expect(old, contains('/images/2?assignment_version=8'));
    expect(current, contains('/images/2?assignment_version=9'));
    expect(current, contains('alt="Robot route"'));
    expect(versionAssignmentImages(current, 9), current);
  });
  test('preserves other assets and existing query arguments', () {
    expect(versionAssignmentImages("<img src='/course/images/2'>", 9),
        "<img src='/course/images/2'>");
    expect(versionAssignmentImages("<img src='/images/2?size=large'>", 9),
        contains('size=large&assignment_version=9'));
  });
}
