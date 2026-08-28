#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./scripts/linux-local-common.sh
source "$SCRIPT_DIR/linux-local-common.sh"

repair="false"
if [[ "${1:-}" == "--repair" ]]; then
  repair="true"
  shift
fi
if [[ "$#" -ne 0 ]]; then
  printf 'Usage: %s [--repair]\n' "$0" >&2
  exit 2
fi

robotics_require_linux_x64
if robotics_any_managed_process_running; then
  printf 'Stop the local application before setup: ./scripts/stop-local.sh\n' >&2
  exit 1
fi
robotics_require_command uv 'Install uv from https://docs.astral.sh/uv/getting-started/installation/.'
robotics_require_command docker 'Install Docker Engine and the Docker Compose plugin.'
robotics_require_command flutter 'Install Flutter with Linux web support.'
robotics_require_command curl 'Install curl through apt or ask lab IT.'
robotics_require_command sha256sum 'Install GNU coreutils through apt or ask lab IT.'
robotics_require_command flock 'Install util-linux through apt or ask lab IT.'
robotics_require_command setsid 'Install util-linux through apt or ask lab IT.'

docker info >/dev/null
docker compose version >/dev/null
flutter --version >/dev/null

repository_root="$(robotics_repository_root)"
environment_root="$(robotics_environment_root)"
runtime_root="$(robotics_runtime_root)"
python="$environment_root/bin/python"
requirements="$repository_root/backend/requirements.txt"
signature_file="$environment_root/.environment.signature"
mkdir -p -- "$(dirname -- "$environment_root")" "$runtime_root"
robotics_assert_path_under "$environment_root" "$(robotics_data_root)/environments"

if [[ "$repair" == "true" ]]; then
  rm -rf -- "$environment_root"
fi
if [[ ! -x "$python" ]] || ! "$python" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 14) else 1)' 2>/dev/null; then
  printf 'Creating a device-local Python 3.14 environment...\n'
  rm -rf -- "$environment_root"
  uv venv --python 3.14 "$environment_root"
fi

requirements_hash="$(robotics_sha256 "$requirements")"
python_identity="$($python -c 'import platform,sys; print(f"{sys.executable}|{platform.python_version()}|{platform.machine()}")')"
desired_signature="$requirements_hash|$python_identity"
installed_signature=""
[[ -f "$signature_file" ]] && installed_signature="$(cat -- "$signature_file")"
if [[ "$desired_signature" != "$installed_signature" || "$repair" == "true" ]]; then
  printf 'Installing pinned backend dependencies...\n'
  if [[ "$repair" == "true" ]]; then
    uv pip install --python "$python" --upgrade --force-reinstall --no-cache -r "$requirements"
  else
    uv pip install --python "$python" -r "$requirements"
  fi
  printf '%s' "$desired_signature" > "$signature_file"
fi

"$python" -c 'import pydantic_core, _cffi_backend, numpy, scipy, psycopg'
printf 'Ubuntu local setup is ready.\n'
printf 'Python: %s\n' "$python"
"$python" --version
printf 'Database backup: %s\n' "$(robotics_handoff_root)"
printf 'Private config: %s/.env\n' "$(robotics_handoff_root)"
printf 'Start with: ./scripts/run-local.sh --frontend-port 8180 --backend-port 5100 --sandbox-port 5101\n'
