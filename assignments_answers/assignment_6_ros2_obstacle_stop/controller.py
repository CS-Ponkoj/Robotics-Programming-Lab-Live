import math

import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node
from sensor_msgs.msg import LaserScan


class ObstacleStopController(Node):

    def __init__(self):
        super().__init__('obstacle_stop_controller')
        self.velocity_publisher = self.create_publisher(Twist, '/cmd_vel', 10)
        self.scan_subscription = self.create_subscription(
            LaserScan,
            '/scan',
            self.handle_scan,
            10,
        )
        self.forward_speed = 0.20
        self.stop_distance = 0.75

    def handle_scan(self, scan):
        valid_ranges = [
            distance
            for distance in scan.ranges
            if math.isfinite(distance) and distance > 0.0
        ]
        nearest_obstacle = min(valid_ranges) if valid_ranges else 0.0

        command = Twist()
        if nearest_obstacle > self.stop_distance:
            command.linear.x = self.forward_speed
        else:
            command.linear.x = 0.0
        command.angular.z = 0.0
        self.velocity_publisher.publish(command)


def main(args=None):
    rclpy.init(args=args)
    controller = ObstacleStopController()
    try:
        rclpy.spin(controller)
    except KeyboardInterrupt:
        pass
    finally:
        controller.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
