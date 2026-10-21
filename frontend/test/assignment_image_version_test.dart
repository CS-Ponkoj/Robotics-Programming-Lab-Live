import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/screens/assignment_workspace.dart';

void main() {
  test('assignment diagrams have a version-specific URL without changing alt',
      () {
    const html = '<img src="/images/2" alt="Robot route">';
    final old = versionAssignmentImages(html, 8);
    final current = versionAssignmentImages(html, 9);
    expect(old, contains('src="images/2?assignment_version=8"'));
    expect(current, contains('src="images/2?assignment_version=9"'));
    expect(current, contains('alt="Robot route"'));
    expect(versionAssignmentImages(current, 9), current);
  });
  test('diagram URLs keep an API base path prefix', () {
    final src = RegExp(r'src="([^"]+)"')
        .firstMatch(versionAssignmentImages('<img src="/images/2">', 9))![1]!;
    expect(Uri.parse('https://rpl.ponkoj.com/api/').resolve(src).toString(),
        'https://rpl.ponkoj.com/api/images/2?assignment_version=9');
    expect(Uri.parse('http://127.0.0.1:5100/').resolve(src).toString(),
        'http://127.0.0.1:5100/images/2?assignment_version=9');
  });
  test('preserves other assets and existing query arguments', () {
    expect(versionAssignmentImages("<img src='/course/images/2'>", 9),
        "<img src='/course/images/2'>");
    expect(versionAssignmentImages("<img src='/images/2?size=large'>", 9),
        contains('size=large&assignment_version=9'));
  });
}
