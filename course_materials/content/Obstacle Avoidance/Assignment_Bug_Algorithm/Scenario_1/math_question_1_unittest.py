#!/bin/bash python3
import unittest
import os
from math_question_1_solution import *


#feedback on direction
#need to be able to show the correct value - guidance.

class MathQuestion1TestCase(unittest.TestCase):
    
    def testDistanceToHit(self):
        self.assertEqual(distance_to_hit, 2.8284271247461903, "Distance to hit the first point is incorrect")
        
    def testDistanceAlongObstacle(self):
        self.assertEqual(distance_along_obstacle, 9.0, "Distance along the obstacle boundary is incorrect")
    
    def testDistanceLeaveToGoal(self):
        self.assertEqual(distance_leave_to_goal, 5.0, "Distance from leave point to goal is incorrect")
    
    def testTotalDistance(self):
        self.assertEqual(total_distance, 16.82842712474619, "The total distance you calculated is incorrect")
    
    
        

if __name__ == '__main__':
    # with file("math_question_1_solution.py", 'r') as file:
    #     code = file.read()
    #     exec(code)
    
    unittest.main()