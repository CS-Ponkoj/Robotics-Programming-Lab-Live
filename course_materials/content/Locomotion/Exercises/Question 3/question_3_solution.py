def calculate_energy(distance, terrain, speed):
    """
    Calculates the total energy consumption of a tracked robot based on:
    - Distance traveled (meters)
    - Terrain type (Flat, Rocky, Muddy)
    - Speed (1, 2, or 3 m/s)
    """
    
    # Energy efficiency values (Joules per meter) based on terrain and speed
    energy_efficiency = {
        "Flat": {1: 10, 2: 15, 3: 20},
        "Rocky": {1: 20, 2: 30, 3: 40},
        "Muddy": {1: 30, 2: 45, 3: 60}
    }
    
    # Validate input
    if terrain not in energy_efficiency or speed not in energy_efficiency[terrain]:
        return "Invalid terrain or speed selection!"
    
    # Calculate energy used
    energy_used = distance * energy_efficiency[terrain][speed]
    
    return energy_used

# User input
distance = float(input("Enter distance to travel (meters): "))
terrain = input("Enter terrain type (Flat, Rocky, Muddy): ").capitalize()
speed = int(input("Enter speed (1, 2, or 3 m/s): "))

# Compute energy consumption
result = calculate_energy(distance, terrain, speed)

# Print the result
if isinstance(result, str):
    print(result)  # Error message if input is invalid
else:
    print(f"Total Energy Consumed: {result} Joules")
