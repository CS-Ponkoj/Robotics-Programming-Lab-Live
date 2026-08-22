import math

# Define the route points as (x, y) tuples
start_point = (0, 0)
goal_point = (10, 0)
hit_point = (4, 0)
leave_point = (6, 0)
obstacle_A = (4, -1)
obstacle_B = (6, -1)
obstacle_C = (6, 1)
obstacle_D = (4, 1)

def calculate_distance(point_1, point_2):
    return math.hypot(point_2[0] - point_1[0], point_2[1] - point_1[1])


distance_to_obstacle = calculate_distance(start_point, hit_point)

# The right-turn boundary route follows H -> A -> B -> L.
distance_along_obstacle = (
    calculate_distance(hit_point, obstacle_A)
    + calculate_distance(obstacle_A, obstacle_B)
    + calculate_distance(obstacle_B, leave_point)
)

distance_from_obstacle_to_goal = calculate_distance(leave_point, goal_point)

# Calculate the total path length
total_path_length = distance_to_obstacle + distance_along_obstacle + distance_from_obstacle_to_goal
print(total_path_length)
