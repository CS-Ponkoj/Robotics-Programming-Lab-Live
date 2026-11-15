import math

import rclpy
from geometry_msgs.msg import Twist
from rclpy.executors import ExternalShutdownException
from sensor_msgs.msg import LaserScan

FORWARD_SPEED = 0.20    # m/s
STOP_DISTANCE = 0.50    # m
FRONT_READINGS = 5      # readings on each side of straight ahead


def build_node():
    node = rclpy.create_node('wall_stop')
    publisher = node.create_publisher(Twist, '/cmd_vel', 10)

    def handle_scan(scan):
        middle = len(scan.ranges) // 2
        ahead = scan.ranges[middle - FRONT_READINGS:middle + FRONT_READINGS + 1]
        usable = [distance for distance in ahead if not math.isnan(distance)]
        command = Twist()
        if usable and min(usable) > STOP_DISTANCE:
            command.linear.x = FORWARD_SPEED
        publisher.publish(command)

    node.create_subscription(LaserScan, '/scan', handle_scan, 10)
    return node


def main(args=None):  # Do not change main().
    rclpy.init(args=args)
    node = build_node()
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == '__main__':
    main()
