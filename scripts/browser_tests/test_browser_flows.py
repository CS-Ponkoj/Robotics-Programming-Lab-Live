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

FRONTEND_URL = os.environ.get("E2E_FRONTEND_URL", "http://127.0.0.1:8180").rstrip("/")
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
    # Each input has its own labelled box, starting from the instructions'
    # example, so one click runs it; presets offer edge cases to explore.
    wait_for_text(page, "Pick a case to explore")
    expect(page.get_by_label("Hit point")).to_be_visible()
    page.get_by_role("button", name="Run my function").click()
    wait_for_text(page, "Approach distance", GRADING_TIMEOUT_MS)
    wait_for_text(page, "Printed output")
    # The diagram draws the typed points and the values the function returned.
    wait_for_text(page, "Drawn to scale from your inputs")
    expect(
        page.get_by_role("img", name=re.compile(r"^Route diagram\. Points: S at \(2\.0, 1\.0\)"))
    ).to_have_count(1)
    # A preset fills every field; a second run lets the student compare runs.
    page.get_by_role("button", name=re.compile("Start from|Instructions example")).first.click()
    page.get_by_role("menuitem", name="Hit right after start").click()
    page.get_by_role("button", name="Run my function").click()
    wait_for_text(page, "Compare your last runs", GRADING_TIMEOUT_MS)
    wait_for_text(page, "Latest: Hit right after start")
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


# --- Persistent student drafts -------------------------------------------
# A real student's half-finished code must come back however they leave.
# These checks sign in with E2E_STUDENT_LOGIN / E2E_STUDENT_PASSWORD and
# save draft rows for that account, so they are skipped unless both are set.
# Use a dedicated test student, never a research participant.

ASSIGNMENT_BUTTON = re.compile(r"^(Start|Continue|Review) assignment$")
DRAFT_WAIT_MS = 30_000


def student_credentials() -> tuple[str, str]:
    login = os.environ.get("E2E_STUDENT_LOGIN")
    password = os.environ.get("E2E_STUDENT_PASSWORD")
    if not (login and password):
        pytest.skip("Set E2E_STUDENT_LOGIN and E2E_STUDENT_PASSWORD to run.")
    return login, password


def new_page(browser):
    """A fresh browser profile: what a student sees on another computer."""
    context = browser.new_context(viewport={"width": 1280, "height": 800})
    opened = context.new_page()
    opened.set_default_timeout(30_000)
    return context, opened


def sign_in(page: Page, login: str, password: str) -> None:
    open_app(page)
    type_into(page, "Login ID", login)
    type_into(page, "Password", password)
    page.keyboard.press("Enter")
    expect(page.get_by_role("button", name=ASSIGNMENT_BUTTON).first).to_be_visible(
        timeout=60_000
    )


def open_first_assignment(page: Page) -> None:
    page.get_by_role("button", name=ASSIGNMENT_BUTTON).first.click()
    expect(page.get_by_role("button", name="Run tests")).to_be_enabled(timeout=60_000)


