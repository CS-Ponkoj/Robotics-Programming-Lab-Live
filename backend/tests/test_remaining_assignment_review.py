"""Student partial-work permutations and independent instructor contract checks."""
import ast
import itertools
import json
import math
from pathlib import Path

import pytest

from graders.python_function import PythonFunctionGrader
from graders.ros2_topic import Ros2TopicGrader
from models import Assignment
from sandbox import SubprocessSandbox


ROOT = Path(__file__).resolve().parents[2]


def source(i):
    return json.loads((ROOT / f'backend/assignments/assignment_{i}.json').read_text(encoding='utf-8'))


def target(i):
    data = source(i)
    return Assignment(id=i, title=data['title'], stable_id=data['stable_id'],
                      version=data['version'], grader_config=data['grader_config'],
                      public_tests=data['public_tests'], asset_manifest=data['asset_manifest'])


def answer(i):
    return (ROOT / f'assignments_answers/assignment_{i}_answer.py').read_text(encoding='utf-8')


def partial(i, mask):
    code = answer(i)
    name = source(i)['grader_config']['function_name']
    values = ', '.join(f'values[{n}]' if ok else ('""' if i == 3 and n == 6 else '-999')
                       for n, ok in enumerate(mask))
    return code + f'\noriginal = {name}\ndef {name}(*args):\n    values = original(*args)\n    return ({values},)\n'


@pytest.mark.parametrize('i,n', [(3, 8), (4, 5)])
def test_all_partial_work_combinations(i, n):
    # Real isolated execution, not a scoring mock: every subset of solved outputs.
    grader = PythonFunctionGrader(SubprocessSandbox())
    assignment = target(i)
    for mask in itertools.product([False, True], repeat=n):
        result = grader.grade(assignment, partial(i, mask))
        assert result.execution_succeeded, mask
        assert result.score == round(sum(mask) / n * 100), mask
        assert [item.passed for item in result.evidence] == list(mask), mask
        assert result.passed == all(mask), mask


@pytest.mark.parametrize('i', [3, 4])
def test_maintained_answer_and_untouched_starter(i):
    grader = PythonFunctionGrader(SubprocessSandbox())
    assert grader.grade(target(i), answer(i)).score == 100
    assert grader.grade(target(i), source(i)['starter_code']).score == 0


@pytest.mark.parametrize('i', [3, 4])
@pytest.mark.parametrize('kind', ['syntax', 'runtime', 'missing_return', 'extra_return', 'unsafe_import'])
def test_student_errors_cannot_pass(i, kind):
    code = answer(i)
    name = source(i)['grader_config']['function_name']
    if kind == 'syntax':
        code += '\nif True print(1)'
    elif kind == 'runtime':
        code += '\nraise ValueError("student error")'
    elif kind == 'unsafe_import':
        code = 'import os\n' + code
    else:
        suffix = 'None' if kind == 'missing_return' else 'original(*args) + (99,)'
        code += f'\noriginal = {name}\ndef {name}(*args):\n    return {suffix}\n'
    result = PythonFunctionGrader(SubprocessSandbox()).grade(target(i), code)
    assert not result.passed and result.score == 0


def test_vfh_hardcoded_full_circle_is_not_complete():
    code = answer(4).replace('len(lidar_readings),', '360,')
    result = PythonFunctionGrader(SubprocessSandbox()).grade(target(4), code)
    assert result.score == 80
    assert not result.evidence[0].passed


def test_vfh_numpy_and_math_are_equivalent():
    code = answer(4).replace('import numpy as np', 'import math').replace('np.sin', 'math.sin').replace('np.radians', 'math.radians')
    assert PythonFunctionGrader(SubprocessSandbox()).grade(target(4), code).passed


@pytest.mark.parametrize('i', [3, 4])
def test_expected_values_have_an_independent_mathematical_oracle(i):
    for case in source(i)['grader_config']['cases']:
        args = case['arguments']
        if i == 3:
            speed, radius, wm, ws, rm, rs, floors, start, goal, main, service, waypoints = args
            points = [start, *waypoints, main]
            m = sum(math.dist(a, b) for a, b in zip(points, points[1:]))
            s = math.dist(start, service) + math.pi * radius
            md, sd = math.dist(main, goal), math.dist(service, goal)
            mt, st = (m + md) / speed + wm + floors * rm, (s + sd) / speed + ws + floors * rs
            expected = [m, s, md, sd, mt, st, 'Main Elevator' if mt < st else 'Service Elevator', min(mt, st)]
        else:
            seed, lo, hi, goal, width, probe = args
            readings = dict(seed)
            readings.update((a, 10 + 2 * math.sin(math.radians(a))) for a in range(lo, hi + 1))
            candidates = range(goal - width, goal + width + 1)
            best = min(candidates, key=lambda a: (1 / readings[a] ** 2, a))
            expected = [len(readings), len(candidates), 1 / readings[probe] ** 2, best, 1 / readings[best] ** 2]
        for actual, wanted in zip(case['expected'], expected):
            assert actual == wanted if isinstance(wanted, str) else math.isclose(actual, wanted, abs_tol=1e-9)


