import numpy as np


def analyze_vfh(
    seed_readings, fill_start, fill_end, goal_direction,
    search_half_width, probe_angle,
):
    lidar_readings = dict(seed_readings)
    for angle in range(fill_start, fill_end + 1):
        lidar_readings[angle] = 10 + 2 * np.sin(np.radians(angle))

    primary_polar_histogram = {
        angle: 1 / reading**2
        for angle, reading in lidar_readings.items()
    }
    angle_range = list(range(
        goal_direction - search_half_width,
        goal_direction + search_half_width + 1,
    ))
    optimal_sector_angle = min(
        angle_range,
        key=lambda angle: primary_polar_histogram[angle],
    )
    optimal_sector_value = primary_polar_histogram[optimal_sector_angle]
    return (
        len(lidar_readings),
        len(angle_range),
        primary_polar_histogram[probe_angle],
        optimal_sector_angle,
        optimal_sector_value,
    )


seed_readings = {0: 10, 1: 8, 2: 12, 358: 7, 359: 9}
results = analyze_vfh(seed_readings, 3, 357, 90, 10, 90)
print(*results)
