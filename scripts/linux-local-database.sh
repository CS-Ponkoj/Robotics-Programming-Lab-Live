#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=./scripts/linux-local-common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/linux-local-common.sh"

ROBOTICS_DB_NAME="robotics_lab"
ROBOTICS_DB_USER="robotics"
ROBOTICS_DB_PASSWORD="${ROBOTICS_LOCAL_DB_PASSWORD:-robotics-local-only}"

robotics_compose() {
  local project_name="$1"
  local database_port="$2"
  shift 2
  LOCAL_POSTGRES_DB="$ROBOTICS_DB_NAME" \
  LOCAL_POSTGRES_USER="$ROBOTICS_DB_USER" \
  LOCAL_POSTGRES_PASSWORD="$ROBOTICS_DB_PASSWORD" \
  LOCAL_POSTGRES_PORT="$database_port" \
    docker compose \
      --project-name "$project_name" \
      --file "$(robotics_repository_root)/docker-compose.yml" \
      "$@"
}

robotics_wait_for_postgres() {
  local project_name="$1"
  local database_port="$2"
  local attempt
  for ((attempt = 1; attempt <= 120; attempt++)); do
    if robotics_compose "$project_name" "$database_port" exec -T postgres \
      pg_isready -U "$ROBOTICS_DB_USER" -d "$ROBOTICS_DB_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  printf 'Local PostgreSQL did not become healthy. Review Docker logs.\n' >&2
  return 1
}

robotics_postgres_schema_present() {
  local project_name="$1"
  local database_port="$2"
  local result
  result="$(robotics_compose "$project_name" "$database_port" exec -T postgres \
    psql -U "$ROBOTICS_DB_USER" -d "$ROBOTICS_DB_NAME" -At -c \
    "SELECT CASE WHEN to_regclass('public.alembic_version') IS NOT NULL AND to_regclass('public.users') IS NOT NULL THEN 'present' ELSE 'missing' END;" \
    | tail -n 1 | tr -d '\r')"
  [[ "$result" == "present" ]]
}

robotics_export_postgres_dump() {
  local project_name="$1"
  local database_port="$2"
  local destination="$3"
  local container_dump
  container_dump="/tmp/robotics-lab-$(< /proc/sys/kernel/random/uuid).dump"
  mkdir -p -- "$(dirname -- "$destination")"
  robotics_compose "$project_name" "$database_port" exec -T postgres \
    pg_dump -U "$ROBOTICS_DB_USER" -d "$ROBOTICS_DB_NAME" \
      --format=custom --no-owner --no-privileges --file="$container_dump" >/dev/null
  robotics_compose "$project_name" "$database_port" exec -T postgres \
    pg_restore --list "$container_dump" >/dev/null
  robotics_compose "$project_name" "$database_port" cp \
    "postgres:$container_dump" "$destination" >/dev/null
  robotics_compose "$project_name" "$database_port" exec -T postgres \
    rm -f "$container_dump" >/dev/null || true
  [[ -s "$destination" ]] || {
    printf 'PostgreSQL created an empty or missing backup file.\n' >&2
    return 1
  }
}

robotics_reset_postgres_database() {
  local project_name="$1"
  local database_port="$2"
  robotics_compose "$project_name" "$database_port" exec -T postgres \
    psql -U "$ROBOTICS_DB_USER" -d postgres -v ON_ERROR_STOP=1 -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$ROBOTICS_DB_NAME' AND pid <> pg_backend_pid();" >/dev/null
  robotics_compose "$project_name" "$database_port" exec -T postgres \
    dropdb -U "$ROBOTICS_DB_USER" --if-exists "$ROBOTICS_DB_NAME" >/dev/null
  robotics_compose "$project_name" "$database_port" exec -T postgres \
    createdb -U "$ROBOTICS_DB_USER" "$ROBOTICS_DB_NAME" >/dev/null
}

