#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

robotics_repository_root() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
}

robotics_project_key() {
  local root name
  root="$(robotics_repository_root)"
  name="$(basename -- "$root")"
  printf '%s\n' "${name//[^A-Za-z0-9._-]/-}"
}

robotics_data_root() {
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/RoboticsProgrammingLab"
}

robotics_runtime_root() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/RoboticsProgrammingLab/runtime/$(robotics_project_key)"
}

robotics_environment_root() {
  printf '%s\n' "$(robotics_data_root)/environments/$(robotics_project_key)/venv"
}

robotics_private_config() {
  printf '%s\n' "$(robotics_repository_root)/.env"
}

robotics_python() {
  printf '%s\n' "$(robotics_environment_root)/bin/python"
}

robotics_require_command() {
  local command_name="$1"
  local help_text="$2"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command is unavailable: %s. %s\n' "$command_name" "$help_text" >&2
    return 1
  fi
}

robotics_require_linux_x64() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    printf 'Ubuntu scripts require Linux. Use the PowerShell scripts on Windows.\n' >&2
    return 1
  fi
  if [[ "$(uname -m)" != "x86_64" ]]; then
    printf 'This first Ubuntu release supports x86_64 only; found %s.\n' "$(uname -m)" >&2
    return 1
  fi
}

robotics_process_start_time() {
  local pid="$1"
  awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || true
}

robotics_process_matches() {
  local pid="$1"
  local expected_start="$2"
  [[ -n "$pid" && -d "/proc/$pid" && "$(robotics_process_start_time "$pid")" == "$expected_start" ]]
}

robotics_any_managed_process_running() {
  local process_file
  process_file="$(robotics_runtime_root)/processes.tsv"
  [[ -f "$process_file" ]] || return 1
  while IFS=$'\t' read -r _name pid start_time; do
    if robotics_process_matches "$pid" "$start_time"; then
      return 0
    fi
  done < "$process_file"
  return 1
}

robotics_assert_path_under() {
  local target="$1"
  local parent="$2"
  local resolved_target resolved_parent
  resolved_target="$(realpath -m -- "$target")"
  resolved_parent="$(realpath -m -- "$parent")"
  case "$resolved_target" in
    "$resolved_parent"/*) ;;
    *)
      printf 'Refusing to modify a path outside %s: %s\n' "$resolved_parent" "$resolved_target" >&2
      return 1
      ;;
  esac
}

robotics_sha256() {
  sha256sum -- "$1" | awk '{print toupper($1)}'
}

robotics_wait_for_http() {
  local name="$1"
  local url="$2"
  local attempts="${3:-120}"
  local attempt
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --silent --show-error --max-time 2 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  printf '%s did not become ready at %s.\n' "$name" "$url" >&2
  return 1
}

robotics_port_available() {
  local port="$1"
  "$(robotics_python)" - "$port" <<'PY'
import socket
import sys

port = int(sys.argv[1])
with socket.socket() as sock:
    try:
        sock.bind(("127.0.0.1", port))
    except OSError:
        raise SystemExit(1)
PY
}
