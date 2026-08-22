import math


robot_speed = 1.0
service_detour_radius = 1.0
main_elevator_wait = 30.0
service_elevator_wait = 10.0
main_seconds_per_floor = 15.0
service_seconds_per_floor = 20.0
floors_to_travel = 5

S = (5.0, 5.0)
G = (25.0, 30.0)
E_m = (10.0, 5.0)
E_s = (6.0, 15.0)
M1 = (7.5, 4.5)
M2 = (8.5, 4.5)


def calculate_distance(point_1, point_2):
    return math.hypot(point_2[0] - point_1[0], point_2[1] - point_1[1])


def route_length(points):
    return sum(
        calculate_distance(points[index], points[index + 1])
        for index in range(len(points) - 1)
    )


path_to_E_m = route_length([S, M1, M2, E_m])
path_to_E_s = calculate_distance(S, E_s) + math.pi * service_detour_radius

path_from_E_m_to_goal = calculate_distance(E_m, G)
path_from_E_s_to_goal = calculate_distance(E_s, G)

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

print(
    path_to_E_m,
    path_to_E_s,
    path_from_E_m_to_goal,
    path_from_E_s_to_goal,
    total_time_via_E_m,
    total_time_via_E_s,
    best_option,
    best_time,
)