@pytest.mark.parametrize('i', [5, 6])
def test_all_ros_weight_combinations(i):
    # This isolates weighting only; actual topic behavior is tested with Docker.
    assignment = target(i)
    ids = [item['id'] for item in source(i)['public_tests']]
    weights = source(i)['grader_config']['test_weights']
    scaffold = set(source(i)['grader_config']['scaffold_tests'])
    class Executor:
        def execute(self, code, files, config):
            return {'success': True, 'tests': [dict(id=t, passed=p) for t, p in zip(ids, self.mask)]}
    executor = Executor()
    for mask in itertools.product([False, True], repeat=len(ids)):
        executor.mask = mask
        result = Ros2TopicGrader(executor).grade(assignment, '')
        # Supplied build/start credit counts only alongside a passing behavior check.
        behavior = any(ok for t, ok in zip(ids, mask) if t not in scaffold)
        assert result.score == sum(
            weights[t] for t, ok in zip(ids, mask) if ok and (behavior or t not in scaffold)
        )
        assert result.passed == all(mask)


def motion_checks():
    # Extract the pure function without requiring host ROS installation.
    tree = ast.parse((ROOT / 'backend/ros2_topic_harness.py').read_text(encoding='utf-8'))
    wanted = {'motion_checks', 'unused_axes_zero', 'is_stop', 'STOP_TOLERANCE'}
    nodes = [
        item for item in tree.body
        if (isinstance(item, ast.FunctionDef) and item.name in wanted)
        or (isinstance(item, ast.Assign)
            and any(getattr(target, 'id', None) in wanted for target in item.targets))
    ]
    scope = {'math': math}
    exec(compile(ast.Module(body=nodes, type_ignores=[]), '<motion-checks>', 'exec'), scope)
    return scope['motion_checks']


@pytest.mark.parametrize('launch_delay', [0.0, 0.5, 1.8])
@pytest.mark.parametrize('stop_at,valid', [(4.0, False), (5.0, True), (6.0, False)])
def test_ros_timing_does_not_reward_late_stops(launch_delay, stop_at, valid):
    samples = [(launch_delay + n / 10, 0.2 if n / 10 < stop_at else 0.0, 0.0) for n in range(80)]
    assert motion_checks()(samples, 0.2, 0.02, 0.01, 5, 0.5)['safe-stop'] == valid


def test_ros_resuming_rotation_is_not_holding_a_safe_stop():
    samples = [(n / 10, 0.2 if n < 50 else 0.0, 0.1 if n > 60 else 0.0) for n in range(80)]
    assert not motion_checks()(samples, 0.2, 0.02, 0.01, 5, 0.5)['hold-stop']


def test_ros_three_stop_commands_then_silence_is_not_continuous_stop():
    samples = [(0.5 + n / 10, 0.2 if n < 50 else 0.0, 0.0) for n in range(54)]
    checks = motion_checks()(samples, 0.2, 0.02, 0.01, 5, 0.5, 5, 8.3)
    assert checks['safe-stop']
    assert not checks['hold-stop']


def test_ros_sparse_stop_messages_do_not_meet_the_publication_rate():
    samples = [(n / 10, 0.2, 0.0) for n in range(50)]
    samples += [(5.0, 0.0, 0.0), (5.1, 0.0, 0.0), (8.3, 0.0, 0.0)]
    assert not motion_checks()(samples, 0.2, 0.02, 0.01, 5, 0.5, 5, 8.3)['hold-stop']


@pytest.mark.parametrize('field', range(4))
@pytest.mark.parametrize('value', [0.1, -0.1, math.nan, math.inf])
def test_ros_unused_twist_fields_must_stay_zero(field, value):
    def sample(n):
        extras = [0.0, 0.0, 0.0, 0.0]
        extras[field] = value
        return (n / 10, 0.2 if n < 50 else 0.0, 0.0, *extras)
    checks = motion_checks()([sample(n) for n in range(80)], 0.2, 0.02, 0.01, 5, 0.5, 5, 7.9)
    assert checks['forward-motion']
    assert not checks['straight-motion']
    assert not checks['safe-stop']
    assert not checks['hold-stop']


def test_ros_unused_twist_fields_while_stopped_break_the_hold():
    samples = [(n / 10, 0.2 if n < 50 else 0.0, 0.0, 0.0, 0.0, 0.0, 0.1 if n > 60 else 0.0)
               for n in range(80)]
    checks = motion_checks()(samples, 0.2, 0.02, 0.01, 5, 0.5, 5, 7.9)
    assert checks['safe-stop']
    assert not checks['straight-motion']
    assert not checks['hold-stop']


def test_ros_clean_six_field_commands_pass_every_motion_check():
    samples = [(n / 10, 0.2 if n < 50 else 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) for n in range(80)]
    checks = motion_checks()(samples, 0.2, 0.02, 0.01, 5, 0.5, 5, 7.9)
    assert all(checks.values())


@pytest.mark.parametrize('i', [5, 6])
def test_ros_reference_answer_path_exists(i):
    assert (ROOT / source(i)['reference_solution_path']).is_file()
