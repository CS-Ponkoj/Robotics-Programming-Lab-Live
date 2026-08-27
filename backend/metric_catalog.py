"""Versioned, machine-readable definitions for implemented Phase 1 metrics."""

from typing import Any


CATALOG_VERSION = "1.1"
PHASE = 1

# id, name, definition, formula, unit, audience
_METRICS = (
    ("POP-01", "Assigned students", "Active non-demo students assigned to published assignments.", "distinct active non-demo student users", "students", "instructor"),
    ("POP-03", "Students started", "Assigned students with meaningful assignment activity or a valid attempt.", "distinct started students", "students", "instructor"),
    ("POP-04", "Participation rate", "Share of assigned students who started.", "100 * students_started / assigned_students", "percent", "instructor"),
    ("POP-05", "Students completed", "Started students with at least one successful current-version assignment.", "distinct students with passed=true", "students", "instructor"),
    ("POP-06", "Completion rate", "Share of started students who completed at least one assignment.", "100 * students_completed / students_started", "percent", "instructor"),
    ("POP-07", "Assignment uptake rate", "Share of assigned students who started an assignment version.", "100 * assignment_starters / assigned_students", "percent", "instructor"),
    ("POP-08", "Return-session rate", "Share of started students with two or more active sessions.", "100 * students_with_2plus_sessions / students_started", "percent", "instructor"),
    ("OUT-01", "First-attempt score", "Score on the first valid attempt for an assignment version.", "first valid attempt score", "percent", "student,instructor"),
    ("OUT-02", "Final-attempt score", "Score on the latest valid attempt for an assignment version.", "latest valid attempt score", "percent", "student,instructor"),
    ("OUT-03", "Best-attempt score", "Highest valid score for an assignment version.", "max(valid attempt score)", "percent", "student,instructor"),
    ("OUT-04", "Absolute score gain", "Change from first to latest valid score.", "latest score - first score", "percentage_points", "student,instructor"),
    ("OUT-05", "Best score gain", "Change from first score to best score.", "best score - first score", "percentage_points", "student,instructor"),
    ("OUT-07", "Successful solution", "Whether a valid attempt passed the assignment version.", "1 if any valid passed attempt else 0", "boolean", "student,instructor"),
    ("OUT-08", "First-attempt success rate", "Share of starters who passed on their first valid attempt.", "100 * first_attempt_successes / students_with_valid_attempt", "percent", "instructor"),
    ("OUT-09", "Overall success rate", "Share of assignment starters who completed it.", "100 * completed_students / started_students", "percent", "instructor"),
    ("OUT-10", "Test pass percentage", "Share of all executed tests passed on the latest valid attempt.", "100 * passed_tests / executed_tests", "percent", "student,instructor"),
    ("OUT-11", "Public-test pass percentage", "Share of public tests passed on the latest valid attempt.", "100 * passed_public_tests / executed_public_tests", "percent", "student,instructor"),
    ("OUT-12", "Hidden-test pass percentage", "Aggregate hidden-test pass share without test identities.", "100 * passed_hidden_tests / executed_hidden_tests", "percent", "instructor"),
    ("OUT-15", "Assignment completion status", "Version-specific state: not started, started, partial, or completed.", "state from activity, attempts, and first success", "category", "student,instructor"),
    ("ATT-01", "Total valid attempts", "Student-related attempts excluding infrastructure failures.", "count(valid attempts)", "attempts", "student,instructor"),
    ("ATT-02", "Attempts to first success", "Sequence number of the first successful valid attempt.", "index(first passed valid attempt)", "attempts", "student,instructor"),
    ("ATT-03", "Unsuccessful attempts", "Valid failures before first success, or all valid attempts for non-completers.", "failures before success or deadline", "attempts", "student,instructor"),
    ("TIME-01", "Active working time", "Heartbeat time while visible and recently interactive.", "sum(accepted active heartbeat seconds)", "seconds", "student,instructor"),
    ("TIME-02", "Time to first attempt", "Accumulated active time at the first valid attempt.", "first_attempt.active_seconds_snapshot", "seconds", "student,instructor"),
    ("TIME-03", "Time to first success", "Accumulated active time at first successful attempt.", "first_success.active_seconds_snapshot", "seconds", "student,instructor"),
    ("TIME-04", "Time to final attempt", "Accumulated active time at the latest valid attempt.", "latest_attempt.active_seconds_snapshot", "seconds", "student,instructor"),
    ("TIME-05", "Median time between attempts", "Median difference between consecutive active-time snapshots.", "median(current_snapshot - previous_snapshot)", "seconds", "student,instructor"),
    ("TIME-09", "Session count", "Count of sessions containing recorded active time.", "count(sessions where active_seconds > 0)", "sessions", "student,instructor"),
    ("TIME-10", "Median session duration", "Median active duration across non-empty sessions.", "median(session.active_seconds)", "seconds", "student,instructor"),
    ("ERR-01", "Syntax-error count", "Valid attempts classified as student syntax errors.", "count(status=syntax_error)", "attempts", "student,instructor"),
    ("ERR-02", "Runtime-error count", "Valid attempts classified as student runtime errors.", "count(status=runtime_error)", "attempts", "student,instructor"),
    ("ERR-03", "Timeout count", "Valid attempts terminated for student-code timeout.", "count(status=timeout)", "attempts", "student,instructor"),
    ("ERR-04", "Failed-test count", "Failed executed public tests across valid attempts.", "sum(public tests where passed=false)", "tests", "student,instructor"),
    ("ERR-05", "Unsafe-code rejection count", "Attempts rejected by the execution safety policy.", "count(status=rejected and reason!=size_limit)", "attempts", "student,instructor"),
    ("ERR-06", "Excessive-output count", "Attempts whose captured output reached the configured limit.", "count(output_truncated=true)", "attempts", "student,instructor"),
    ("ERR-07", "Oversized-submission count", "Attempts rejected because submitted code exceeded the size limit.", "count(rejection_reason=size_limit)", "attempts", "student,instructor"),
    ("ERR-08", "Unique error categories", "Distinct student-caused error categories for an assignment version.", "count(distinct student error status)", "categories", "student,instructor"),
    ("ERR-16", "Error-free attempt rate", "Share of valid attempts without a student execution error.", "100 * error_free_attempts / valid_attempts", "percent", "student,instructor"),
    ("TUT-01", "Built-in hint requests", "Successfully delivered non-AI progressive hints.", "count(delivered fallback progressive hints)", "interactions", "student,instructor"),
    ("TUT-02", "AI interaction count", "Recorded valid requests for AI tutoring.", "count(valid AI tutor requests)", "interactions", "student,instructor"),
    ("TUT-04", "Hint level reached", "Highest delivered progressive hint level.", "max(delivered hint_level)", "level", "student,instructor"),
    ("ASG-01", "Median final score", "Median latest valid score among assignment starters.", "median(student final scores)", "percent", "instructor"),
    ("ASG-02", "Score distribution", "Counts of final scores in fixed score bands.", "count(final scores by 0-59,60-69,70-79,80-89,90-100)", "students", "instructor"),
    ("ASG-03", "Median attempts to success", "Median first-success attempt number among completers.", "median(attempts_to_first_success)", "attempts", "instructor"),
    ("ASG-04", "Median active completion time", "Median active seconds to first success among completers with tracked time.", "median(active_seconds_to_completion)", "seconds", "instructor"),
    ("ASG-05", "Most-failed tests", "Public tests ranked by distinct affected students.", "rank public tests by distinct failing students", "students", "instructor"),
    ("ASG-06", "Most-common errors", "Safe error categories ranked by affected students.", "rank categories by students with count > 0", "students", "instructor"),
    ("SYS-09", "Missing-event rate", "Submission workflows missing their expected research event.", "100 * missing submission events / persisted submissions", "percent", "instructor"),
    ("SYS-10", "Duplicate-event rate", "Repeated logical event groups among recorded events.", "100 * duplicate event groups / events", "percent", "instructor"),
    ("SYS-11", "Orphan-record count", "Research records whose required student parent is absent.", "count(orphan submissions and learning events)", "records", "instructor"),
    ("SYS-12", "Version-missing rate", "Attempts without a valid assignment version.", "100 * missing-version attempts / attempts", "percent", "instructor"),
    ("SYS-13", "Condition-missing rate", "Study attempts without a participant condition when conditions apply.", "not applicable until Phase 2 condition assignment", "percent", "instructor"),
    ("SYS-14", "Timestamp-order error rate", "Sessions or events with impossible timestamp ordering.", "100 * invalid timestamp chains / checked chains", "percent", "instructor"),
    ("SYS-15", "Export reconciliation", "Whether export row counts match authoritative database counts.", "exported matching rows / expected rows", "status", "instructor"),
    ("SYS-18", "Demo-data contamination count", "Persistent research records linked to demo accounts.", "count(persistent demo submissions and events)", "records", "instructor"),
)


def implemented_metric_catalog() -> dict[str, Any]:
    metrics = [
        {
            "metric_id": metric_id,
            "phase": PHASE,
            "name": name,
            "definition": definition,
            "formula": formula,
            "unit": unit,
            "audience": audience.split(","),
            "implementation_status": "implemented",
        }
        for metric_id, name, definition, formula, unit, audience in _METRICS
    ]
    return {
        "catalog_version": CATALOG_VERSION,
        "phase": PHASE,
        "metrics": metrics,
    }


assert len(_METRICS) == 55
