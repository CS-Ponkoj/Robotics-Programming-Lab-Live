# if the scipy package is not installed
# !pip install scipy

from scipy.spatial import distance

# Constants
robot_speed = 1  # m/s
safety_margin = 0.5  # meters
obstacle_detection_range = 2  # meters
main_elevator_wait = 30  # seconds
service_elevator_wait = 10  # seconds
main_elevator_speed = 1/15  # floors per second
service_elevator_speed = 1/20  # floors per second
floors_to_travel = 10 - 5  # From 5th to 10th floor

# Points in meters on the 5th floor's plan
S = (5, 5)
G = (25, 30)
E_m = (10, 5)
E_s = (6, 15)
barrier_start = (8, 5)
barrier_end = (8, 10)
movable_obstacle = (7, 7)  # Simulated position of movable obstacle detected on path

# Calculate straight-line paths to elevators, considering barriers and safety margin
def straight_line_distance_with_barrier(start, end, barrier_start, barrier_end, safety_margin):
    """
    Calculate the straight-line distance from start to end, considering a barrier.
    This simplistic model will add the safety margin to the detour length.
    """
    # Check if the barrier affects the straight line path (simple check for this scenario)
    if start[0] < barrier_start[0] < end[0] or start[0] < barrier_end[0] < end[0]:
        # Calculate detour distance
        detour_distance = distance.euclidean(start, barrier_start) + \
                          distance.euclidean(barrier_start, barrier_end) + \
                          distance.euclidean(barrier_end, end) + \
                          2 * safety_margin  # Adding safety margin for barrier avoidance
    else:
        detour_distance = distance.euclidean(start, end)
    return detour_distance

# Paths to elevators considering barrier
path_to_E_m = straight_line_distance_with_barrier(S, E_m, barrier_start, barrier_end, safety_margin)
path_to_E_s = straight_line_distance_with_barrier(S, E_s, barrier_start, barrier_end, safety_margin)

# Time to reach each elevator
time_to_E_m = path_to_E_m / robot_speed + main_elevator_wait + (floors_to_travel / main_elevator_speed)
time_to_E_s = path_to_E_s / robot_speed + service_elevator_wait + (floors_to_travel / service_elevator_speed)

# Detecting movable obstacle (assuming always in the way for this calculation)
# Adding a detour, simplistic model: direct line to obstacle + detour radius + line to elevator
# This is a simplified way to account for a small detour, actual path planning would be more complex
if distance.euclidean(S, movable_obstacle) < obstacle_detection_range:
    detour_length = obstacle_detection_range + 2 * np.pi * (safety_margin / 2)  # Half-circle around the obstacle
    # Adjust time calculations to include detour
    time_to_E_m += detour_length / robot_speed
    time_to_E_s += detour_length / robot_speed

# Choose the best option based on total time
best_option = "Main Elevator" if time_to_E_m < time_to_E_s else "Service Elevator"
best_time = min(time_to_E_m, time_to_E_s)

print(path_to_E_m, path_to_E_s, time_to_E_m, time_to_E_s, best_option, best_time)


# Answere
# The shortest path length to the main elevator (Em) considering the barrier and safety margin is approximately 14.39 meters. The adjusted time to reach the 10th floor using the main elevator, including the wait and travel times and the detour for the movable obstacle, is about 119.39 seconds.

# The shortest path length to the service elevator (Es) considering the barrier and safety margin is approximately 10.05 meters. The adjusted time to reach the 10th floor using the service elevator, including the wait and travel times and the detour for the movable obstacle, is about 120.05 seconds.
