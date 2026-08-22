import math


start_point = (2.0, 1.0)
goal_point = (8.0, 9.0)
hit_point = (4.0, 11.0 / 3.0)
top_left = (4.0, 6.0)
leave_point = (23.0 / 4.0, 6.0)


def calculate_distance(point_1, point_2):
    return math.hypot(point_2[0] - point_1[0], point_2[1] - point_1[1])


distance_to_hit = calculate_distance(start_point, hit_point)
distance_along_obstacle = (
    calculate_distance(hit_point, top_left)
    + calculate_distance(top_left, leave_point)
)
distance_leave_to_goal = calculate_distance(leave_point, goal_point)
total_distance = distance_to_hit + distance_along_obstacle + distance_leave_to_goal

print("Total travel distance:", total_distance)
