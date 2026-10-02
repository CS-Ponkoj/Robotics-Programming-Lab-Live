import pytest


@pytest.hookimpl(wrapper=True)
def pytest_runtest_makereport(item, call):
    report = yield
    # Expose the call-phase result so the page fixture can save a screenshot.
    if report.when == "call":
        item.call_failed = report.failed
    return report
