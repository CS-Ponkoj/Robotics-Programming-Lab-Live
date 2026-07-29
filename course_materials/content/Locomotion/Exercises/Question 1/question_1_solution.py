import math

# Constants
warehouse_length = 10  # meters
warehouse_width = 10   # meters
robot_speed = 1.5  # max speed in m/s
turn_penalty_differential = 2  # seconds (in-place rotation time)
turn_penalty_ackermann = 1  # seconds (due to turning radius)
turn_penalty_omni = 0.5  # seconds (quick turn in any direction)
obstacle_penalty = 1  # seconds (time taken to re-route around obstacle)

# Function to calculate travel time based on locomotion type
def calculate_travel_time(locomotion_type):
    straight_distance = warehouse_length / 2  # Before the turn
    post_turn_distance = warehouse_length / 2  # After the turn
    
    # Base travel time (without turns or obstacles)
    travel_time = (straight_distance + post_turn_distance) / robot_speed
    
    # Add penalties based on locomotion type
    if locomotion_type == "Differential Drive":
        travel_time += turn_penalty_differential + obstacle_penalty
    elif locomotion_type == "Ackermann Steering":
        travel_time += turn_penalty_ackermann + obstacle_penalty
    elif locomotion_type == "Omnidirectional Drive":
        travel_time += turn_penalty_omni + obstacle_penalty
    else:
        raise ValueError("Invalid locomotion type")

    return travel_time

# Calculate and print travel times for each system
systems = ["Differential Drive", "Ackermann Steering", "Omnidirectional Drive"]

for system in systems:
    time_taken = calculate_travel_time(system)
    print(f"{system}: Total Time = {time_taken:.2f} seconds")
