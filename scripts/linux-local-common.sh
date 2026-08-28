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

robotics_handoff_root() {
  printf '%s\n' "$(robotics_repository_root)/local_handoff_package"
}

robotics_python() {
  printf '%s\n' "$(robotics_environment_root)/bin/python"
}

robotics_device_name() {
  if [[ -n "${ROBOTICS_DEVICE_NAME:-}" ]]; then
    printf '%s\n' "$ROBOTICS_DEVICE_NAME"
  else
    hostname
  fi
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

robotics_json_field() {
  local path="$1"
  local field="$2"
  local default_value="${3:-}"
  local python
  python="$(robotics_python)"
  if [[ ! -f "$path" ]]; then
    printf '%s\n' "$default_value"
    return 0
  fi
  "$python" - "$path" "$field" "$default_value" <<'PY'
import json
import sys

path, field, default = sys.argv[1:]
with open(path, encoding="utf-8-sig") as stream:
    value = json.load(stream)
for part in field.split("."):
    if not isinstance(value, dict) or part not in value:
        value = default
        break
    value = value[part]
if value is None:
    value = default
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

robotics_write_json_atomic() {
  local destination="$1"
  local json_payload="$2"
  local python
  python="$(robotics_python)"
  mkdir -p -- "$(dirname -- "$destination")"
  "$python" - "$destination" "$json_payload" <<'PY'
import json
import os
import sys
import tempfile

destination, payload = sys.argv[1:]
parent = os.path.dirname(destination)
value = json.loads(payload)
fd, temporary = tempfile.mkstemp(prefix=os.path.basename(destination) + ".", suffix=".tmp", dir=parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")
    os.replace(temporary, destination)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PY
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
