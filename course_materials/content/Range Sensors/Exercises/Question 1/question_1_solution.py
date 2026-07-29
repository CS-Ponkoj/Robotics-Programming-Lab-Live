import random
import time

# Define sensor detection thresholds (meters)
ULTRASONIC_THRESHOLD = 0.5   # Ultrasonic detects obstacles within 50 cm
LIDAR_THRESHOLD = 5.0        # LIDAR detects obstacles up to 5m
TOF_THRESHOLD = 2.0          # ToF sensor detects fast-moving obstacles within 2m
IR_THRESHOLD = 0.3           # IR sensor detects dark/reflective objects within 30 cm

# Robot movement parameters
ROBOT_SPEED = 1.0            # Robot moves at 1 meter per second
CHECK_INTERVAL = 0.2         # Robot checks for obstacles every 0.2 seconds
TOTAL_DISTANCE = 5.0         # Robot must travel 5 meters

# Function to simulate sensor readings (adjusted for fewer obstacles)
def get_sensor_readings():
    return {
        "Ultrasonic": random.uniform(0.4, 3.0),  # Increased lower range to avoid too many obstacles
        "LIDAR": random.uniform(3.0, 6.0),       # LIDAR now rarely detects obstacles
        "ToF": random.uniform(1.5, 4.0),         # ToF is now less likely to trigger a stop
        "IR": random.uniform(0.2, 1.5)           # IR sensor still detects some close obstacles
    }

# Function to determine if an obstacle is detected
def obstacle_detected(sensor_readings):
    return (
        sensor_readings["Ultrasonic"] <= ULTRASONIC_THRESHOLD or
        sensor_readings["LIDAR"] <= LIDAR_THRESHOLD or
        sensor_readings["ToF"] <= TOF_THRESHOLD or
        sensor_readings["IR"] <= IR_THRESHOLD
    )

# Simulate robot navigation
def navigate_warehouse():
    distance_covered = 0.0

    print("Starting warehouse navigation...\n")

    while distance_covered < TOTAL_DISTANCE:
        # Simulate sensor readings
        sensor_readings = get_sensor_readings()

        # Display sensor readings
        print(f"Sensor Readings: {sensor_readings}")

        # Check for obstacles
        if obstacle_detected(sensor_readings):
            print("Obstacle detected! Stopping and turning...\n")
            time.sleep(1)  # Simulate stopping and turning
        else:
            distance_covered += ROBOT_SPEED * CHECK_INTERVAL
            print(f"No obstacles detected. Moving forward... ({distance_covered:.2f}m covered)\n")

        time.sleep(CHECK_INTERVAL)  # Simulate time delay for next sensor check

    print("Robot has successfully reached the destination!")

# Run the simulation
navigate_warehouse()
