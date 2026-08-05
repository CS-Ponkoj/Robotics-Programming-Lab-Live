# Define the points as (x, y) tuples.
start_point = (0, 0)
goal_point = (10, 0)
obstacle_a = (4, -1)
obstacle_b = (6, -1)
obstacle_c = (6, 1)
obstacle_d = (4, 1)

# Travel from the start to the first obstacle point.
distance_to_obstacle = obstacle_a[0] - start_point[0]

# The right-turn path follows A -> D -> C -> B.
perimeter_of_obstacle = (
    (obstacle_d[1] - obstacle_a[1])
    + (obstacle_c[0] - obstacle_d[0])
    + (obstacle_c[1] - obstacle_b[1])
)

# Continue from the obstacle to the goal.
distance_from_obstacle_to_goal = goal_point[0] - obstacle_b[0]

total_path_length = (
    distance_to_obstacle
    + perimeter_of_obstacle
    + distance_from_obstacle_to_goal
)

print("Total path length:", total_path_length)
