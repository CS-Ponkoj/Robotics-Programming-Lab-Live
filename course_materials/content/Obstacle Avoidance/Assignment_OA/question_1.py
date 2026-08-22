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


# TODO: Floor-5 routes to each elevator.
path_to_E_m = 0.0
path_to_E_s = 0.0

# TODO: Floor-10 routes from each elevator to the goal.
path_from_E_m_to_goal = 0.0
path_from_E_s_to_goal = 0.0

# TODO: Complete time through each elevator.
total_time_via_E_m = 0.0
total_time_via_E_s = 0.0

# TODO: Choose the smaller complete time and matching label.
best_option = ""
best_time = 0.0

