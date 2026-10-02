#!/usr/bin/env bash
# Run the end-to-end browser checks against the stack started by run-local.sh.
# Playwright lives in its own environment so the application's pinned Python
# environment is unchanged.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./scripts/linux-local-common.sh
source "$SCRIPT_DIR/linux-local-common.sh"

frontend_url=""
instructor_login=""
headed=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --frontend-url) frontend_url="$2"; shift 2 ;;
    --instructor-login) instructor_login="$2"; shift 2 ;;
    --headed) headed="1"; shift ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

python="$(robotics_python)"
if [[ -z "$frontend_url" ]]; then
  metadata_file="$(robotics_runtime_root)/managed.env"
  [[ -f "$metadata_file" ]] || {
    printf 'The local application is not running. Start it with ./scripts/run-local.sh first.\n' >&2
    exit 1
  }
  frontend_url="$(sed -n 's/^frontend_url=//p' "$metadata_file")"
fi

environment_root="$(dirname -- "$(robotics_environment_root)")/browser-tests-venv"
if [[ ! -x "$environment_root/bin/python" ]]; then
  "$python" -m venv "$environment_root"
fi
"$environment_root/bin/python" -m pip install --quiet --disable-pip-version-check \
  -r "$SCRIPT_DIR/requirements-browser-tests.txt"
# Ubuntu has no Google Chrome by default; use Playwright's bundled Chromium.
# This is a no-op once downloaded. A fresh machine may also need the system
# libraries from: sudo "$environment_root/bin/python" -m playwright install-deps chromium
"$environment_root/bin/python" -m playwright install chromium

if [[ -n "$instructor_login" && -z "${E2E_INSTRUCTOR_PASSWORD:-}" ]]; then
  [[ -t 0 ]] || {
    printf 'Set E2E_INSTRUCTOR_PASSWORD when running without a terminal.\n' >&2
    exit 1
  }
  read -r -s -p "Password for instructor test account '$instructor_login': " E2E_INSTRUCTOR_PASSWORD
  printf '\n'
  export E2E_INSTRUCTOR_PASSWORD
fi

E2E_FRONTEND_URL="$frontend_url" E2E_HEADED="$headed" \
  E2E_INSTRUCTOR_LOGIN="$instructor_login" E2E_BROWSER_CHANNEL=chromium \
  "$environment_root/bin/python" -m pytest -p no:cacheprovider "$SCRIPT_DIR/browser_tests" -v
