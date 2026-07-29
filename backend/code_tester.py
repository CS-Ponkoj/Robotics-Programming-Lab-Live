import json
import os
from pathlib import Path
import subprocess
import sys

from unittests.math_question_unittest import MathQuestionTestCase


EXECUTION_TIMEOUT_SECONDS = 5
WORKER_PATH = Path(__file__).with_name("submission_worker.py")


class InterpreterError(Exception):
    pass


class CodeTester:
    def __init__(self, id, submitted_code, namespace):
        self.exec_result = ""
        self.id = id
        self.code_output = ""
        self.submitted_code = submitted_code
        self.namespace = namespace
        self.results_array = []
        self.pass_results = []
        self.exec_success = False

        assignment_path = (
            Path(__file__).resolve().parent
            / "assignments"
            / f"assignment_{self.id}.json"
        )
        assignment = json.loads(assignment_path.read_text(encoding="utf-8"))
        self.vals = assignment["vals"]

    def full_check(self):
        self.exec_result = self.code_check()
        self.results_array = self.code_check_unittest()

    def get_tested_vals(self):
        return list(self.vals.keys())

    def get_results_array(self):
        return self.results_array

    def get_pass_results(self):
        return self.pass_results

    def get_code_output(self):
        return self.code_output

    def get_exec_result(self):
        return self.exec_result

    def code_check(self):
        request_data = json.dumps(
            {
                "code": self.submitted_code,
                "result_names": list(self.vals.keys()),
            }
        )
        creation_flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0

        try:
            completed = subprocess.run(
                [sys.executable, "-I", str(WORKER_PATH)],
                input=request_data,
                capture_output=True,
                text=True,
                timeout=EXECUTION_TIMEOUT_SECONDS,
                check=False,
                creationflags=creation_flags,
            )
        except subprocess.TimeoutExpired:
            return InterpreterError(
                f"TimeoutError in submission: execution exceeded "
                f"{EXECUTION_TIMEOUT_SECONDS} seconds"
            )

        if completed.returncode != 0:
            detail = completed.stderr.strip() or "Submission worker failed."
            return InterpreterError(detail)

        try:
            result = json.loads(completed.stdout)
        except json.JSONDecodeError:
            return InterpreterError("Submission worker returned an invalid response.")

        self.code_output = result.get("output", "")
        self.namespace.update(result.get("values", {}))
        self.exec_success = result.get("success") is True
        if self.exec_success:
            return ""
        return InterpreterError(result.get("error", "Submission failed."))

    def code_check_unittest(self):
        tester = MathQuestionTestCase(
            self.namespace,
            list(self.vals.keys()),
            list(self.vals.values()),
        )
        results = tester.test_vals()
        self.pass_results = tester.get_results()
        return results
