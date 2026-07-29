def simulate_auv_navigation(total_distance, max_dive_distance):
    """
    Simulates AUV navigation using INS, SONAR, and GPS in a GPS-denied underwater environment.
    
    Parameters:
    - total_distance (meters): Total mission distance the AUV needs to travel.
    - max_dive_distance (meters): Maximum distance the AUV can travel before resurfacing for GPS correction.

    Returns:
    - None (prints navigation logs and final position error).
    """

    # Constants for error modeling
    INS_ERROR_RATE = 0.0005  # 0.05% drift per meter
    SONAR_CORRECTION = 0.5   # Reduces INS error by 50% every 1000m
    GPS_CORRECTION = 0       # Resets error to 0 when surfacing

    # Initialization
    total_error = 0
    distance_traveled = 0
    log = []

    while distance_traveled < total_distance:
        # Determine how far the AUV will travel before surfacing
        dive_distance = min(max_dive_distance, total_distance - distance_traveled)

        # INS accumulates error
        ins_error = dive_distance * INS_ERROR_RATE
        total_error += ins_error

        # SONAR applies correction every 1000m
        if dive_distance >= 1000:
            total_error *= SONAR_CORRECTION

        # Log the error before surfacing
        log.append(f"After {distance_traveled + dive_distance}m (Underwater): Position Error = {total_error:.4f}m")

        # Surface and apply GPS correction
        total_error = GPS_CORRECTION

        # Log the GPS reset
        log.append(f"After {distance_traveled + dive_distance}m (Resurfaced): GPS Reset Applied, Position Error = {total_error:.4f}m")

        # Update total distance traveled
        distance_traveled += dive_distance

    # Print log
    for entry in log:
        print(entry)

    # Print final status
    print("\nMission Complete!")
    print(f"Total Distance Traveled: {total_distance}m")
    print(f"Final Position Error: {total_error:.4f}m (GPS corrected)")

# User input
total_distance = int(input("Enter total mission distance (meters): "))
max_dive_distance = int(input("Enter max dive distance before resurfacing (meters): "))

# Run the simulation
simulate_auv_navigation(total_distance, max_dive_distance)