def editor_shows(page: Page, marker: str, timeout: int = DRAFT_WAIT_MS) -> bool:
    """Whether the code editor's text contains marker within timeout."""
    # Flutter publishes the editor text to the accessibility tree once the
    # editor has focus; clicking only places the cursor.
    page.wait_for_timeout(500)
    viewport = page.viewport_size
    page.mouse.click(viewport["width"] * 0.25, viewport["height"] * 0.55)
    host = page.locator("flt-semantics-host")
    for _ in range(timeout // 500):
        if marker in host.aria_snapshot():
            return True
        page.wait_for_timeout(500)
    return marker in host.aria_snapshot()


CARD_STATUS = re.compile(r"\b01 .*?\b(Completed|Attempted|In progress|Not started)\b")


def first_card_status(page: Page) -> str:
    """The progress label on the first assignment card of the home page."""
    expect(page.get_by_role("button", name=ASSIGNMENT_BUTTON).first).to_be_visible(
        timeout=60_000
    )
    page.wait_for_timeout(1_000)
    match = CARD_STATUS.search(page.locator("flt-semantics-host").aria_snapshot())
    assert match, "first assignment card has no progress label"
    return match.group(1)


def device_copy_has(page: Page, marker: str, timeout: int = 10_000) -> bool:
    """Whether this browser's saved draft copy contains marker.

    The editor writes this copy on every change, before any server save, so
    it is the reliable sign that typing reached the app.
    """
    script = (
        "m => Object.entries(window.localStorage)"
        ".some(([key, value]) => key.includes('code_drafts') && value.includes(m))"
    )
    for _ in range(timeout // 250):
        if page.evaluate(script, marker):
            return True
        page.wait_for_timeout(250)
    return bool(page.evaluate(script, marker))


def write_code(page: Page, marker: str) -> None:
    # Let the editor finish loading the saved draft, and take focus, before
    # typing over it; Flutter applies typed text a moment after the browser.
    page.wait_for_timeout(1_000)
    viewport = page.viewport_size
    # Synthetic typing occasionally arrives before Flutter's hidden text field
    # has focus and is dropped; a person's keystrokes are not. Retry until the
    # app has the text, then the checks below test what matters: whether it
    # comes back.
    for _ in range(3):
        page.mouse.click(viewport["width"] * 0.25, viewport["height"] * 0.55)
        page.wait_for_timeout(300)
        replace_editor_code(page, f"# {marker}\nanswer = 1\n")
        if device_copy_has(page, marker, timeout=3_000):
            return
    raise AssertionError("typing did not reach the editor")


def test_student_code_comes_back_however_they_leave(browser):
    login, password = student_credentials()
    stamp = str(os.getpid()) + str(abs(hash(FRONTEND_URL)) % 10_000)

    # 1. Back to the home page and reopen.
    context, page = new_page(browser)
    sign_in(page, login, password)
    open_first_assignment(page)
    first = f"DRAFT-HOME-{stamp}"
    write_code(page, first)
    page.wait_for_timeout(2_000)
    page.get_by_role("button", name="Back").first.click()
    open_first_assignment(page)
    assert editor_shows(page, first), "draft lost after going back home"

    # 2. Browser refresh inside the app keeps the session and the code.
    page.reload()
    placeholder = page.locator("flt-semantics-placeholder")
    placeholder.wait_for(state="attached", timeout=60_000)
    placeholder.dispatch_event("click")
    expect(page.get_by_role("button", name=ASSIGNMENT_BUTTON).first).to_be_visible(
        timeout=60_000
    )
    open_first_assignment(page)
    assert editor_shows(page, first), "draft lost after a browser refresh"

    # 3. Sign out and back in.
    page.get_by_role("button", name="Back").first.click()
    page.get_by_role("button", name="Account menu").click()
    page.get_by_role("menuitem", name="Sign out").click()
    expect(page.get_by_role("button", name="Sign in")).to_be_visible()
    type_into(page, "Login ID", login)
    type_into(page, "Password", password)
    page.keyboard.press("Enter")
    open_first_assignment(page)
    assert editor_shows(page, first), "draft lost after signing out and in"
    page.get_by_role("button", name="Back").first.click()
    status_here = first_card_status(page)
    context.close()

    # 4. Another computer: only the server copy can supply the code, and the
    # home page shows the same status as the student's usual browser (the
    # server restores attempts and scores, so it is not always "In progress").
    other, page = new_page(browser)
    sign_in(page, login, password)
    assert first_card_status(page) == status_here, "status differs on another computer"
    open_first_assignment(page)
    assert editor_shows(page, first), "draft missing on another computer"
    other.close()


def test_student_code_survives_a_closed_tab_and_a_lost_connection(browser):
    login, password = student_credentials()
    stamp = str(os.getpid())

    # 5. Close the tab before the server save happens. Blocking draft saves
    # makes that certain, instead of racing the short save delay.
    context, page = new_page(browser)
    sign_in(page, login, password)
    open_first_assignment(page)
    page.route(
        re.compile(r".*/assignments/\d+/draft$"),
        lambda route: route.abort()
        if route.request.method == "PUT"
        else route.continue_(),
    )
    closed = f"DRAFT-CLOSED-TAB-{stamp}"
    write_code(page, closed)
    page.close()
    page = context.new_page()
    page.set_default_timeout(30_000)
    sign_in(page, login, password)
    open_first_assignment(page)
    assert editor_shows(page, closed), "draft lost when the tab closed at once"

    # 6. Lose the connection while typing, then come back online.
    offline = f"DRAFT-OFFLINE-{stamp}"
    context.set_offline(True)
    write_code(page, offline)
    page.wait_for_timeout(2_000)
    context.set_offline(False)
    page.close()
    page = context.new_page()
    page.set_default_timeout(30_000)
    sign_in(page, login, password)
    open_first_assignment(page)
    assert editor_shows(page, offline), "draft lost after the connection dropped"
    page.wait_for_timeout(2_000)
    context.close()

    # Reopening on this computer sent the offline code to the server, so
    # another computer sees it too.
    other, page = new_page(browser)
    sign_in(page, login, password)
    open_first_assignment(page)
    assert editor_shows(page, offline), "offline draft never reached the server"
    other.close()


def terminal_shows(page: Page, text: str, timeout: int = 30_000) -> None:
    """Wait until a terminal line containing text is in the accessibility tree."""
    host = page.locator("flt-semantics-host")
    for _ in range(timeout // 500):
        if text in host.aria_snapshot():
            return
        page.wait_for_timeout(500)
    assert text in host.aria_snapshot(), f"terminal never showed {text!r}"


def test_terminal_under_the_editor_shows_output_and_errors(page: Page):
    open_app(page)
    page.get_by_role("button", name="Try the student demo").click()
    page.get_by_role("button", name="Start assignment").first.click()
    run_tests = page.get_by_role("button", name="Run tests")
    expect(run_tests).to_be_enabled(timeout=60_000)
    # Like the VS Code panel, the terminal is open under the editor from the
    # start and says what it will show.
    expect(page.get_by_role("button", name="Collapse terminal")).to_be_visible()
    terminal_shows(page, "Run tests to see what your program prints")

    # A normal run: the command, what print() wrote, and the test summary.
    run_tests.click()
    # Results open over the page; minimizing them shows the terminal.
    minimize = page.get_by_role("button", name="Minimize results")
    expect(minimize).to_be_visible(timeout=GRADING_TIMEOUT_MS)
    wait_for_text(page, "Test score", GRADING_TIMEOUT_MS)
    minimize.click()
    terminal_shows(page, "Tests finished:")
    terminal_shows(page, "$ python")
    terminal_shows(page, "Total travel distance:")

    # An error: the printed line before it, the student's own failing line,
    # and the error message, like a VS Code terminal.
    broken = (
        "print('before the error')\n"
        "def calculate_bug2_route(start, hit, corner, leave, goal):\n"
        "    return missing_name\n"
        "calculate_bug2_route(1, 2, 3, 4, 5)\n"
    )
    # Demo drafts are memory-only, so confirm the typing from the editor
    # itself, retrying if a synthetic keystroke arrives before focus.
    viewport = page.viewport_size
    for _ in range(3):
        page.wait_for_timeout(500)
        page.mouse.click(viewport["width"] * 0.25, viewport["height"] * 0.45)
        page.wait_for_timeout(300)
        replace_editor_code(page, broken)
        if editor_shows(page, "return missing_name", timeout=3_000):
            break
    else:
        raise AssertionError("typing did not reach the editor")
    page.get_by_role("button", name="Run tests").click()
    expect(minimize).to_be_visible(timeout=GRADING_TIMEOUT_MS)
    wait_for_text(page, "resolve the execution error", GRADING_TIMEOUT_MS)
    minimize.click()
    terminal_shows(page, "Traceback (most recent call last):")
    terminal_shows(page, "line 4, in <module>")
    terminal_shows(page, "calculate_bug2_route(1, 2, 3, 4, 5)")
    terminal_shows(page, "line 3, in calculate_bug2_route")
    terminal_shows(page, "NameError: name 'missing_name' is not defined")
    terminal_shows(page, "before the error")
    terminal_shows(page, "return missing_name")
    go_to_line = page.get_by_role("button", name=re.compile(r"^Go to line 3 in the editor"))
    expect(go_to_line).to_have_count(1)
    go_to_line.click()
    terminal_shows(page, "Tests did not finish")

    # A bug only a grading test reaches: the traceback still walks the
    # student's own lines, while the test input stays hidden.
    inner = (
        "def calculate_bug2_route(start, hit, corner, leave, goal):\n"
        "    distance = missing_name\n"
        "    return distance\n"
    )
    for _ in range(3):
        page.wait_for_timeout(500)
        page.mouse.click(viewport["width"] * 0.25, viewport["height"] * 0.45)
        page.wait_for_timeout(300)
        replace_editor_code(page, inner)
        if editor_shows(page, "distance = missing_name", timeout=3_000):
            break
    else:
        raise AssertionError("typing did not reach the editor")
    page.get_by_role("button", name="Run tests").click()
    expect(minimize).to_be_visible(timeout=GRADING_TIMEOUT_MS)
    wait_for_text(page, "Test score", GRADING_TIMEOUT_MS)
    minimize.click()
    terminal_shows(page, "A grading test called your function")
    terminal_shows(page, "line 2, in calculate_bug2_route")
    terminal_shows(page, "NameError: name 'missing_name' is not defined")
    expect(
        page.get_by_role("button", name=re.compile(r"^Go to line 2 in the editor"))
    ).to_have_count(1)
    if os.environ.get("E2E_SCREENSHOT"):
        page.screenshot(path=os.environ["E2E_SCREENSHOT"])
