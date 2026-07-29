# Debugging version with extra print statements
def correct_position(initial_position, ins_displacement, wps_position, environment):
    """
    Computes the corrected position of a robot using Hybrid Navigation.
    """

    # Validate input
    if environment not in ["Indoor", "Outdoor"]:
        return "Invalid environment type! Choose 'Indoor' or 'Outdoor'."

    # Define sensor reliability weights
    if environment == "Outdoor":
        w_primary = 0.5  # GPS is the primary source
        w_ins = 0.3      # INS is secondary
        primary_lat, primary_lon = initial_position  # Use GPS
    else:  # Indoor environment
        w_primary = 0.2  # WPS is the primary source
        w_ins = 0.3      # INS is secondary
        primary_lat, primary_lon = wps_position  # Use WPS

    # Convert INS displacement (meters) to latitude/longitude adjustments
    METERS_TO_DEGREES = 0.00001  # Approximation: 1 meter ≈ 0.00001 degrees
    
    ins_lat = initial_position[0] + (ins_displacement[1] * METERS_TO_DEGREES)
    ins_lon = initial_position[1] + (ins_displacement[0] * METERS_TO_DEGREES)

    # Print intermediate debug values
    print(f"Initial GPS Position: {initial_position}")
    print(f"INS Displacement (dx, dy): {ins_displacement}")
    print(f"INS Adjusted Position: Latitude = {ins_lat:.6f}, Longitude = {ins_lon:.6f}")
    print(f"WPS Position: {wps_position}")
    print(f"Environment: {environment}")

    # Compute weighted final position
    final_lat = (w_primary * primary_lat) + (w_ins * ins_lat)
    final_lon = (w_primary * primary_lon) + (w_ins * ins_lon)

    # Print final computed position before returning
    print(f"Final Computed Position: Latitude = {final_lat:.6f}, Longitude = {final_lon:.6f}")

    return final_lat, final_lon

# Example Inputs
initial_position = (37.7749, -122.4194)  # GPS position (San Francisco)
ins_displacement = (5, 10)  # INS displacement in meters (dx = 5m, dy = 10m)
wps_position = (37.7750, -122.4193)  # Estimated position from WPS

# User Input for environment type
environment = input("Enter environment type (Indoor/Outdoor): ").capitalize()

# Compute corrected position
corrected_position = correct_position(initial_position, ins_displacement, wps_position, environment)

# Output results
if isinstance(corrected_position, str):
    print(corrected_position)  # Error message for invalid input
else:
    print(f"Corrected Position: Latitude = {corrected_position[0]:.6f}, Longitude = {corrected_position[1]:.6f}")
