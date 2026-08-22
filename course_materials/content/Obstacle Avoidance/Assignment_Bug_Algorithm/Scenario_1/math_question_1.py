import math


start_point = (2.0, 1.0)
goal_point = (8.0, 9.0)
hit_point = (4.0, 11.0 / 3.0)
top_left = (4.0, 6.0)
leave_point = (23.0 / 4.0, 6.0)


def calculate_distance(point_1, point_2):
    return math.hypot(point_2[0] - point_1[0], point_2[1] - point_1[1])


# TODO: Distance from the start to the m-line hit point.
distance_to_hit = 0.0

# TODO: Clockwise boundary distance H -> T -> L.
distance_along_obstacle = 0.0

# TODO: Distance from the m-line leave point to the goal.
distance_leave_to_goal = 0.0

# TODO: Add the three traveled components exactly once.
total_distance = 0.0

print("Total travel distance:", total_distance)
