def simulate_robot_navigation(total_distance, env_distribution):
    """
    Simulates a delivery robot navigating a smart city with Hybrid Navigation and Adaptive Locomotion.
    
    Parameters:
    - total_distance (meters): Total distance for the delivery.
    - env_distribution (dict): Percentage of distance in each environment (Outdoor, Urban Canyon, Indoor, Rough Terrain).
    
    Returns:
    - None (prints a log of navigation transitions and final time/energy usage).
    """

    # Define navigation methods & locomotion modes for each environment
    environments = {
        "Outdoor Streets": {"speed": 1.5, "energy_per_meter": 5, "navigation": "GPS + DGPS", "mode": "Wheeled"},
        "Urban Canyons": {"speed": 1.5, "energy_per_meter": 5, "navigation": "WPS + INS", "mode": "Wheeled"},
        "Indoor Areas": {"speed": 0.8, "energy_per_meter": 8, "navigation": "INS + LIDAR", "mode": "Legged"},
        "Rough Terrain": {"speed": 0.8, "energy_per_meter": 8, "navigation": "INS + LIDAR", "mode": "Legged"},
    }

    # Initialize tracking variables
    total_time = 0
    total_energy = 0
    log = []

    # Process each environment segment
    for env, percent in env_distribution.items():
        distance = (percent / 100) * total_distance
        speed = environments[env]["speed"]
        energy_per_meter = environments[env]["energy_per_meter"]
        navigation = environments[env]["navigation"]
        mode = environments[env]["mode"]

        # Compute time & energy usage
        time_taken = distance / speed
        energy_used = distance * energy_per_meter

        # Update totals
        total_time += time_taken
        total_energy += energy_used

        # Log results
        log.append(f"Environment: {env}, Distance: {distance:.1f}m")
        log.append(f"   → Navigation: {navigation}, Locomotion: {mode}")
        log.append(f"   → Time Taken: {time_taken:.2f}s, Energy Used: {energy_used:.2f}J\n")

    # Print journey log
    for entry in log:
        print(entry)

    # Print final results
    print("Final Delivery Summary:")
    print(f"Total Distance Covered: {total_distance} meters")
    print(f"Total Time Taken: {total_time:.2f} seconds")
    print(f"Total Energy Consumed: {total_energy:.2f} Joules")

# User Inputs
total_distance = int(input("Enter total delivery distance (meters): "))
env_distribution = {
    "Outdoor Streets": float(input("Enter % of journey in Outdoor Streets: ")),
    "Urban Canyons": float(input("Enter % of journey in Urban Canyons: ")),
    "Indoor Areas": float(input("Enter % of journey Indoors: ")),
    "Rough Terrain": float(input("Enter % of journey in Rough Terrain: ")),
}

# Validate that percentages add up to 100
if sum(env_distribution.values()) != 100:
    print("Error: The total percentage must add up to 100%!")
else:
    # Run the simulation
    simulate_robot_navigation(total_distance, env_distribution)