robotics_restore_postgres_dump() {
  local project_name="$1"
  local database_port="$2"
  local source_dump="$3"
  local runtime_root="$4"
  local container_dump recovery_dump recovery_container
  container_dump="/tmp/robotics-lab-restore-$(< /proc/sys/kernel/random/uuid).dump"
  recovery_dump="$runtime_root/database-pre-restore.dump"
  recovery_container="/tmp/robotics-lab-recovery-$(< /proc/sys/kernel/random/uuid).dump"

  robotics_export_postgres_dump "$project_name" "$database_port" "$recovery_dump"
  robotics_compose "$project_name" "$database_port" cp "$source_dump" "postgres:$container_dump" >/dev/null
  robotics_compose "$project_name" "$database_port" exec -T postgres pg_restore --list "$container_dump" >/dev/null
  robotics_reset_postgres_database "$project_name" "$database_port"
  if ! robotics_compose "$project_name" "$database_port" exec -T postgres \
    pg_restore --exit-on-error --no-owner --no-privileges \
      -U "$ROBOTICS_DB_USER" -d "$ROBOTICS_DB_NAME" "$container_dump" >/dev/null; then
    printf 'Synchronized restore failed; recovering the previous local database.\n' >&2
    robotics_reset_postgres_database "$project_name" "$database_port"
    robotics_compose "$project_name" "$database_port" cp "$recovery_dump" "postgres:$recovery_container" >/dev/null
    robotics_compose "$project_name" "$database_port" exec -T postgres \
      pg_restore --exit-on-error --no-owner --no-privileges \
        -U "$ROBOTICS_DB_USER" -d "$ROBOTICS_DB_NAME" "$recovery_container" >/dev/null
    robotics_compose "$project_name" "$database_port" exec -T postgres \
      rm -f "$container_dump" "$recovery_container" >/dev/null || true
    return 1
  fi
  robotics_compose "$project_name" "$database_port" exec -T postgres rm -f "$container_dump" >/dev/null || true
}

robotics_validate_session_lock() {
  local backup_root="$1"
  local session_id="$2"
  local lock_path="$backup_root/active-device.json"
  local lock_device lock_session
  [[ -f "$lock_path" ]] || {
    printf 'The local database device lock is missing. Backup files were not changed.\n' >&2
    return 1
  }
  lock_device="$(robotics_json_field "$lock_path" device)"
  lock_session="$(robotics_json_field "$lock_path" session_id)"
  if [[ "$lock_device" != "$(robotics_device_name)" || "$lock_session" != "$session_id" ]]; then
    printf 'The local database lock does not belong to this application session.\n' >&2
    return 1
  fi
}

robotics_postgres_change_position() {
  local project_name="$1"
  local database_port="$2"
  robotics_compose "$project_name" "$database_port" exec -T postgres \
    psql -U "$ROBOTICS_DB_USER" -d "$ROBOTICS_DB_NAME" -At -c \
    "SELECT system_identifier::text || '|' || pg_current_wal_lsn()::text FROM pg_control_system();" \
    | tail -n 1 | tr -d '\r'
}

