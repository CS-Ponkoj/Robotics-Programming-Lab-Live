def correct_position(gps_coords, ins_displacement, wps_coords):
    """
    Computes the corrected position of the drone using sensor fusion.
    
    Parameters:
    - gps_coords: Tuple (lat, lon) from GPS
    - ins_displacement: Tuple (dx, dy) in meters from INS
    - wps_coords: Tuple (lat, lon) from Wi-Fi Positioning System (WPS)
    
    Returns:
    - Corrected latitude and longitude as a tuple (lat, lon)
    """
    
    # Define sensor reliability weights
    w_gps = 0.3   # GPS is unreliable in urban areas
    w_ins = 0.4   # INS is more reliable but drifts over time
    w_wps = 0.3   # WPS is useful in buildings
    
    # Convert INS displacement (meters) to latitude/longitude adjustments
    METERS_TO_DEGREES = 0.00001  # Approximation: 1 meter ≈ 0.00001 degrees
    
    ins_lat = gps_coords[0] + (ins_displacement[1] * METERS_TO_DEGREES)
    ins_lon = gps_coords[1] + (ins_displacement[0] * METERS_TO_DEGREES)
    
    # Compute weighted average for latitude and longitude
    final_lat = (w_gps * gps_coords[0]) + (w_ins * ins_lat) + (w_wps * wps_coords[0])
    final_lon = (w_gps * gps_coords[1]) + (w_ins * ins_lon) + (w_wps * wps_coords[1])
    
    return final_lat, final_lon

# Example Inputs
gps_coords = (37.7749, -122.4194)  # San Francisco GPS coordinates
ins_displacement = (5, 10)  # INS displacement in meters (dx = 5m, dy = 10m)
wps_coords = (37.7750, -122.4193)  # Estimated position from WPS

# Compute the corrected position
corrected_coords = correct_position(gps_coords, ins_displacement, wps_coords)

# Output results
print(f"Corrected Position: Latitude = {corrected_coords[0]:.6f}, Longitude = {corrected_coords[1]:.6f}")
