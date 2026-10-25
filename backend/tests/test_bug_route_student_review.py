"""Independent student-work permutations and instructor contract checks."""
import itertools
import json
import math
from pathlib import Path

import pytest

from graders.python_function import PythonFunctionGrader
from models import Assignment, Submission
from sandbox import SubprocessSandbox
from config import Settings
from tutor import TutorService


def source(assignment_id):
    return json.loads((Path(__file__).parents[1] / f'assignments/assignment_{assignment_id}.json').read_text(encoding='utf-8'))


def target(data):
    return Assignment(id=data['id'], stable_id=data['stable_id'], version=data['version'],
                      title=data['title'], grader_type=data['grader_type'], grader_config=data['grader_config'])


def student_code(assignment_id, mask=(True, True, True, True), method='hypot'):
    params = 'start, hit, corner, leave, goal' if assignment_id == 1 else 'start, hit, corner_a, corner_b, leave, goal'
    name = 'calculate_bug2_route' if assignment_id == 1 else 'calculate_bug_route'
    distance = {
        'hypot': 'math.hypot(b[0]-a[0], b[1]-a[1])',
        'sqrt': 'math.sqrt((b[0]-a[0])**2 + (b[1]-a[1])**2)',
        'dist': 'math.dist(a, b)',
    }[method]
    boundary = 'd(hit, corner) + d(corner, leave)' if assignment_id == 1 else 'd(hit, corner_a) + d(corner_a, corner_b) + d(corner_b, leave)'
    values = ['d(start, hit)', boundary, 'd(leave, goal)', 'd(start, hit) + ' + boundary + ' + d(leave, goal)']
    return f'import math\ndef d(a, b):\n    return {distance}\ndef {name}({params}):\n    return ' + ', '.join(v if ok else '0.0' for v, ok in zip(values, mask))


@pytest.mark.parametrize('assignment_id', [1, 2])
@pytest.mark.parametrize('mask', list(itertools.product([False, True], repeat=4)))
def test_every_partial_credit_combination(assignment_id, mask):
    result = PythonFunctionGrader(SubprocessSandbox()).grade(target(source(assignment_id)), student_code(assignment_id, mask))
    assert result.execution_succeeded
    assert result.score == sum(mask) * 25
    assert result.passed == all(mask)
    assert [e.passed for e in result.evidence] == list(mask)


@pytest.mark.parametrize('assignment_id', [1, 2])
@pytest.mark.parametrize('method', ['hypot', 'sqrt', 'dist'])
def test_equivalent_student_approaches(assignment_id, method):
    result = PythonFunctionGrader(SubprocessSandbox()).grade(target(source(assignment_id)), student_code(assignment_id, method=method))
    assert result.passed and result.score == 100


@pytest.mark.parametrize('assignment_id', [1, 2])
def test_exact_return_contract_rejects_extra_values(assignment_id):
    code = student_code(assignment_id) + ', 999'
    result = PythonFunctionGrader(SubprocessSandbox()).grade(target(source(assignment_id)), code)
    assert not result.passed and result.score == 0
    assert not result.execution_succeeded


@pytest.mark.parametrize('assignment_id', [1, 2])
@pytest.mark.parametrize('ending, returned', [
    (', d(leave, goal)', 'returned 3'),
    ('', 'single value or nothing'),
])
def test_short_or_single_return_names_the_required_order(assignment_id, ending, returned):
    prefix = student_code(assignment_id).rsplit('    return ', 1)[0]
    code = prefix + '    return d(start, hit), d(start, hit)' + ending
    if not ending:
        code = prefix + '    return d(start, hit)'
    result = PythonFunctionGrader(SubprocessSandbox()).grade(target(source(assignment_id)), code)
    assert result.score == 0 and not result.execution_succeeded
    assert 'IndexError' not in result.execution_error
    assert 'TypeError' not in result.execution_error
    assert 'Return exactly 4 values in this order:' in result.execution_error
    assert returned in result.execution_error


def test_endless_loop_reports_the_time_limit():
    data = source(1)
    code = student_code(1).replace('    return ', '    while True:\n        pass\n    return ', 1)
    sandbox = SubprocessSandbox(timeout_seconds=1)
    result = PythonFunctionGrader(sandbox).grade(target(data), code)
    assert result.score == 0 and not result.execution_succeeded
    assert 'did not finish within the 1-second time limit' in result.execution_error


@pytest.mark.parametrize('assignment_id', [1, 2])
def test_return_order_is_not_masked_by_equal_displayed_distances(assignment_id):
    code = student_code(assignment_id, (True, True, True, False))
    code = code.replace('return d(start, hit),', 'return d(leave, goal),')
    code = code.replace(', d(leave, goal), 0.0', ', d(start, hit), 0.0')
    result = PythonFunctionGrader(SubprocessSandbox()).grade(target(source(assignment_id)), code)
    assert result.score == 25


