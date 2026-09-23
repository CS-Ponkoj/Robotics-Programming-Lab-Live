import math


def calculate_distance(point_1, point_2):
    return math.hypot(point_2[0] - point_1[0], point_2[1] - point_1[1])


def route_length(points):
    return sum(
        calculate_distance(points[index], points[index + 1])
        for index in range(len(points) - 1)
    )


def evaluate_elevator_routes(
    robot_speed, service_detour_radius, main_elevator_wait,
    service_elevator_wait, main_seconds_per_floor,
    service_seconds_per_floor, floors_to_travel, start, goal,
    main_elevator, service_elevator, main_waypoints,
):
    path_to_E_m = route_length([start, *main_waypoints, main_elevator])
    path_to_E_s = (
        calculate_distance(start, service_elevator)
        + math.pi * service_detour_radius
    )
    path_from_E_m_to_goal = calculate_distance(main_elevator, goal)
    path_from_E_s_to_goal = calculate_distance(service_elevator, goal)
    total_time_via_E_m = (
        path_to_E_m / robot_speed
        + main_elevator_wait
        + floors_to_travel * main_seconds_per_floor
        + path_from_E_m_to_goal / robot_speed
    )
    total_time_via_E_s = (
        path_to_E_s / robot_speed
        + service_elevator_wait
        + floors_to_travel * service_seconds_per_floor
        + path_from_E_s_to_goal / robot_speed
    )
    if total_time_via_E_m < total_time_via_E_s:
        best_option = "Main Elevator"
        best_time = total_time_via_E_m
    else:
        best_option = "Service Elevator"
        best_time = total_time_via_E_s
    return (
        path_to_E_m, path_to_E_s, path_from_E_m_to_goal,
        path_from_E_s_to_goal, total_time_via_E_m,
        total_time_via_E_s, best_option, best_time,
    )


results = evaluate_elevator_routes(
    1.0, 1.0, 30.0, 10.0, 15.0, 20.0, 5,
    (5.0, 5.0), (25.0, 30.0), (10.0, 5.0), (6.0, 15.0),
    [(7.5, 4.5), (8.5, 4.5)],
)
print(*results)