robotics_save_postgres_backup() {
  local session_id="$1"
  local project_name="$2"
  local database_port="$3"
  local backup_root="$4"
  local runtime_root="$5"
  local skip_if_unchanged="${6:-false}"
  local lock_file="$runtime_root/database-backup.lock"
  mkdir -p -- "$backup_root" "$runtime_root"
  exec 9>"$lock_file"
  flock -w 30 9 || {
    printf 'Another database backup is still running.\n' >&2
    return 1
  }
  robotics_validate_session_lock "$backup_root" "$session_id"
  robotics_wait_for_postgres "$project_name" "$database_port"

  local change_position system_identifier wal_lsn auto_state
  change_position="$(robotics_postgres_change_position "$project_name" "$database_port")"
  system_identifier="${change_position%%|*}"
  wal_lsn="${change_position#*|}"
  [[ -n "$system_identifier" && -n "$wal_lsn" && "$system_identifier" != "$change_position" ]] || {
    printf 'PostgreSQL did not return a valid change position.\n' >&2
    return 1
  }
  auto_state="$runtime_root/database-auto-backup.json"
  if [[ "$skip_if_unchanged" == "true" && -f "$auto_state" ]]; then
    if [[ "$(robotics_json_field "$auto_state" system_identifier)" == "$system_identifier" && \
          "$(robotics_json_field "$auto_state" wal_lsn)" == "$wal_lsn" ]]; then
      printf 'unchanged\n'
      return 0
    fi
  fi

  local temporary_dump incoming_dump latest_dump latest_manifest
  local previous_dump previous_manifest hash size schema_version now
  temporary_dump="$runtime_root/database-backup-$(< /proc/sys/kernel/random/uuid).dump"
  incoming_dump="$backup_root/latest.dump.incoming"
  latest_dump="$backup_root/latest.dump"
  latest_manifest="$backup_root/latest.json"
  previous_dump="$backup_root/previous.dump"
  previous_manifest="$backup_root/previous.json"
  trap 'rm -f -- "$temporary_dump" "$incoming_dump"' RETURN

  robotics_export_postgres_dump "$project_name" "$database_port" "$temporary_dump"
  hash="$(robotics_sha256 "$temporary_dump")"
  size="$(stat -c '%s' "$temporary_dump")"
  schema_version="$(robotics_compose "$project_name" "$database_port" exec -T postgres \
    psql -U "$ROBOTICS_DB_USER" -d "$ROBOTICS_DB_NAME" -At -c \
    'SELECT version_num FROM alembic_version LIMIT 1;' | tail -n 1 | tr -d '\r')"
  cp -- "$temporary_dump" "$incoming_dump"
  [[ "$(robotics_sha256 "$incoming_dump")" == "$hash" ]] || {
    printf 'Database backup copy verification failed.\n' >&2
    return 1
  }
  [[ -f "$latest_dump" ]] && cp -- "$latest_dump" "$previous_dump"
  [[ -f "$latest_manifest" ]] && cp -- "$latest_manifest" "$previous_manifest"
  mv -f -- "$incoming_dump" "$latest_dump"
  now="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  robotics_write_json_atomic "$latest_manifest" "$(printf \
    '{\"format\":\"postgresql-custom-dump\",\"created_at_utc\":\"%s\",\"source_device\":\"%s\",\"database\":\"%s\",\"alembic_version\":\"%s\",\"bytes\":%s,\"sha256\":\"%s\",\"system_identifier\":\"%s\",\"wal_lsn\":\"%s\"}' \
    "$now" "$(robotics_device_name)" "$ROBOTICS_DB_NAME" "$schema_version" "$size" "$hash" "$system_identifier" "$wal_lsn")"
  robotics_write_json_atomic "$auto_state" "$(printf \
    '{\"system_identifier\":\"%s\",\"wal_lsn\":\"%s\",\"last_backup_sha256\":\"%s\",\"updated_at_utc\":\"%s\"}' \
    "$system_identifier" "$wal_lsn" "$hash" "$now")"
  robotics_write_json_atomic "$runtime_root/database-sync.json" "$(printf \
    '{\"device\":\"%s\",\"dirty\":true,\"last_backup_sha256\":\"%s\",\"session_id\":\"%s\",\"updated_at_utc\":\"%s\"}' \
    "$(robotics_device_name)" "$hash" "$session_id" "$now")"
  rm -f -- "$temporary_dump"
  trap - RETURN
  printf 'saved|%s|%s\n' "$latest_dump" "$hash"
}

