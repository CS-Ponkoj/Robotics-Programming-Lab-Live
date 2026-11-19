import math

import rclpy
from geometry_msgs.msg import Twist
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rse_msgs.msg import Flbr


class OpenSideController(Node):

    def __init__(self):
        super().__init__('open_side_controller')
        self.velocity_publisher = self.create_publisher(Twist, '/cmd_vel', 10)
        self.flbr_subscription = self.create_subscription(
            Flbr, '/flbr', self.handle_flbr, 10)

        self.forward_speed = 0.20   # m/s
        self.turn_speed = 0.5       # rad/s
        self.stop_distance = 0.75   # m

    def handle_flbr(self, msg):
        # An unknown (NaN) distance counts as no space.
        front = 0.0 if math.isnan(msg.front) else msg.front
        left = 0.0 if math.isnan(msg.left) else msg.left
        right = 0.0 if math.isnan(msg.right) else msg.right

        command = Twist()
        if front > self.stop_distance:
            command.linear.x = self.forward_speed
        elif left > right:
            command.angular.z = self.turn_speed
        else:
            command.angular.z = -self.turn_speed

        self.velocity_publisher.publish(command)


def main(args=None):
    rclpy.init(args=args)
    controller = OpenSideController()
    try:
        rclpy.spin(controller)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        controller.destroy_node()
        rclpy.try_shutdown()


if __name__ == '__main__':
    main()
