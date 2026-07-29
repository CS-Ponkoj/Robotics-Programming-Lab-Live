import math

# Define the points as (x, y) tuples
start_point = (0, 0)
goal_point = (10, 0)
obstacle_A = (4, -1)
obstacle_B = (6, -1)
obstacle_C = (6, 1)
obstacle_D = (4, 1)

# Calculate the straight-line distance from the start to the first point of the obstacle
distance_to_obstacle = obstacle_A[0] - start_point[0]

# Calculate the perimeter of the obstacle that the robot will travel.
# Since the robot always turns right and starts at point A, it will travel A -> D -> C -> B.
perimeter_of_obstacle = (obstacle_D[1] - obstacle_A[1]) + \
                        (obstacle_C[0] - obstacle_D[0]) + \
                        (obstacle_C[1] - obstacle_B[1])

# Calculate the straight-line distance from the last point of the obstacle to the goal
distance_from_obstacle_to_goal = goal_point[0] - obstacle_B[0]

# Calculate the total path length
total_path_length = distance_to_obstacle + perimeter_of_obstacle + distance_from_obstacle_to_goal
print(total_path_length)
