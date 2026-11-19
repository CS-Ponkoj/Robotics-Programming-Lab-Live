#!/bin/bash
# Grader entrypoint: ROS 2 Jazzy plus the vendored course interfaces
# (rse_msgs), so student packages and harnesses can both use them.
set -e
source /opt/ros/jazzy/setup.bash
source /opt/rse_ws/install/setup.bash
exec python3 /grader/ros2_worker.py "$@"
