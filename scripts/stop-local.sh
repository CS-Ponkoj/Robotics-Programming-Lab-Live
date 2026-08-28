#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./scripts/linux-local-database.sh
source "$SCRIPT_DIR/linux-local-database.sh"

runtime_root="$(robotics_runtime_root)"
process_file="$runtime_root/processes.tsv"
metadata_file="$runtime_root/managed.env"
if [[ ! -f "$process_file" && ! -f "$metadata_file" ]]; then
  printf 'No managed local Robotics Programming Lab processes are recorded.\n'
  exit 0
fi

stop_named_process() {
  local target_name="$1"
  local name pid start_time
  [[ -f "$process_file" ]] || return 0
  while IFS=$'\t' read -r name pid start_time; do
    [[ "$name" == "$target_name" ]] || continue
    if robotics_process_matches "$pid" "$start_time"; then
      kill -- "-$pid" 2>/dev/null || true
      for _attempt in {1..50}; do
        robotics_process_matches "$pid" "$start_time" || break
        sleep 0.1
      done
      if robotics_process_matches "$pid" "$start_time"; then
        kill -KILL -- "-$pid" 2>/dev/null || true
      fi
      printf 'Stopped %s process %s.\n' "$name" "$pid"
    fi
  done < "$process_file"
}

stop_named_process database-backup
stop_named_process frontend
stop_named_process sandbox
stop_named_process backend

if [[ -f "$metadata_file" ]]; then
  managed_database="$(awk -F= '$1=="managed_database" {print substr($0,index($0,"=")+1)}' "$metadata_file")"
  if [[ "$managed_database" == "true" ]]; then
    database_session_id="$(awk -F= '$1=="database_session_id" {print substr($0,index($0,"=")+1)}' "$metadata_file")"
    database_project="$(awk -F= '$1=="database_project" {print substr($0,index($0,"=")+1)}' "$metadata_file")"
    database_port="$(awk -F= '$1=="database_port" {print substr($0,index($0,"=")+1)}' "$metadata_file")"
    backup_root="$(awk -F= '$1=="backup_root" {print substr($0,index($0,"=")+1)}' "$metadata_file")"
    recorded_runtime="$(awk -F= '$1=="runtime_root" {print substr($0,index($0,"=")+1)}' "$metadata_file")"
    robotics_complete_local_postgres "$database_session_id" "$database_project" "$database_port" "$backup_root" "$recorded_runtime"
  fi
fi
rm -f -- "$process_file" "$metadata_file"
printf 'Local Robotics Programming Lab services are stopped.\n'
