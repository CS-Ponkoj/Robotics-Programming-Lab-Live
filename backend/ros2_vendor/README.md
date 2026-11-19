# Vendored ROS 2 interface packages

These packages are built into the ROS 2 grader image (`Dockerfile.ros2`) so
student packages can use them. Students never edit them.

| Package | Source | License |
|---|---|---|
| `rse_msgs` | `unr-rse-fall-2026/rse-fall-2026-class-code`, commit `42e6ac22501d1aae4013ebcede3fd7a5e78be360`, folder `rse_msgs/` (unchanged) | BSD-3-Clause, see `rse_msgs/LICENSE` |

`rse_msgs/Flbr` carries the closest obstacle distance in four 90-degree
sectors (front, left, back, right) in metres; NaN marks a sector with no usable
reading. Assignment 8 (shown to students as Assignment 2) subscribes to it.
