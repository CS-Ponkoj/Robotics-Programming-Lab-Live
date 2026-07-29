import numpy as np

# LIDAR readings are given in a dictionary format for every degree.
# Only a subset is given here for the example, and others would be filled in similarly.
lidar_readings = {
    0: 10,
    1: 8,
    2: 12,
    # ... (other readings would be here)
    358: 7,
    359: 9
}

# To simulate a complete set of readings, we'll fill in the missing data with arbitrary values.
# In a real-world scenario, these would be actual LIDAR readings.
# For simplicity in this example, we'll use a sinusoidal function to generate values.
for angle in range(3, 358):
    lidar_readings[angle] = 10 + 2 * np.sin(np.radians(angle))

# Calculate the primary polar histogram by assigning a value to each sector
# that corresponds to the density of obstacles.
# Here, the obstacle density value is inversely proportional to the square of the distance.
primary_polar_histogram = {angle: 1 / distance**2 for angle, distance in lidar_readings.items()}

# Find the sector with the lowest obstacle density value towards the goal direction (90 degrees)
# We will consider sectors close to 90 degrees for the goal direction.
# In a real VFH implementation, we would also consider the width of the robot and possible safety margins.

# Define the goal direction
goal_direction = 90

# Find the optimal sector
# For this example, we will look for the minimum value in the histogram around the goal direction
# considering a range of +/- 10 degrees from the goal direction for simplicity.
angle_range = list(range(goal_direction - 10, goal_direction + 11))
optimal_sector = min(angle_range, key=lambda x: primary_polar_histogram.get(x, float('inf')))

# Get the angle and value of the optimal sector
optimal_sector_angle = optimal_sector
optimal_sector_value = primary_polar_histogram[optimal_sector]

print(optimal_sector_angle, optimal_sector_value)
