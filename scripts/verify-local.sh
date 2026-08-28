#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./scripts/linux-local-common.sh
source "$SCRIPT_DIR/linux-local-common.sh"

api_base_url="http://127.0.0.1:5000"
if [[ "${1:-}" == "--api-base-url" ]]; then
  api_base_url="$2"
  shift 2
fi
if [[ "$#" -ne 0 ]]; then
  printf 'Usage: %s [--api-base-url URL]\n' "$0" >&2
  exit 2
fi
robotics_require_linux_x64
python="$(robotics_python)"
[[ -x "$python" ]] || { printf 'Run ./scripts/setup-local.sh first.\n' >&2; exit 1; }

for script in "$SCRIPT_DIR"/*.sh; do
  bash -n "$script"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "$SCRIPT_DIR"/*.sh
else
  printf 'ShellCheck is not installed; Bash syntax passed, but linting is skipped.\n' >&2
fi

repository_root="$(robotics_repository_root)"
environment_root="$(robotics_environment_root)"
runtime_root="$(robotics_runtime_root)"
robotics_assert_path_under "$environment_root" "$(robotics_data_root)/environments"
robotics_assert_path_under "$runtime_root" "${XDG_STATE_HOME:-$HOME/.local/state}/RoboticsProgrammingLab/runtime"
[[ "$(realpath -m -- "$(robotics_handoff_root)")" == "$(realpath -m -- "$repository_root/local_handoff_package")" ]]

(
  cd -- "$repository_root/backend"
  "$python" -m pytest -p no:cacheprovider tests -q
  uv pip check --python "$python"
  PYTHONPYCACHEPREFIX="$runtime_root/python-cache" "$python" -m compileall -q .
)
"$SCRIPT_DIR/verify-linux-database-handoff.sh"

safe_frontend="$runtime_root/frontend-sqa"
robotics_assert_path_under "$safe_frontend" "$runtime_root"
rm -rf -- "$safe_frontend"
mkdir -p -- "$safe_frontend"
for directory in fonts lib test web; do
  cp -a -- "$repository_root/frontend/$directory" "$safe_frontend/$directory"
done
for file in .metadata analysis_options.yaml pubspec.lock pubspec.yaml; do
  cp -- "$repository_root/frontend/$file" "$safe_frontend/$file"
done
(
  cd -- "$safe_frontend"
  flutter pub get
  flutter analyze
  flutter test
  flutter build web --release "--dart-define=API_BASE_URL=$api_base_url"
)

if git -C "$repository_root" ls-files | grep -E \
  '(^|/)(\.env|env|venv|venvs|build|\.dart_tool|\.local-run)(/|$)|\.(db|sqlite|sqlite3|dump)$' >/dev/null; then
  printf 'A generated or secret-bearing path is tracked.\n' >&2
  exit 1
fi
git -C "$repository_root" diff --check

metadata_file="$runtime_root/managed.env"
if [[ -f "$metadata_file" ]]; then
  backend_url="$(awk -F= '$1=="backend_url" {print substr($0,index($0,"=")+1)}' "$metadata_file")"
  sandbox_url="$(awk -F= '$1=="sandbox_url" {print substr($0,index($0,"=")+1)}' "$metadata_file")"
  robotics_wait_for_http Backend "$backend_url/health" 10
  robotics_wait_for_http Sandbox "$sandbox_url/health" 10
fi
printf 'Complete Ubuntu local SQA verification passed.\n'
