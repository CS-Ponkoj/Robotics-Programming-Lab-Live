#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./scripts/linux-local-database.sh
source "$SCRIPT_DIR/linux-local-database.sh"

frontend_port="8080"
backend_port="5000"
sandbox_port="5001"
database_port="5432"
backup_interval="10"
database_url=""
use_sqlite="false"
enable_ai="false"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --frontend-port) frontend_port="$2"; shift 2 ;;
    --backend-port) backend_port="$2"; shift 2 ;;
    --sandbox-port) sandbox_port="$2"; shift 2 ;;
    --database-port) database_port="$2"; shift 2 ;;
    --backup-interval-minutes) backup_interval="$2"; shift 2 ;;
    --database-url) database_url="$2"; shift 2 ;;
    --use-sqlite) use_sqlite="true"; shift ;;
    --enable-ai) enable_ai="true"; shift ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

robotics_require_linux_x64
robotics_require_command curl 'Install curl through apt or ask lab IT.'
robotics_require_command flutter 'Install Flutter with Linux web support.'
robotics_require_command setsid 'Install util-linux through apt or ask lab IT.'
python="$(robotics_python)"
[[ -x "$python" ]] || {
  printf 'The Ubuntu Python environment is missing. Run ./scripts/setup-local.sh first.\n' >&2
  exit 1
}
if [[ "$use_sqlite" == "true" && -n "$database_url" ]]; then
  printf 'Use either --use-sqlite or --database-url, not both.\n' >&2
  exit 2
fi
for port in "$frontend_port" "$backend_port" "$sandbox_port"; do
  [[ "$port" =~ ^[0-9]+$ ]] || { printf 'Ports must be integers.\n' >&2; exit 2; }
  robotics_port_available "$port" || { printf 'Requested port is already in use: %s\n' "$port" >&2; exit 1; }
done
[[ "$backup_interval" =~ ^[0-9]+$ && "$backup_interval" -ge 1 && "$backup_interval" -le 1440 ]] || {
  printf 'Backup interval must be between 1 and 1440 minutes.\n' >&2
  exit 2
}

runtime_root="$(robotics_runtime_root)"
repository_root="$(robotics_repository_root)"
backend_root="$repository_root/backend"
handoff_root="$(robotics_handoff_root)"
process_file="$runtime_root/processes.tsv"
metadata_file="$runtime_root/managed.env"
log_root="$runtime_root/logs"
safe_frontend="$runtime_root/frontend"
mkdir -p -- "$runtime_root" "$log_root"
if robotics_any_managed_process_running; then
  printf 'The local application is already running. Use ./scripts/stop-local.sh first.\n' >&2
  exit 1
fi
rm -f -- "$process_file" "$metadata_file"

cleanup_failed_start() {
  local _name pid start_time
  if [[ -f "$process_file" ]]; then
    while IFS=$'\t' read -r _name pid start_time; do
      if robotics_process_matches "$pid" "$start_time"; then
        kill -- "-$pid" 2>/dev/null || true
      fi
    done < "$process_file"
  fi
  if [[ "${managed_database:-false}" == "true" && -n "${database_session_id:-}" ]]; then
    robotics_complete_local_postgres "$database_session_id" "$database_project" "$database_port" "$handoff_root" "$runtime_root" || true
  fi
  rm -f -- "$process_file" "$metadata_file"
}
trap cleanup_failed_start ERR INT TERM

start_managed_process() {
  local name="$1"
  local working_directory="$2"
  shift 2
  local stdout="$log_root/$name.stdout.log"
  local stderr="$log_root/$name.stderr.log"
  : > "$stdout"
  : > "$stderr"
  (
    cd -- "$working_directory"
    exec setsid "$@"
  ) >"$stdout" 2>"$stderr" &
  local pid=$!
  local start_time=""
  for _attempt in {1..20}; do
    start_time="$(robotics_process_start_time "$pid")"
    [[ -n "$start_time" ]] && break
    sleep 0.05
  done
  [[ -n "$start_time" ]] || { printf 'Could not record %s process identity.\n' "$name" >&2; return 1; }
  printf '%s\t%s\t%s\n' "$name" "$pid" "$start_time" >> "$process_file"
  ROBOTICS_LAST_PID="$pid"
}

managed_database="false"
database_session_id=""
database_project="${ROBOTICS_DATABASE_PROJECT_NAME:-robotics-lab-local}"
database_restored_backup="false"
has_backup="false"
if [[ "$use_sqlite" == "true" ]]; then
  database_url="sqlite:///robotics_lab_staging.db"
elif [[ -z "$database_url" ]]; then
  database_result="$(robotics_start_local_postgres "$database_port" "$database_project" "$handoff_root" "$runtime_root")"
  IFS='|' read -r database_session_id database_project database_port database_restored_backup latest_hash <<< "$database_result"
  database_url="postgresql+psycopg://robotics:robotics-local-only@127.0.0.1:$database_port/robotics_lab"
  managed_database="true"
  [[ -n "$latest_hash" ]] && has_backup="true"
fi

