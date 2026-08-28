#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./scripts/linux-local-database.sh
source "$SCRIPT_DIR/linux-local-database.sh"

python="$(robotics_python)"
[[ -x "$python" ]] || { printf 'Run ./scripts/setup-local.sh first.\n' >&2; exit 1; }
test_id="$(tr -d '-' < /proc/sys/kernel/random/uuid)"
test_root="$(mktemp -d -t robotics-db-handoff-XXXXXXXX)"
backup_root="$test_root/backups"
runtime_one="$test_root/runtime-one"
runtime_two="$test_root/runtime-two"
project_name="robotics-lab-linux-handoff-${test_id:0:10}"
database_port="$($python - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"

cleanup() {
  LOCAL_POSTGRES_PORT="$database_port" LOCAL_POSTGRES_PASSWORD="$ROBOTICS_DB_PASSWORD" \
    docker compose --project-name "$project_name" \
      --file "$(robotics_repository_root)/docker-compose.yml" down --volumes >/dev/null 2>&1 || true
  case "$(realpath -m -- "$test_root")" in
    "$(realpath -m -- "${TMPDIR:-/tmp}")"/*) rm -rf -- "$test_root" ;;
  esac
}
trap cleanup EXIT

first="$(ROBOTICS_DEVICE_NAME=LINUX-DEVICE-ONE robotics_start_local_postgres \
  "$database_port" "$project_name" "$backup_root" "$runtime_one")"
IFS='|' read -r first_session _project _port _restored _hash <<< "$first"
(
  cd -- "$(robotics_repository_root)/backend"
  DATABASE_URL="postgresql+psycopg://robotics:robotics-local-only@127.0.0.1:$database_port/robotics_lab" \
    "$python" -m alembic upgrade head
)

blocked="false"
if ROBOTICS_DEVICE_NAME=LINUX-DEVICE-TWO robotics_start_local_postgres \
  "$database_port" "$project_name" "$backup_root" "$runtime_two" >/dev/null 2>&1; then
  printf 'Simulated second device unexpectedly acquired the database.\n' >&2
  exit 1
else
  blocked="true"
fi
[[ "$blocked" == "true" ]]

automatic="$(ROBOTICS_DEVICE_NAME=LINUX-DEVICE-ONE robotics_save_postgres_backup \
  "$first_session" "$project_name" "$database_port" "$backup_root" "$runtime_one" true)"
[[ "$automatic" == saved\|* ]] || { printf 'First automatic backup was not saved.\n' >&2; exit 1; }
unchanged="$(ROBOTICS_DEVICE_NAME=LINUX-DEVICE-ONE robotics_save_postgres_backup \
  "$first_session" "$project_name" "$database_port" "$backup_root" "$runtime_one" true)"
[[ "$unchanged" == "unchanged" ]] || { printf 'Unchanged database was not skipped.\n' >&2; exit 1; }

ROBOTICS_DEVICE_NAME=LINUX-DEVICE-ONE robotics_complete_local_postgres \
  "$first_session" "$project_name" "$database_port" "$backup_root" "$runtime_one" >/dev/null
[[ ! -f "$backup_root/active-device.json" ]]

LOCAL_POSTGRES_PORT="$database_port" LOCAL_POSTGRES_PASSWORD="$ROBOTICS_DB_PASSWORD" \
  docker compose --project-name "$project_name" \
    --file "$(robotics_repository_root)/docker-compose.yml" down --volumes >/dev/null
second="$(ROBOTICS_DEVICE_NAME=LINUX-DEVICE-TWO robotics_start_local_postgres \
  "$database_port" "$project_name" "$backup_root" "$runtime_two")"
IFS='|' read -r second_session _project _port restored _hash <<< "$second"
[[ "$restored" == "true" ]] || { printf 'Clean-device restore did not occur.\n' >&2; exit 1; }
schema_version="$(robotics_compose "$project_name" "$database_port" exec -T postgres \
  psql -U robotics -d robotics_lab -At -c 'SELECT version_num FROM alembic_version;' | tail -n 1 | tr -d '\r')"
[[ "$schema_version" == "0004_basic_research_analytics" ]]
ROBOTICS_DEVICE_NAME=LINUX-DEVICE-TWO robotics_complete_local_postgres \
  "$second_session" "$project_name" "$database_port" "$backup_root" "$runtime_two" >/dev/null
printf 'PASS: Ubuntu automatic backup, unchanged skip, device lock, final backup, and clean-device restore.\n'
