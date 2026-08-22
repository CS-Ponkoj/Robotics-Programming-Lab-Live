import math


# Define the route points as (x, y) tuples.
start_point = (0, 0)
goal_point = (10, 0)
hit_point = (4, 0)
leave_point = (6, 0)
obstacle_a = (4, -1)
obstacle_b = (6, -1)
obstacle_c = (6, 1)
obstacle_d = (4, 1)

def calculate_distance(point_1, point_2):
    return math.hypot(point_2[0] - point_1[0], point_2[1] - point_1[1])


# Travel from the start to the hit point on the m-line.
distance_to_obstacle = calculate_distance(start_point, hit_point)

# The right-turn boundary route follows H -> A -> B -> L.
distance_along_obstacle = (
    calculate_distance(hit_point, obstacle_a)
    + calculate_distance(obstacle_a, obstacle_b)
    + calculate_distance(obstacle_b, leave_point)
)

# Continue from the leave point to the goal.
distance_from_obstacle_to_goal = calculate_distance(leave_point, goal_point)

total_path_length = (
    distance_to_obstacle
    + distance_along_obstacle
    + distance_from_obstacle_to_goal
)

print("Total path length:", total_path_length)
