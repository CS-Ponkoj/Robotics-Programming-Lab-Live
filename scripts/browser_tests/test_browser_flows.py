"""End-to-end browser checks for the running local staging application.

These tests drive a real Chrome browser against the stack started by
scripts/run-local.ps1 or scripts/run-local.sh. Run them with
scripts/run-browser-tests.ps1 or scripts/run-browser-tests.sh.

The student flow uses the memory-only student demo, so it creates no database
rows. The instructor flow signs in with the account named by
E2E_INSTRUCTOR_LOGIN / E2E_INSTRUCTOR_PASSWORD and changes no course or
research data (signing in and out still records the normal session and audit
rows). It is skipped when those variables are not set.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

import pytest
from playwright.sync_api import Page, expect, sync_playwright

FRONTEND_URL = os.environ.get("E2E_FRONTEND_URL", "http://127.0.0.1:8080").rstrip("/")
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
# Read at run time only; the maintained answer is never copied into tests.
ASSIGNMENT_1_ANSWER = REPOSITORY_ROOT / "assignments_answers" / "assignment_1_answer.py"
GRADING_TIMEOUT_MS = 60_000


@pytest.fixture(scope="module")
def browser():
    with sync_playwright() as playwright:
        channel = os.environ.get("E2E_BROWSER_CHANNEL", "chrome")
        launched = playwright.chromium.launch(
            channel=None if channel == "chromium" else channel,
            headless=os.environ.get("E2E_HEADED") != "1",
        )
        yield launched
        launched.close()


@pytest.fixture
def page(browser, request, tmp_path_factory):
    context = browser.new_context(viewport={"width": 1280, "height": 800})
    opened = context.new_page()
    opened.set_default_timeout(30_000)
    yield opened
    if getattr(request.node, "call_failed", False):
        screenshot = tmp_path_factory.getbasetemp() / f"{request.node.name}.png"
        opened.screenshot(path=str(screenshot))
        print(f"Failure screenshot: {screenshot}")
    context.close()


def open_app(page: Page) -> None:
    """Load the app and turn on Flutter's accessibility tree for locators."""
    page.goto(f"{FRONTEND_URL}/")
    placeholder = page.locator("flt-semantics-placeholder")
    placeholder.wait_for(state="attached", timeout=60_000)
    placeholder.dispatch_event("click")
    expect(page.get_by_role("button", name="Sign in")).to_be_visible()


def type_into(page: Page, label: str, text: str) -> None:
    # Flutter listens for key events; Playwright's fill() bypasses them.
    page.get_by_label(label).click()
    page.keyboard.type(text)


def wait_for_text(page: Page, text: str, timeout: int = 30_000) -> None:
    # Text a screen reader can reach, not just pixels on the canvas.
    expect(page.locator("flt-semantics-host")).to_contain_text(text, timeout=timeout)


def replace_editor_code(page: Page, code: str) -> None:
    # The editor's accessibility node spans the whole window, so click inside
    # the code area itself: the left pane, below the editor toolbar.
    viewport = page.viewport_size
    page.mouse.click(viewport["width"] * 0.25, viewport["height"] * 0.55)
    page.keyboard.press("Control+A")
    # insert_text sends one edit, so editor auto-indent cannot alter the code.
    page.keyboard.insert_text(code)


def test_student_demo_runs_and_submits_an_assignment(page: Page):
    open_app(page)
    page.get_by_role("button", name="Try the student demo").click()

    starts = page.get_by_role("button", name="Start assignment")
    expect(starts.first).to_be_visible()
    # Student and instructor capabilities stay separate.
    expect(page.get_by_role("button", name="Instructor studio")).to_have_count(0)
    starts.first.click()

    # Run tests stays disabled until the assignment code is in the editor.
    run_tests = page.get_by_role("button", name="Run tests")
    expect(run_tests).to_be_enabled(timeout=60_000)
    run_tests.click()
    wait_for_text(page, "Keep refining your solution", GRADING_TIMEOUT_MS)
    wait_for_text(page, "Built-in tutor hint")

    minimize = page.get_by_role("button", name="Minimize results")
    minimize.click()
    expect(minimize).to_have_count(0)
    replace_editor_code(page, ASSIGNMENT_1_ANSWER.read_text(encoding="utf-8"))
    page.get_by_role("button", name="Run tests").click()
    wait_for_text(page, "All tests passed", GRADING_TIMEOUT_MS)

    # Demo work is memory-only: a refresh returns to the login page.
    page.reload()
    open_app(page)
    expect(page.get_by_role("button", name="Try the student demo")).to_be_visible()


def test_student_demo_tries_inputs_and_reads_failure_guidance(page: Page):
    open_app(page)
    page.get_by_role("button", name="Try the student demo").click()
    page.get_by_role("button", name="Start assignment").first.click()

    # The ungraded playground calls the starter function with chosen inputs.
    try_inputs = page.get_by_role("button", name="Try inputs")
    expect(try_inputs).to_be_enabled(timeout=60_000)
    try_inputs.click()
    wait_for_text(page, "not graded, not saved")
    # Each input has its own labelled box holding the instructions' example,
    # so one click runs it.
    wait_for_text(page, "starts with the example from the instructions")
    expect(page.get_by_label("Hit point")).to_be_visible()
    page.get_by_role("button", name="Run my function").click()
    wait_for_text(page, "Approach distance", GRADING_TIMEOUT_MS)
    wait_for_text(page, "Printed output")
    # The diagram draws the typed points and the values the function returned.
    wait_for_text(page, "Drawn to scale from your inputs")
    expect(
        page.get_by_role("img", name=re.compile(r"^Route diagram\. Points: S at \(2\.0, 1\.0\)"))
    ).to_have_count(1)
    page.get_by_role("button", name="Close").click()

    # Graded results name each check, its points, and why it failed.
    page.get_by_role("button", name="Run tests").click()
    wait_for_text(page, "Keep refining your solution", GRADING_TIMEOUT_MS)
    wait_for_text(page, "0 of 25 points")
    wait_for_text(page, "Wrong for every grading scenario")


def test_instructor_signs_in_reviews_studio_and_signs_out(page: Page):
    login = os.environ.get("E2E_INSTRUCTOR_LOGIN")
    password = os.environ.get("E2E_INSTRUCTOR_PASSWORD")
    if not (login and password):
        pytest.skip("Set E2E_INSTRUCTOR_LOGIN and E2E_INSTRUCTOR_PASSWORD to run.")

    open_app(page)
    type_into(page, "Login ID", login)
    type_into(page, "Password", password)
    page.keyboard.press("Enter")

    page.get_by_role("button", name="Instructor studio").click()
    expect(page.get_by_role("button", name="Create assignment")).to_be_visible()
    expect(page.get_by_role("button", name="Manage accounts")).to_be_visible()
    for assignment_number in range(1, 5):
        expect(
            page.get_by_role("button", name=f"Assignment {assignment_number}:")
        ).to_be_visible()

    page.get_by_role("button", name="Research study dashboard").click()
    expect(page.get_by_role("button", name="Export research data")).to_be_visible(
        timeout=60_000
    )
    wait_for_text(page, "attempts")

    # Dashboard -> studio -> home, where the account menu lives.
    page.get_by_role("button", name="Back").first.click()
    expect(page.get_by_role("button", name="Create assignment")).to_be_visible()
    page.get_by_role("button", name="Back").first.click()
    page.get_by_role("button", name="Account menu").click()
    page.get_by_role("menuitem", name="Sign out").click()
    expect(page.get_by_role("button", name="Sign in")).to_be_visible()
