#!/bin/bash python3
import unittest
import os

#needs to be in the same directory as the question file - working on a solution
from question_1_solution import *



class OAUnitTest(unittest.TestCase):
        
    def test_path_to_E_m(self):
        self.assertEqual(path_to_E_m, 
                         14.385164807134505, 
                         "The path to main elevator is incorrect")
    
    def test_path_to_E_s(self):
        self.assertEqual(path_to_E_s, 
                         10.04987562112089, 
                         "The path to service elevator is incorrect")
    
    def test_straight_line_distance_with_barrier(self):
        self.assertEqual(straight_line_distance_with_barrier(S, 
                                                             E_m, 
                                                             barrier_start, 
                                                             barrier_end, 
                                                             safety_margin), 
                         14.385164807134505, 
                         "The straight line distance with barrier function is incorrect")
    
    def test_time_to_E_m(self):
        self.assertEqual(time_to_E_m, 
                         119.3851648071345, 
                         "The time to main elevator is incorrect")
    
    def test_time_to_E_s(self):
        self.assertEqual(time_to_E_s, 
                         120.04987562112089, 
                         "The time to service elevator is incorrect")
        
    def test_best_option(self):
        self.assertEqual(best_option, 
                         "Main Elevator", 
                         "The best path option is incorrect, check your calculations")
        
    def test_best_time(self):
        self.assertEqual(best_time, 119.3851648071345, "The best time is incorrect")

if __name__ == '__main__':
    # with file("math_question_1_solution.py", 'r') as file:
    #     code = file.read()
    #     exec(code)
    
    unittest.main()