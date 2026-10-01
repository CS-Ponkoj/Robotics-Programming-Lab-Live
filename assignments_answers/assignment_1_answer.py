import math


start_point = (2.0, 1.0)
goal_point = (8.0, 9.0)
hit_point = (4.0, 11.0 / 3.0)
top_left = (4.0, 6.0)
leave_point = (23.0 / 4.0, 6.0)


def calculate_distance(point_1, point_2):
    return math.hypot(point_2[0] - point_1[0], point_2[1] - point_1[1])


def calculate_bug2_route(start, hit, corner, leave, goal):
    distance_to_hit = calculate_distance(start, hit)
    distance_along_obstacle = (
        calculate_distance(hit, corner) + calculate_distance(corner, leave)
    )
    distance_leave_to_goal = calculate_distance(leave, goal)
    total_distance = (
        distance_to_hit + distance_along_obstacle + distance_leave_to_goal
    )
    return (
        distance_to_hit,
        distance_along_obstacle,
        distance_leave_to_goal,
        total_distance,
    )


result = calculate_bug2_route(
    start_point, hit_point, top_left, leave_point, goal_point
)
print("Total travel distance:", result[3])
