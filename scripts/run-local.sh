#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./scripts/linux-local-common.sh
source "$SCRIPT_DIR/linux-local-common.sh"

frontend_port="8080"
backend_port="5000"
sandbox_port="5001"
enable_ai="false"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --frontend-port) frontend_port="$2"; shift 2 ;;
    --backend-port) backend_port="$2"; shift 2 ;;
    --sandbox-port) sandbox_port="$2"; shift 2 ;;
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
for port in "$frontend_port" "$backend_port" "$sandbox_port"; do
  [[ "$port" =~ ^[0-9]+$ ]] || { printf 'Ports must be integers.\n' >&2; exit 2; }
  robotics_port_available "$port" || { printf 'Requested port is already in use: %s\n' "$port" >&2; exit 1; }
done

runtime_root="$(robotics_runtime_root)"
repository_root="$(robotics_repository_root)"
backend_root="$repository_root/backend"
private_config="$(robotics_private_config)"
process_file="$runtime_root/processes.tsv"
metadata_file="$runtime_root/managed.env"
log_root="$runtime_root/logs"
safe_frontend="$runtime_root/frontend"
mkdir -p -- "$runtime_root" "$log_root"
[[ -f "$private_config" ]] || {
  printf 'Neon configuration is missing: repository root .env\n' >&2
  exit 1
}
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

database_url="$(
  cd -- "$backend_root"
  ROBOTICS_ENV_FILE="$private_config" "$python" -c \
    'from config import get_settings; print(get_settings().cloud_database_url or "")'
)"
[[ -n "$database_url" && "$database_url" == *neon.tech* ]] || {
  printf 'NEON_DATABASE_URL is missing or invalid in the repository root .env.\n' >&2
  exit 1
}
printf 'Using the configured Neon staging database.\n'
ai_available="$(
  cd -- "$backend_root"
  ROBOTICS_ENV_FILE="$private_config" "$python" -c \
    'from config import get_settings; print("true" if get_settings().openai_api_key else "false")'
)"
if [[ "$enable_ai" == "true" && "$ai_available" != "true" ]]; then
  printf '%s\n' '--enable-ai was requested, but OPENAI_API_KEY is not configured in the repository root .env.' >&2
  exit 1
fi
(
  cd -- "$backend_root"
  DATABASE_URL="$database_url" "$python" -m alembic upgrade head
)

sandbox_token="$($python -c 'import secrets; print(secrets.token_hex(32))')"
start_managed_process sandbox "$backend_root" env \
  SANDBOX_API_TOKEN="$sandbox_token" SANDBOX_MAX_CONCURRENT_EXECUTIONS=2 \
  "$python" -m uvicorn sandbox_service:app --host 127.0.0.1 --port "$sandbox_port" --no-server-header
robotics_wait_for_http Sandbox "http://127.0.0.1:$sandbox_port/health"

backend_environment=(
  ENVIRONMENT=development
  DATABASE_URL="$database_url"
  AUTO_CREATE_SCHEMA=false
  PUBLIC_APP_URL="http://127.0.0.1:$frontend_port"
  ALLOWED_ORIGINS="http://127.0.0.1:$frontend_port,http://localhost:$frontend_port"
  SANDBOX_BACKEND=remote
  SANDBOX_URL="http://127.0.0.1:$sandbox_port"
  SANDBOX_API_TOKEN="$sandbox_token"
  ROBOTICS_ENV_FILE="$private_config"
)
start_managed_process backend "$backend_root" env "${backend_environment[@]}" \
  "$python" -m uvicorn app:app --host 127.0.0.1 --port "$backend_port" --no-server-header
robotics_wait_for_http Backend "http://127.0.0.1:$backend_port/health"

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
    # An explicit exit skips the ERR trap; stop the sandbox and backend too.
    cleanup_failed_start
    exit 1
  }
  sleep 0.5
done
robotics_wait_for_http 'Frontend shell' "http://127.0.0.1:$frontend_port" 240
robotics_wait_for_http 'Frontend entrypoint' "http://127.0.0.1:$frontend_port/web_entrypoint.dart" 240

cat > "$metadata_file" <<EOF
database_provider=neon
frontend_url=http://127.0.0.1:$frontend_port
backend_url=http://127.0.0.1:$backend_port
sandbox_url=http://127.0.0.1:$sandbox_port
ai_available=$ai_available
ai_enabled_by_default=false
EOF
trap - ERR INT TERM
printf 'Robotics Programming Lab is ready.\n'
printf 'Frontend: http://127.0.0.1:%s/app\n' "$frontend_port"
printf 'Backend:  http://127.0.0.1:%s/health\n' "$backend_port"
printf 'Sandbox:  http://127.0.0.1:%s/health\n' "$sandbox_port"
printf 'Database: Neon staging PostgreSQL\n'
printf 'AI available: %s; off until the assignment switch is turned on.\n' "$ai_available"
printf 'Stop with: ./scripts/stop-local.sh\n'
