import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/screens/study_data_page.dart';
import 'package:iuse_demo/services/study_data_api.dart';

const _catalog = {
  'tables': [
    {
      'name': 'ai_questions_and_hints',
      'title': 'AI questions and hints',
      'description': 'Every question and hint.',
      'has_assignment': true,
    },
    {
      'name': 'sign_ins',
      'title': 'Sign-ins',
      'description': 'Every sign-in.',
      'has_assignment': false,
    },
  ],
  'participants': [
    {'id': 'u1', 'participant_code': 'P-001', 'feedback_mode': 'tdd_ai'},
  ],
  'assignments': [
    {'id': 7, 'label': 'Assignment 1'},
  ],
};

Map<String, dynamic> _page(String table, {int total = 1, bool empty = false}) =>
    {
      'table': table,
      'columns': [
        {'key': 'participant_code', 'label': 'Participant', 'help': ''},
        {'key': 'feedback_mode', 'label': 'Mode', 'help': ''},
        {'key': 'student_question', 'label': 'Student question', 'help': ''},
        {'key': 'attempt_id', 'label': 'Attempt', 'help': ''},
      ],
      'rows': empty
          ? []
          : [
              {
                'participant_code': 'P-001',
                'feedback_mode': 'tdd_ai',
                'student_question': 'Why does my robot not stop?',
                'attempt_id': 'a1',
              },
            ],
      'total': total,
      'page': 1,
      'page_size': 50,
    };

class _Calls {
  final tables = <String>[];
  final filters = <StudyDataFilters>[];
  final sorts = <String?>[];
  final downloads = <String>[];
  final codes = <String>[];
}

Widget _app(_Calls calls, {bool empty = false, int total = 1}) => MaterialApp(
      home: StudyDataPage(
        loadCatalog: ({bool includeTestAccounts = false}) async => _catalog,
        loadTable: (table,
            {required filters,
            int page = 1,
            int pageSize = 50,
            String? sort,
            bool descending = true}) async {
          calls.tables.add(table);
          calls.filters.add(filters);
          calls.sorts.add(sort);
          return _page(table, empty: empty, total: total);
        },
        downloadCsv: (table,
            {required filters, String? sort, bool descending = true}) async {
          calls.downloads.add(table);
          return true;
        },
        loadCode: (attemptId) async {
          calls.codes.add(attemptId);
          return {'code': 'def build_node():\n    pass\n'};
        },
      ),
    );

void main() {
  testWidgets('shows the AI questions table and its rows', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = _Calls();
    await tester.pumpWidget(_app(calls));
    await tester.pumpAndSettle();

    expect(calls.tables, ['ai_questions_and_hints']);
    expect(find.byKey(const Key('study-table-sign_ins')), findsOneWidget);
    expect(find.text('Why does my robot not stop?'), findsOneWidget);
    expect(find.text('TDD + AI'), findsWidgets);
    expect(find.text('1–1 of 1'), findsOneWidget);
  });

  testWidgets('switches tables, sorts, and downloads the CSV', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = _Calls();
    await tester.pumpWidget(_app(calls));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Student question').first);
    await tester.pumpAndSettle();
    expect(calls.sorts.last, 'student_question');

    await tester.tap(find.byKey(const Key('study-table-sign_ins')));
    await tester.pumpAndSettle();
    expect(calls.tables.last, 'sign_ins');
    expect(find.byKey(const Key('study-filter-assignment')), findsNothing);

    await tester.tap(find.byKey(const Key('study-data-download')));
    await tester.pumpAndSettle();
    expect(calls.downloads, ['sign_ins']);
    expect(find.text('Downloaded sign_ins.csv'), findsOneWidget);
  });

  testWidgets('a mode filter reloads the table with that mode', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = _Calls();
    await tester.pumpWidget(_app(calls));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('study-filter-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Traditional').last);
    await tester.pumpAndSettle();
    expect(calls.filters.last.feedbackMode, 'traditional');
    expect(find.byKey(const Key('study-filter-clear')), findsOneWidget);

    // Clear filters resets the data and what the dropdown shows.
    await tester.tap(find.byKey(const Key('study-filter-clear')));
    await tester.pumpAndSettle();
    expect(calls.filters.last.feedbackMode, isNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('study-filter-mode')),
        matching: find.text('All modes'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a row opens the full record and the attempt code',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = _Calls();
    await tester.pumpWidget(_app(calls));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Why does my robot not stop?'));
    await tester.pumpAndSettle();
    expect(find.text('Record'), findsOneWidget);
    await tester.tap(find.byKey(const Key('study-data-view-code')));
    await tester.pumpAndSettle();
    expect(calls.codes, ['a1']);
    expect(find.byKey(const Key('study-data-code')), findsOneWidget);
  });

  testWidgets('phone width uses a table picker and shows an empty state',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = _Calls();
    await tester.pumpWidget(_app(calls, empty: true, total: 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('study-table-picker')), findsOneWidget);
    expect(find.byKey(const Key('study-data-empty')), findsOneWidget);
    expect(find.text('0–0 of 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
