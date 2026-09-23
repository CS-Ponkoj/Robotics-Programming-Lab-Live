import math

def calculate_distance(point_1, point_2):
    return math.hypot(point_2[0] - point_1[0], point_2[1] - point_1[1])


def calculate_bug_route(start, hit, corner_a, corner_b, leave, goal):
    distance_to_obstacle = calculate_distance(start, hit)
    distance_along_obstacle = (
        calculate_distance(hit, corner_a)
        + calculate_distance(corner_a, corner_b)
        + calculate_distance(corner_b, leave)
    )
    distance_from_obstacle_to_goal = calculate_distance(leave, goal)
    total_path_length = (
        distance_to_obstacle
        + distance_along_obstacle
        + distance_from_obstacle_to_goal
    )
    return (
        distance_to_obstacle,
        distance_along_obstacle,
        distance_from_obstacle_to_goal,
        total_path_length,
    )


results = calculate_bug_route(
    (0, 0), (4, 0), (4, -1), (6, -1), (6, 0), (10, 0)
)
print(*results)
