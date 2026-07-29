import numpy as np

# Constants
WHEEL_DIAMETER = 0.3  # meters (example value)
WHEEL_CIRCUMFERENCE = np.pi * WHEEL_DIAMETER  # meters
ENCODER_TICKS_PER_REVOLUTION = 1000  # example value
DRIFT_PERCENTAGE = 0.5 / 100  # 0.5% drift
AVERAGE_SPEED = 1  # m/s
PATH_LENGTH = 100  # meters (from start to target in a straight line for simplicity)

def calculate_odometry_drift(path_length, wheel_circumference, encoder_ticks_per_revolution, drift_percentage, average_speed):
    # Calculate the number of wheel revolutions for the entire path
    total_revolutions = path_length / wheel_circumference

    # Calculate the total encoder ticks for the path
    total_encoder_ticks = total_revolutions * encoder_ticks_per_revolution

    # Calculate the drift per tick
    drift_per_tick = drift_percentage * wheel_circumference / encoder_ticks_per_revolution

    # Total drift for the entire path
    total_drift = drift_per_tick * total_encoder_ticks

    # Time taken to travel the path
    time_taken = path_length / average_speed

    return total_drift, time_taken

# Calculate total drift and time taken
total_drift, time_taken = calculate_odometry_drift(PATH_LENGTH, WHEEL_CIRCUMFERENCE, ENCODER_TICKS_PER_REVOLUTION, DRIFT_PERCENTAGE, AVERAGE_SPEED)
print(f"Total Drift Error: {total_drift:.2f} meters over a distance of {PATH_LENGTH} meters")
print(f"Time Taken: {time_taken:.2f} seconds")

