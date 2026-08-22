from code_tester import CodeTester


def test_allows_assignment_math_import():
    tester = CodeTester(
        1,
        """
import math
distance_to_hit = 10.0 / 3.0
distance_along_obstacle = 49.0 / 12.0
distance_leave_to_goal = 15.0 / 4.0
total_distance = 67.0 / 6.0
""",
        {},
    )

    tester.full_check()

    assert tester.exec_success is True
    assert tester.get_pass_results() == [True, True, True, True]


def test_rejects_import_outside_assignment_allowlist():
    tester = CodeTester(
        2,
        """
import os
distance_to_obstacle = 4
distance_along_obstacle = 4
distance_from_obstacle_to_goal = 4
total_path_length = 12
""",
        {},
    )

    tester.full_check()

    assert tester.exec_success is False
    assert "Import of 'os' is not allowed" in str(tester.get_exec_result())
    assert tester.get_pass_results() == [False, False, False, False]


def test_stops_submission_that_exceeds_execution_timeout(monkeypatch):
    monkeypatch.setattr("code_tester.EXECUTION_TIMEOUT_SECONDS", 0.2)
    tester = CodeTester(2, "while True:\n    pass", {})

    tester.full_check()

    assert tester.exec_success is False
    assert "TimeoutError" in str(tester.get_exec_result())


def test_caps_submission_output():
    tester = CodeTester(
        2,
        """
print("x" * 30000)
distance_to_obstacle = 4
distance_along_obstacle = 4
distance_from_obstacle_to_goal = 4
total_path_length = 12
""",
        {},
    )

    tester.full_check()

    assert tester.exec_success is True
    assert tester.get_code_output().endswith("[output truncated]")
    assert len(tester.get_code_output()) < 20_100
