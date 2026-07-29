def correct_gps_with_dgps(car_gps, ref_true, ref_measured):
    """
    Computes the corrected GPS position of an autonomous car using DGPS.
    
    Parameters:
    - car_gps: Tuple (lat, lon) representing the car's raw GPS position.
    - ref_true: Tuple (lat, lon) representing the reference station's true position.
    - ref_measured: Tuple (lat, lon) representing the reference station's GPS-measured position.
    
    Returns:
    - Corrected car position as a tuple (lat, lon).
    """

    # Compute the GPS error at the reference station
    gps_error_lat = ref_measured[0] - ref_true[0]
    gps_error_lon = ref_measured[1] - ref_true[1]

    # Apply the same error correction to the car's GPS position
    corrected_lat = car_gps[0] - gps_error_lat
    corrected_lon = car_gps[1] - gps_error_lon

    return corrected_lat, corrected_lon

# Example Inputs
car_gps = (37.7749, -122.4194)  # Car's raw GPS position (San Francisco)
ref_true = (37.7750, -122.4193)  # DGPS reference station's true position
ref_measured = (37.7753, -122.4190)  # Measured position (simulating GPS error)

# Compute corrected car position
corrected_position = correct_gps_with_dgps(car_gps, ref_true, ref_measured)

# Output results
print(f"Corrected Car Position: Latitude = {corrected_position[0]:.6f}, Longitude = {corrected_position[1]:.6f}")