robotics_start_local_postgres() {
  local database_port="$1"
  local project_name="${2:-robotics-lab-local}"
  local backup_root="${3:-$(robotics_handoff_root)}"
  local runtime_root="${4:-$(robotics_runtime_root)}"
  local lock_path="$backup_root/active-device.json"
  local session_id existing_device latest_dump latest_manifest latest_hash last_hash dirty schema_present restored
  local lock_acquired="false"

  # shellcheck disable=SC2317,SC2329  # Invoked by the RETURN trap below.
  cleanup_failed_database_start() {
    if [[ "$lock_acquired" == "true" ]]; then
      rm -f -- "$lock_path"
      robotics_compose "$project_name" "$database_port" stop postgres >/dev/null 2>&1 || true
    fi
  }
  trap cleanup_failed_database_start RETURN

  robotics_require_command docker 'Install Docker Engine and the Compose plugin.'
  docker info >/dev/null
  mkdir -p -- "$backup_root" "$runtime_root"
  latest_dump="$backup_root/latest.dump"
  latest_manifest="$backup_root/latest.json"
  if { [[ -f "$latest_dump" ]] && [[ ! -f "$latest_manifest" ]]; } ||
     { [[ ! -f "$latest_dump" ]] && [[ -f "$latest_manifest" ]]; }; then
    printf 'The handoff package is incomplete; latest.dump and latest.json are both required.\n' >&2
    return 1
  fi
  latest_hash=""
  if [[ -f "$latest_manifest" ]]; then
    latest_hash="$(robotics_sha256 "$latest_dump")"
    [[ "$latest_hash" == "$(robotics_json_field "$latest_manifest" sha256)" ]] || {
      printf 'The database backup checksum does not match its manifest.\n' >&2
      return 1
    }
  fi
  if [[ -f "$lock_path" ]]; then
    existing_device="$(robotics_json_field "$lock_path" device)"
    if [[ "$existing_device" != "$(robotics_device_name)" ]]; then
      printf "The database is assigned to '%s'. Stop it there and finish the handoff first.\n" "$existing_device" >&2
      return 1
    fi
  fi
  session_id="$(tr -d '-' < /proc/sys/kernel/random/uuid)"
  robotics_write_json_atomic "$lock_path" "$(printf \
    '{\"device\":\"%s\",\"session_id\":\"%s\",\"acquired_at_utc\":\"%s\",\"repository\":\"%s\"}' \
    "$(robotics_device_name)" "$session_id" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$(robotics_repository_root)")"
  lock_acquired="true"

  if ! robotics_compose "$project_name" "$database_port" up -d postgres >/dev/null; then
    rm -f -- "$lock_path"
    return 1
  fi
  robotics_wait_for_postgres "$project_name" "$database_port"
  restored="false"
  if [[ -f "$latest_manifest" ]]; then
    last_hash="$(robotics_json_field "$runtime_root/database-sync.json" last_backup_sha256)"
    dirty="$(robotics_json_field "$runtime_root/database-sync.json" dirty false)"
    if [[ "$dirty" == "true" && -n "$last_hash" && "$last_hash" != "$latest_hash" ]]; then
      printf 'This computer has unexported changes while the package contains a different backup.\n' >&2
      return 1
    fi
    schema_present="false"
    robotics_postgres_schema_present "$project_name" "$database_port" && schema_present="true"
    if [[ "$last_hash" != "$latest_hash" || "$schema_present" != "true" ]]; then
      robotics_restore_postgres_dump "$project_name" "$database_port" "$latest_dump" "$runtime_root"
      restored="true"
    fi
  fi
  robotics_write_json_atomic "$runtime_root/database-sync.json" "$(printf \
    '{\"device\":\"%s\",\"dirty\":true,\"last_backup_sha256\":\"%s\",\"session_id\":\"%s\",\"updated_at_utc\":\"%s\"}' \
    "$(robotics_device_name)" "$latest_hash" "$session_id" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')")"
  lock_acquired="false"
  trap - RETURN
  printf '%s|%s|%s|%s|%s\n' "$session_id" "$project_name" "$database_port" "$restored" "$latest_hash"
}

robotics_complete_local_postgres() {
  local session_id="$1"
  local project_name="$2"
  local database_port="$3"
  local backup_root="$4"
  local runtime_root="$5"
  local result hash now
  result="$(robotics_save_postgres_backup "$session_id" "$project_name" "$database_port" "$backup_root" "$runtime_root" false)"
  hash="${result##*|}"
  now="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  robotics_write_json_atomic "$runtime_root/database-sync.json" "$(printf \
    '{\"device\":\"%s\",\"dirty\":false,\"last_backup_sha256\":\"%s\",\"session_id\":null,\"updated_at_utc\":\"%s\"}' \
    "$(robotics_device_name)" "$hash" "$now")"
  rm -f -- "$backup_root/active-device.json"
  robotics_compose "$project_name" "$database_port" stop postgres >/dev/null
  printf 'Verified PostgreSQL backup saved to %s/latest.dump\n' "$backup_root"
}