@pytest.mark.parametrize('assignment_id', [1, 2])
@pytest.mark.parametrize('order', list(itertools.permutations(range(4))))
def test_all_return_order_permutations(assignment_id, order):
    code = student_code(assignment_id)
    expression = code.split('    return ', 2)[-1]
    # Expressions contain helper-call commas, so construct the independent
    # components first rather than splitting the return statement on commas.
    prefix, expression = code.rsplit('    return ', 1)
    code = prefix + '    values = (' + expression + ')\n    return ' + ', '.join(f'values[{i}]' for i in order)
    result = PythonFunctionGrader(SubprocessSandbox()).grade(target(source(assignment_id)), code)
    assert result.score == 25 * sum(i == j for i, j in enumerate(order))


@pytest.mark.parametrize('assignment_id', [1, 2])
@pytest.mark.parametrize('kind', ['syntax', 'runtime', 'missing_helper', 'missing_return', 'nan', 'infinity', 'unsafe_import'])
def test_student_errors_do_not_earn_success(assignment_id, kind):
    code = student_code(assignment_id)
    if kind == 'syntax':
        code += '\nif True print(1)'
    elif kind == 'runtime':
        code += '\nvalue = 1 / 0'
    elif kind == 'missing_helper':
        code = code.replace('def d(a, b):', 'def other(a, b):')
    elif kind == 'missing_return':
        code = code.rsplit('    return ', 1)[0] + '    pass'
    elif kind in ('nan', 'infinity'):
        code = code.rsplit('    return ', 1)[0] + "    return (float('" + ('nan' if kind == 'nan' else 'inf') + "'),) * 4"
    else:
        code = 'import os\n' + code
    result = PythonFunctionGrader(SubprocessSandbox()).grade(target(source(assignment_id)), code)
    assert result.score == 0 and not result.passed


@pytest.mark.parametrize('assignment_id', [1, 2])
def test_bug2_case_geometry_and_independent_expected_lengths(assignment_id):
    for case in source(assignment_id)['grader_config']['cases']:
        points = case['arguments']
        start, hit, *corners, leave, goal = points
        def cross(p):
            return (p[0]-start[0])*(goal[1]-start[1]) - (p[1]-start[1])*(goal[0]-start[0])
        assert abs(cross(hit)) < 1e-7, 'Hit point must be on the Bug2 m-line'
        assert abs(cross(leave)) < 1e-7, 'Leave point must be on the Bug2 m-line'
        assert math.dist(leave, goal) < math.dist(hit, goal)
        route = [hit, *corners, leave]
        segments = list(zip(route, route[1:]))
        assert all(a[0] == b[0] or a[1] == b[1] for a, b in segments)
        approach = math.dist(start, hit)
        boundary = sum(math.dist(a, b) for a, b in segments)
        departure = math.dist(leave, goal)
        assert case['expected'] == pytest.approx([approach, boundary, departure, approach + boundary + departure])


def test_completed_submission_does_not_get_failure_advice():
    data = source(1)
    assignment = target(data)
    assignment.misconceptions = data['common_misconceptions']
    submission = Submission(code=student_code(1), evidence={'execution_succeeded': True, 'score': 100, 'tests': [{'test_id': c['id'], 'passed': True, 'label': c['label']} for c in data['grader_config']['criteria']]})
    feedback = TutorService(Settings(openai_api_key=None)).feedback(assignment, submission, use_ai_tutor=False)
    assert 'still needs attention' not in feedback.diagnosis
    assert feedback.misconception == ''


def test_hint_levels_do_not_invent_unrelated_misconceptions():
    data = source(2)
    assignment = target(data)
    assignment.misconceptions = data['common_misconceptions']
    submission = Submission(code='', evidence={'execution_succeeded': True, 'score': 75, 'tests': [{'test_id': c['id'], 'passed': i != 3, 'label': c['label']} for i, c in enumerate(data['grader_config']['criteria'])]})
    feedback = TutorService(Settings(openai_api_key=None)).feedback(assignment, submission, hint_level=1, use_ai_tutor=False)
    assert feedback.misconception == '' or 'total' in feedback.misconception


def test_missing_check_evidence_is_not_called_success():
    submission = Submission(code='', evidence={'execution_succeeded': True, 'tests': []})
    feedback = TutorService(Settings(openai_api_key=None)).feedback(target(source(1)), submission, use_ai_tutor=False)
    assert 'no check results' in feedback.diagnosis
    assert 'all recorded checks passed' not in feedback.diagnosis
