#!/bin/bash python3
import unittest
import os
from Programming_Question_1 import *


class ProgrammingQuestion1TestCase(unittest.TestCase):
    
    def testDistanceToObstacle(self):
        self.assertEqual(distance_to_obstacle, 4, "Distance to the first obstacle is incorrect")
        
    def testPerimiterOfObstacle(self):
        self.assertEqual(perimeter_of_obstacle, 6, "Distance along the obstacle boundary is incorrect")
    
    def testDistanceFromObstacleToGoal(self):
        self.assertEqual(distance_from_obstacle_to_goal, 4, "Distance from obstacle to goal is incorrect")
    
    def testTotalDistance(self):
        self.assertEqual(total_path_length, 14, "The total distance you calculated is incorrect")
    
    
        

if __name__ == '__main__':  
    # with file("math_question_1_solution.py", 'r') as file:
    #     code = file.read()
    #     exec(code)
    
    unittest.main()