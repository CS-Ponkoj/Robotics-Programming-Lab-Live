import unittest

from math_question_1_solution import *


class MathQuestion1TestCase(unittest.TestCase):

    def test_distance_to_hit(self):
        self.assertAlmostEqual(distance_to_hit, 10.0 / 3.0)

    def test_distance_along_obstacle(self):
        self.assertAlmostEqual(distance_along_obstacle, 49.0 / 12.0)

    def test_distance_leave_to_goal(self):
        self.assertAlmostEqual(distance_leave_to_goal, 15.0 / 4.0)

    def test_total_distance(self):
        self.assertAlmostEqual(total_distance, 67.0 / 6.0)


if __name__ == "__main__":
    unittest.main()
