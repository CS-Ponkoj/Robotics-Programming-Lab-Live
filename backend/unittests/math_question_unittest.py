#!/bin/bash python3
from inspect import isfunction
import sys
import unittest
import os
import random
# import numpy as np
import scipy

class MathQuestionTestCase():
    
    def __init__(self, namespace, tested_values, vals, args=None):
        #there are better ways to do this but it works for now ig
        self.tested_values = tested_values
        self.vals = vals
        self.namespace = namespace
        self.args = args
        self.results = []

    def get_tested_vals(self):
        return self.tested_values

    def get_results(self):
        return self.results

    def random_compliment(self):
        compliment = ["great job", "good work", "gold star", "always achieving", "awe-inspiring", "brilliant"]
        return compliment[random.randint(0,len(compliment)-1)]

    def incorrect_answer(self, tested_value_cnt, answer_val):
        return_string = "The value of " + self.tested_values[tested_value_cnt]
        if self.tested_values[tested_value_cnt] in self.namespace:
            
            return_string += " \"" + str(answer_val) + "\""

            if type(answer_val) == str:
                if answer_val == self.vals[tested_value_cnt]:
                    return return_string+" is incorrect"

            difference = abs(self.vals[tested_value_cnt] - answer_val)

            if self.vals[tested_value_cnt] > answer_val:
                return_string += " is less than"
            elif self.vals[tested_value_cnt] < answer_val:
                return_string += " is greater than"
            
            return_string += " it should be"
            if difference < self.vals[tested_value_cnt]/100:
                return_string += " by less than a hundredth of the actual value"
            elif difference <= self.vals[tested_value_cnt]/10:
                return_string += " by less than a tenth of the actual value"
            
        else:
            return_string += " is not found in the provided namespace"
        return return_string
    
    def correct_answer(self, tested_value_cnt, answer_val):

        return "The value provided for " + self.tested_values[tested_value_cnt] + " is correct, " + self.random_compliment() + "!"


    def test_vals(self):
        return_val_list = []
        self.results = []
        count = 0
        for val in self.tested_values:
            if val in self.namespace:
                print(str(self.vals[count]) + " " + str(self.namespace[val]), file=sys.stderr)
                is_correct = bool(self.vals[count] == self.namespace[val])
                self.results.append(is_correct)
                if is_correct:
                    return_val_list.append(self.correct_answer(count, self.namespace[val]))
                else:
                    return_val_list.append(self.incorrect_answer(count, self.namespace[val]))
            else:
                self.results.append(False)
                return_val_list.append(self.incorrect_answer(count, None))
            count+=1
        return return_val_list
    
    
        

if __name__ == "__main__":
    # with file("math_question_1_solution.py", "r") as file:
    #     code = file.read()
    #     exec(code)

    tester = MathQuestionTestCase({
        "distance_to_hit": 2.8284271247461903,
        "distance_along_obstacle": 9.0,
        "total_distance": 16
    })

    print(tester.test_vals())
