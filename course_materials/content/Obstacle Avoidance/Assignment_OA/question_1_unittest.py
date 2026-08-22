import unittest

from question_1 import *


class Assignment3TestCase(unittest.TestCase):

    def test_path_to_main_elevator(self):
        self.assertAlmostEqual(path_to_E_m, 5.130648586880582)

    def test_path_to_service_elevator(self):
        self.assertAlmostEqual(path_to_E_s, 13.191468274710683)

    def test_main_elevator_to_goal(self):
        self.assertAlmostEqual(path_from_E_m_to_goal, 29.154759474226502)

    def test_service_elevator_to_goal(self):
        self.assertAlmostEqual(path_from_E_s_to_goal, 24.20743687382041)

    def test_total_time_via_main(self):
        self.assertAlmostEqual(total_time_via_E_m, 139.2854080611071)

    def test_total_time_via_service(self):
        self.assertAlmostEqual(total_time_via_E_s, 147.3989051485311)

    def test_best_option(self):
        self.assertEqual(best_option, "Main Elevator")

    def test_best_time(self):
        self.assertAlmostEqual(best_time, 139.2854080611071)


if __name__ == "__main__":
    unittest.main()
