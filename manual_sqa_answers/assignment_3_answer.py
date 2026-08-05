import math

from scipy.spatial import distance


robot_speed = 1
safety_margin = 0.5
obstacle_detection_range = 2
detour_radius = 1.0
main_elevator_wait = 30
service_elevator_wait = 10
main_elevator_speed = 1 / 15
service_elevator_speed = 1 / 20
floors_to_travel = 10 - 5

start = (5, 5)
main_elevator = (10, 5)
service_elevator = (6, 15)
barrier_start = (8, 5)
barrier_end = (8, 10)
movable_obstacle = (6, 6)


def straight_line_distance_with_barrier(
    route_start, route_end, obstacle_start, obstacle_end, margin
):
    """Calculate the scenario's barrier-aware route length."""
    barrier_crosses_route = (
        route_start[0] < obstacle_start[0] < route_end[0]
        or route_start[0] < obstacle_end[0] < route_end[0]
    )
    if barrier_crosses_route:
        return (
            distance.euclidean(route_start, obstacle_start)
            + distance.euclidean(obstacle_start, obstacle_end)
            + distance.euclidean(obstacle_end, route_end)
            + 2 * margin
        )
    return distance.euclidean(route_start, route_end)


path_to_E_m = straight_line_distance_with_barrier(
    start, main_elevator, barrier_start, barrier_end, safety_margin
)
path_to_E_s = straight_line_distance_with_barrier(
    start, service_elevator, barrier_start, barrier_end, safety_margin
)

if distance.euclidean(start, movable_obstacle) <= obstacle_detection_range:
    detour_length = math.pi * detour_radius
    path_to_E_m += detour_length
    path_to_E_s += detour_length

time_to_E_m = (
    path_to_E_m / robot_speed
    + main_elevator_wait
    + floors_to_travel / main_elevator_speed
)
time_to_E_s = (
    path_to_E_s / robot_speed
    + service_elevator_wait
    + floors_to_travel / service_elevator_speed
)

best_option = "Main Elevator" if time_to_E_m < time_to_E_s else "Service Elevator"
best_time = min(time_to_E_m, time_to_E_s)

print(path_to_E_m, path_to_E_s, time_to_E_m, time_to_E_s, best_option, best_time)
