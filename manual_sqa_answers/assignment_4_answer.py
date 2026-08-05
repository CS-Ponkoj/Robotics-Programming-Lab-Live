import numpy as np


# Example LIDAR readings. Fill missing angles with the assignment's simulated
# sinusoidal readings.
lidar_readings = {
    0: 10,
    1: 8,
    2: 12,
    358: 7,
    359: 9,
}

for angle in range(3, 358):
    lidar_readings[angle] = 10 + 2 * np.sin(np.radians(angle))

# VFH obstacle density is inversely proportional to squared distance.
primary_polar_histogram = {
    angle: 1 / reading**2 for angle, reading in lidar_readings.items()
}

goal_direction = 90
angle_range = list(range(goal_direction - 10, goal_direction + 11))
optimal_sector = min(
    angle_range,
    key=lambda angle: primary_polar_histogram.get(angle, float("inf")),
)

optimal_sector_angle = optimal_sector
optimal_sector_value = primary_polar_histogram[optimal_sector]

print(optimal_sector_angle, optimal_sector_value)
