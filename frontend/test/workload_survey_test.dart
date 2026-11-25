import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/models/unittest_feedback_dto.dart';
import 'package:iuse_demo/screens/assignment_workspace.dart' as app;
import 'package:iuse_demo/services/assignment_api.dart';
import 'package:iuse_demo/services/workload_survey_api.dart';
import 'package:iuse_demo/widgets/workload_survey_dialog.dart';

const _keys = [
  'mental_demand',
  'physical_demand',
  'temporal_demand',
  'performance',
  'effort',
  'frustration',
];

WorkloadForm _form() => WorkloadForm.fromJson({
      'form_version': 'tlx-raw-1',
      'instructions': 'Higher is worse on every scale.',
      'step': 5,
      'items': [
        for (final key in _keys)
          {
            'key': key,
            'title': key,
            'question': 'Question for $key?',
            'definition': 'Definition of $key.',
            'low': key == 'performance' ? 'Good' : 'Low',
            'high': key == 'performance' ? 'Poor' : 'High',
          },
      ],
    })!;

Future<void> _open(
  WidgetTester tester,
  WorkloadSubmitter submitter, {
  ValueChanged<bool>? onClosed,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () async {
              final saved = await showWorkloadSurveyDialog(
                context,
                assignmentId: 7,
                form: _form(),
                trigger: 'finished_button',
                submitter: submitter,
              );
              onClosed?.call(saved);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _rate(WidgetTester tester, String key) async {
  final slider = find.byKey(Key('workload-slider-$key'));
  await tester.ensureVisible(slider);
  await tester.pumpAndSettle();
  // Tap left of centre: 0-100 maps across the track.
  final box = tester.getRect(slider);
  await tester.tapAt(Offset(box.left + box.width * 0.3, box.center.dy));
  await tester.pumpAndSettle();
}

void main() {
  test('status parses the form and only an open form can be answered', () {
    final status = WorkloadSurveyStatus.fromJson({
      'offered': true,
      'completed': false,
      'has_attempt': false,
      'form': {
        'form_version': 'tlx-raw-1',
        'instructions': 'x',
        'items': [
          {'key': 'effort', 'title': 'Effort'},
        ],
      },
    });
    expect(status.open, isTrue);
    expect(status.form!.items.single.key, 'effort');
    expect(status.copyWith(completed: true).open, isFalse);
    expect(
      WorkloadSurveyStatus.fromJson({'offered': false, 'form': null}).open,
      isFalse,
    );
  });

  testWidgets('scales start unrated; partial answers are sent as null',
      (tester) async {
    Map<String, int?>? sent;
    String? sentTrigger;
    bool? closed;
    await _open(tester, (id,
        {required ratings, required trigger, required openedAt}) async {
      sent = ratings;
      sentTrigger = trigger;
    }, onClosed: (saved) => closed = saved);

    for (final key in _keys) {
      expect(
        tester.widget<Text>(find.byKey(Key('workload-value-$key'))).data,
        'Not rated',
      );
    }
    final submit = find.byKey(const Key('workload-survey-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await _rate(tester, 'mental_demand');
    final value = tester
        .widget<Text>(find.byKey(const Key('workload-value-mental_demand')))
        .data!;
    expect(int.parse(value) % 5, 0);
    expect(find.byKey(const Key('workload-unrated-note')), findsOneWidget);

    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(sent!.keys, _keys);
    expect(sent!['mental_demand'], int.parse(value));
    expect(sent!['effort'], isNull);
    expect(sentTrigger, 'finished_button');
  });

  testWidgets('a failed save keeps the answers and explains', (tester) async {
    await _open(tester, (id,
        {required ratings, required trigger, required openedAt}) async {
      throw const ApiRequestException('You have already answered this survey.');
    });
    await _rate(tester, 'effort');
    final submit = find.byKey(const Key('workload-survey-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workload-survey-dialog')), findsOneWidget);
    expect(find.text('You have already answered this survey.'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('workload-value-effort'))).data,
      isNot('Not rated'),
    );
  });

  testWidgets('the form fits a phone width without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester,
        (id, {required ratings, required trigger, required openedAt}) async {});
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('workload-survey-later')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workload-survey-dialog')), findsNothing);
  });

  testWidgets('results show the finished card only when the survey is open',
      (tester) async {
    var opened = 0;
    const data = UnittestFeedbackDto(
      id: 7,
      submissionId: 'run-1',
      testedVals: [],
      pass: true,
      unittestFeedback: [''],
      unittestPassResults: [true],
      codeExecResult: '',
      codeOutput: '',
      execSuccess: true,
      hint: '',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: app.Feedback(data: data, onFinished: () => opened++),
      ),
    ));
    await tester.tap(find.byKey(const Key('finished-button')));
    expect(opened, 1);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: app.Feedback(data: data)),
    ));
    expect(find.byKey(const Key('finished-card')), findsNothing);
    expect(find.byKey(const Key('survey-saved')), findsNothing);

    // After saving, Results confirms it (a SnackBar sits under the panel).
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: app.Feedback(data: data, surveySaved: true)),
    ));
    expect(find.byKey(const Key('survey-saved')), findsOneWidget);
  });
}
