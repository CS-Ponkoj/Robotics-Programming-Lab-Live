#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./scripts/linux-local-common.sh
source "$SCRIPT_DIR/linux-local-common.sh"

include_private_config="false"
if [[ "${1:-}" == "--include-private-config" ]]; then
  include_private_config="true"
  shift
fi
if [[ "$#" -ne 0 ]]; then
  printf 'Usage: %s [--include-private-config]\n' "$0" >&2
  exit 2
fi
if robotics_any_managed_process_running; then
  printf 'Stop the application before creating the handoff package: ./scripts/stop-local.sh\n' >&2
  exit 1
fi

repository_root="$(robotics_repository_root)"
package_root="$(robotics_handoff_root)"
latest_dump="$package_root/latest.dump"
latest_manifest="$package_root/latest.json"
mkdir -p -- "$package_root"
[[ -f "$latest_dump" && -f "$latest_manifest" ]] || {
  printf 'No complete database backup exists. Start and stop the application once.\n' >&2
  exit 1
}
database_hash="$(robotics_sha256 "$latest_dump")"
[[ "$database_hash" == "$(robotics_json_field "$latest_manifest" sha256)" ]] || {
  printf 'The current database backup failed checksum verification.\n' >&2
  exit 1
}

packaged_config="$package_root/.env"
backend_config="$repository_root/backend/.env"
if [[ "$include_private_config" == "true" && -f "$backend_config" ]]; then
  cp -- "$backend_config" "$packaged_config"
  chmod 600 "$packaged_config"
elif [[ "$include_private_config" == "true" && ! -f "$packaged_config" ]]; then
  printf 'No private configuration was found; .env was not created.\n' >&2
fi
git_head="$(git -C "$repository_root" rev-parse HEAD 2>/dev/null || true)"
working_tree_dirty="false"
[[ -n "$(git -C "$repository_root" status --porcelain)" ]] && working_tree_dirty="true"
robotics_write_json_atomic "$package_root/package.json" "$(printf \
  '{\"schemaVersion\":1,\"createdAtUtc\":\"%s\",\"sourceCommit\":\"%s\",\"sourceWorkingTreeDirty\":%s,\"databaseSha256\":\"%s\",\"includesPrivateConfig\":%s,\"includesPythonEnvironment\":false}' \
  "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$git_head" "$working_tree_dirty" "$database_hash" \
  "$([[ -f "$packaged_config" ]] && printf true || printf false)")"
chmod 600 "$latest_dump" "$latest_manifest" "$package_root/package.json" 2>/dev/null || true
printf 'Local handoff package is ready: %s\n' "$package_root"
printf 'Database checksum verified: %s\n' "$database_hash"
printf 'Private configuration included: %s\n' "$([[ -f "$packaged_config" ]] && printf true || printf false)"
printf 'Python environment included: false (rebuilt on the destination computer)\n'
