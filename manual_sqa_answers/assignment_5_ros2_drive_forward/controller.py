import rclpy
from rclpy.node import Node
from geometry_msgs.msg import Twist


class RobotController(Node):

    def __init__(self):
        super().__init__('robot_controller')
        self.velocity_publisher = self.create_publisher(Twist, '/cmd_vel', 10)
        self.elapsed_time = 0.0
        self.timer_period = 0.1
        self.timer = self.create_timer(self.timer_period, self.control_robot)

    def control_robot(self):
        command = Twist()
        if self.elapsed_time < 5.0:
            command.linear.x = 0.20
            command.angular.z = 0.0
        else:
            command.linear.x = 0.0
            command.angular.z = 0.0
        self.velocity_publisher.publish(command)
        self.elapsed_time += self.timer_period


def main(args=None):
    rclpy.init(args=args)
    controller = RobotController()
    try:
        rclpy.spin(controller)
    except KeyboardInterrupt:
        pass
    finally:
        controller.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
