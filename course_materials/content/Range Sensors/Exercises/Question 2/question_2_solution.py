import random
import time

# Grid size
GRID_SIZE = 10

# Define sensor detection thresholds (meters)
ULTRASONIC_THRESHOLD = 1.5  # Detects objects within 1.5m
LIDAR_THRESHOLD = 6.5       # Detects objects within 6.5m
TOF_THRESHOLD = 3.5         # Detects fast-moving obstacles within 3.5m
IR_THRESHOLD = 1.5          # Detects dark/reflective obstacles within 1.5m

# Movement directions: Right, Left, Up, Down (randomized each step)
DIRECTIONS = [
    (0, 1),   # Right
    (0, -1),  # Left
    (-1, 0),  # Up
    (1, 0)    # Down
]

# Initialize 10x10 grid with empty spaces
grid = [["." for _ in range(GRID_SIZE)] for _ in range(GRID_SIZE)]

# Robot starts at (9,0) (bottom-left of grid)
robot_x, robot_y = GRID_SIZE - 1, 0
grid[robot_x][robot_y] = "R"  # Mark the robot's starting position

# List to track obstacle positions
obstacle_positions = []

# Function to simulate sensor readings (ensuring obstacles are spaced out)
def get_sensor_readings():
    return {
        "Ultrasonic": random.uniform(2.5, 5.5),  # Reduced max to increase obstacle detection
        "LIDAR": random.uniform(5.0, 9.0),      
        "ToF": random.uniform(3.5, 8.0),
        "IR": random.uniform(2.0, 5.0)
    }

# Function to determine if an obstacle is detected
def obstacle_detected(sensor_readings):
    return (
        sensor_readings["Ultrasonic"] <= ULTRASONIC_THRESHOLD or
        sensor_readings["LIDAR"] <= LIDAR_THRESHOLD or
        sensor_readings["ToF"] <= TOF_THRESHOLD or
        sensor_readings["IR"] <= IR_THRESHOLD
    )

# Function to check if a new obstacle is at least 3 grid spaces away from existing obstacles
def is_valid_obstacle_position(new_x, new_y):
    for ox, oy in obstacle_positions:
        if abs(new_x - ox) < 3 and abs(new_y - oy) < 3:
            return False  # Too close to an existing obstacle
    return True

# Function to display the grid with robot position
def print_grid():
    for row in grid:
        print(" ".join(row))
    print("\n")

# Robot navigation function
def navigate_grid():
    global robot_x, robot_y
    
    print("Starting robot navigation...\n")
    print_grid()

    steps = 0
    max_steps = GRID_SIZE * GRID_SIZE  # Allow enough steps for full exploration

    while steps < max_steps:
        moved = False  # Track if the robot successfully moved

        random.shuffle(DIRECTIONS)  # Shuffle movement directions for randomness

        for dx, dy in DIRECTIONS:  # Try moving in a random order
            new_x, new_y = robot_x + dx, robot_y + dy

            # Check if movement is within grid boundaries and not an obstacle
            if 0 <= new_x < GRID_SIZE and 0 <= new_y < GRID_SIZE and grid[new_x][new_y] == ".":
                # Simulate sensor readings
                sensor_readings = get_sensor_readings()

                # Check for obstacles (now they must be at least 3 spaces apart)
                if obstacle_detected(sensor_readings) and random.random() > 0.5 and is_valid_obstacle_position(new_x, new_y):
                    print(f"🚧 Obstacle detected at ({new_x}, {new_y}) → Marking 'X'...\n")
                    grid[new_x][new_y] = "X"  # Mark obstacle
                    obstacle_positions.append((new_x, new_y))  # Track obstacle position
                else:
                    # Move robot forward
                    grid[robot_x][robot_y] = "."  # Clear old position
                    robot_x, robot_y = new_x, new_y
                    grid[robot_x][robot_y] = "R"  # Update new position
                    print(f"✅ Moving to ({robot_x}, {robot_y})...\n")
                    moved = True
                    break  # Stop checking directions since movement was successful

        if not moved:
            print("❌ No valid moves left. Stopping exploration.\n")
            break  # Stop simulation if the robot is completely trapped

        steps += 1
        print_grid()
        time.sleep(0.3)

    print("🏁 Robot has finished exploring the area!\nFinal Map:")
    print_grid()

# Run the simulation
navigate_grid()
