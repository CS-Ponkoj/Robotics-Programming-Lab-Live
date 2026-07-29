import math

def calculate_distance(x1, y1, x2, y2):
  return math.sqrt((x2 - x1)**2 + (y2 - y1)**2)

# Initial conditions
start_x = 2
start_y = 1
goal_x = 8
goal_y = 9
obstacle_x1 = 4 
obstacle_y1 = 3
obstacle_x2 = 7
obstacle_y2 = 6

# Distance to hit point
distance_to_hit = calculate_distance(start_x, start_y, obstacle_x1, obstacle_y1)

# Distance along obstacle boundary (clockwise)
distance_along_obstacle = calculate_distance(obstacle_x1, obstacle_y1, obstacle_x2, obstacle_y1) + \
                         calculate_distance(obstacle_x2, obstacle_y1, obstacle_x2, obstacle_y2) + \
                         calculate_distance(obstacle_x2, obstacle_y2, obstacle_x1, obstacle_y2)

# Distance from leave point to goal (Bug 2)
distance_leave_to_goal = calculate_distance(obstacle_x1, obstacle_y2, goal_x, goal_y)

# Total distance
total_distance = distance_to_hit + distance_along_obstacle + distance_leave_to_goal

print("Total travel distance:", total_distance) 
