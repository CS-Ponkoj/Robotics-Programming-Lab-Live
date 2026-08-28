#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./scripts/linux-local-common.sh
source "$SCRIPT_DIR/linux-local-common.sh"

build="false"
if [[ "${1:-}" == "--build" ]]; then
  build="true"
  shift
fi
if [[ "$#" -ne 0 ]]; then
  printf 'Usage: %s [--build]\n' "$0" >&2
  exit 2
fi
robotics_require_linux_x64
robotics_require_command docker 'Install Docker Engine and the Compose plugin.'
docker info >/dev/null
if [[ "$build" == "true" ]]; then
  robotics_compose_file="$(robotics_repository_root)/docker-compose.yml"
  docker compose --file "$robotics_compose_file" --profile build build ros2-grader-image
fi
docker image inspect robotics-lab-ros2-grader:jazzy-v1 >/dev/null 2>&1 || {
  printf 'ROS 2 grader image is missing. Run: ./scripts/check-ros2-local.sh --build\n' >&2
  exit 1
}
python="$(robotics_python)"
[[ -x "$python" ]] || { printf 'Run ./scripts/setup-local.sh first.\n' >&2; exit 1; }
printf 'ROS 2 local grader is ready: robotics-lab-ros2-grader:jazzy-v1\n'
"$python" "$(robotics_repository_root)/backend/verify_ros2_assignments.py"
