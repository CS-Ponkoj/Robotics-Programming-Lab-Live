def check_stability(legs, cog):
    """
    Function to check if the robot's Center of Gravity (CoG) is inside
    the boundary formed by the four leg positions.

    Parameters:
    legs - List of (x, y) tuples representing the four leg positions.
    cog - Tuple (x, y) representing the Center of Gravity.

    Returns:
    "Stable" if the CoG is inside the boundary, otherwise "Unstable".
    """

    # Extract min and max x, y values to define the boundary
    min_x = min(leg[0] for leg in legs)
    max_x = max(leg[0] for leg in legs)
    min_y = min(leg[1] for leg in legs)
    max_y = max(leg[1] for leg in legs)

    # Extract CoG position
    cog_x, cog_y = cog

    # Check if CoG is within the boundary
    if min_x <= cog_x <= max_x and min_y <= cog_y <= max_y:
        return "Stable"
    else:
        return "Unstable"


# Define the four leg positions (x, y)
legs = [
    (1, 1),  # Front-left leg
    (4, 1),  # Front-right leg
    (4, 4),  # Back-right leg
    (1, 4)   # Back-left leg
]

# Define the robot's Center of Gravity (CoG)
cog = (2.5, 2.5)  # Change this to test different positions

# Check stability and print result
result = check_stability(legs, cog)
print("Robot Stability:", result)