(
  cd -- "$backend_root"
  DATABASE_URL="$database_url" "$python" -m alembic upgrade head
  if [[ "$managed_database" == "true" && "$has_backup" != "true" && -f robotics_lab_staging.db ]]; then
    DATABASE_URL="$database_url" "$python" database_transfer.py \
      --sqlite robotics_lab_staging.db --target-url "$database_url" \
      --report "$runtime_root/sqlite-import-report.json" --if-empty
  fi
)

sandbox_token="$($python -c 'import secrets; print(secrets.token_hex(32))')"
start_managed_process sandbox "$backend_root" env \
  SANDBOX_API_TOKEN="$sandbox_token" SANDBOX_MAX_CONCURRENT_EXECUTIONS=2 \
  "$python" -m uvicorn sandbox_service:app --host 127.0.0.1 --port "$sandbox_port" --no-server-header
robotics_wait_for_http Sandbox "http://127.0.0.1:$sandbox_port/health"

backend_environment=(
  ENVIRONMENT=development
  DATABASE_URL="$database_url"
  AUTO_CREATE_SCHEMA="$([[ "$use_sqlite" == "true" ]] && printf true || printf false)"
  PUBLIC_APP_URL="http://127.0.0.1:$frontend_port"
  ALLOWED_ORIGINS="http://127.0.0.1:$frontend_port,http://localhost:$frontend_port"
  SANDBOX_BACKEND=remote
  SANDBOX_URL="http://127.0.0.1:$sandbox_port"
  SANDBOX_API_TOKEN="$sandbox_token"
  ROBOTICS_ENV_FILE="$handoff_root/.env"
)
[[ "$enable_ai" != "true" ]] && backend_environment+=(OPENAI_API_KEY=)
start_managed_process backend "$backend_root" env "${backend_environment[@]}" \
  "$python" -m uvicorn app:app --host 127.0.0.1 --port "$backend_port" --no-server-header
robotics_wait_for_http Backend "http://127.0.0.1:$backend_port/health"

if [[ "$managed_database" == "true" ]]; then
  start_managed_process database-backup "$repository_root" \
    "$SCRIPT_DIR/backup-local-database.sh" \
      --session-id "$database_session_id" --database-port "$database_port" \
      --project-name "$database_project" --backup-root "$handoff_root" \
      --runtime-root "$runtime_root" --interval-minutes "$backup_interval"
fi

robotics_assert_path_under "$safe_frontend" "$runtime_root"
rm -rf -- "$safe_frontend"
mkdir -p -- "$safe_frontend"
for directory in fonts lib web; do
  cp -a -- "$repository_root/frontend/$directory" "$safe_frontend/$directory"
done
for file in .metadata analysis_options.yaml pubspec.lock pubspec.yaml; do
  cp -- "$repository_root/frontend/$file" "$safe_frontend/$file"
done
(
  cd -- "$safe_frontend"
  flutter pub get
)
start_managed_process frontend "$safe_frontend" flutter run -d web-server \
  --web-hostname 127.0.0.1 --web-port "$frontend_port" \
  "--dart-define=API_BASE_URL=http://127.0.0.1:$backend_port"
frontend_pid="$ROBOTICS_LAST_PID"
for _attempt in {1..240}; do
  grep -Fq "is being served at http://127.0.0.1:$frontend_port" "$log_root/frontend.stdout.log" 2>/dev/null && break
  robotics_process_matches "$frontend_pid" "$(awk -F '\t' '$1=="frontend" {print $3}' "$process_file")" || {
    printf 'Frontend exited before it became ready. Review %s.\n' "$log_root" >&2
    exit 1
  }
  sleep 0.5
done
robotics_wait_for_http 'Frontend shell' "http://127.0.0.1:$frontend_port" 240
robotics_wait_for_http 'Frontend entrypoint' "http://127.0.0.1:$frontend_port/web_entrypoint.dart" 240

cat > "$metadata_file" <<EOF
managed_database=$managed_database
database_session_id=$database_session_id
database_project=$database_project
database_port=$database_port
backup_root=$handoff_root
runtime_root=$runtime_root
frontend_url=http://127.0.0.1:$frontend_port
backend_url=http://127.0.0.1:$backend_port
sandbox_url=http://127.0.0.1:$sandbox_port
ai_enabled=$enable_ai
EOF
trap - ERR INT TERM
printf 'Robotics Programming Lab is ready.\n'
printf 'Frontend: http://127.0.0.1:%s/app\n' "$frontend_port"
printf 'Backend:  http://127.0.0.1:%s/health\n' "$backend_port"
printf 'Sandbox:  http://127.0.0.1:%s/health\n' "$sandbox_port"
printf 'Database: %s\n' "$([[ "$managed_database" == "true" ]] && printf 'local PostgreSQL with unified handoff package' || printf 'external or SQLite')"
[[ "$database_restored_backup" == "true" ]] && printf 'Restored the newest verified PostgreSQL handoff backup.\n'
printf 'AI enabled: %s\n' "$enable_ai"
[[ "$managed_database" == "true" ]] && printf 'Automatic database backup: every %s minute(s)\n' "$backup_interval"
printf 'Stop with: ./scripts/stop-local.sh\n'
