import math


def calculate_distance(point_1, point_2):
    return math.hypot(point_2[0] - point_1[0], point_2[1] - point_1[1])


def calculate_bug_route(start, hit, corner_a, corner_b, leave, goal):
    distance_to_hit = calculate_distance(start, hit)
    distance_along_obstacle = (
        calculate_distance(hit, corner_a)
        + calculate_distance(corner_a, corner_b)
        + calculate_distance(corner_b, leave)
    )
    distance_leave_to_goal = calculate_distance(leave, goal)
    total_distance = (
        distance_to_hit
        + distance_along_obstacle
        + distance_leave_to_goal
    )
    return (
        distance_to_hit,
        distance_along_obstacle,
        distance_leave_to_goal,
        total_distance,
    )


results = calculate_bug_route(
    (0, 0), (4, 0), (4, -1), (6, -1), (6, 0), (10, 0)
)
print(*results)
