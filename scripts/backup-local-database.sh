#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./scripts/linux-local-database.sh
source "$SCRIPT_DIR/linux-local-database.sh"

session_id=""
database_port="5432"
project_name="robotics-lab-local"
backup_root="$(robotics_handoff_root)"
runtime_root="$(robotics_runtime_root)"
interval_minutes="10"
run_once="false"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --session-id) session_id="$2"; shift 2 ;;
    --database-port) database_port="$2"; shift 2 ;;
    --project-name) project_name="$2"; shift 2 ;;
    --backup-root) backup_root="$2"; shift 2 ;;
    --runtime-root) runtime_root="$2"; shift 2 ;;
    --interval-minutes) interval_minutes="$2"; shift 2 ;;
    --run-once) run_once="true"; shift ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ -n "$session_id" ]] || { printf '%s\n' '--session-id is required.' >&2; exit 2; }
[[ "$interval_minutes" =~ ^[0-9]+$ && "$interval_minutes" -ge 1 && "$interval_minutes" -le 1440 ]] || {
  printf '%s\n' '--interval-minutes must be between 1 and 1440.' >&2
  exit 2
}

save_current_database() {
  local result
  result="$(robotics_save_postgres_backup "$session_id" "$project_name" "$database_port" "$backup_root" "$runtime_root" true)"
  if [[ "$result" == "unchanged" ]]; then
    printf '[%s] Database unchanged; automatic backup skipped.\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  else
    printf '[%s] Verified automatic PostgreSQL backup saved.\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  fi
}

save_current_database
[[ "$run_once" == "true" ]] && exit 0
while true; do
  sleep "$((interval_minutes * 60))"
  save_current_database || printf '[%s] Automatic PostgreSQL backup failed; the previous backup was preserved.\n' \
    "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >&2
done
