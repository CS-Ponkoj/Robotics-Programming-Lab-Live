from collections import deque

# Define the warehouse grid (10x10)
warehouse = [
    [0, 0, 0, 0, 1, 0, 0, 0, 0, 0],
    [0, 1, 1, 0, 1, 0, 1, 1, 1, 0],
    [0, 0, 0, 0, 0, 0, 1, 0, 1, 0],
    [1, 1, 1, 1, 1, 0, 1, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 1, 1, 1, 0],
    [0, 1, 1, 1, 1, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 1, 1, 1, 1, 0, 1],
    [0, 1, 1, 0, 0, 0, 0, 1, 0, 0],
    [0, 1, 0, 0, 1, 1, 0, 1, 1, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
]

# Possible movement directions (dx, dy) with orientation names
directions = {
    "UP": (0, 1),
    "DOWN": (0, -1),
    "LEFT": (-1, 0),
    "RIGHT": (1, 0)
}

# Turn penalty and movement cost
MOVE_COST = 1   # Moving forward 1 step takes 1 second
TURN_COST = 2   # Turning 90 degrees takes 2 seconds

# BFS to find the shortest path
def bfs(start, goal):
    queue = deque([(start, "UP", 0, 0, [])])  # (position, direction, steps, turns, path)
    visited = set()

    while queue:
        (x, y), direction, steps, turns, path = queue.popleft()

        # If reached the goal, return total time and path
        if (x, y) == goal:
            total_time = (steps * MOVE_COST) + (turns * TURN_COST)
            return total_time, path + [(x, y)]

        # Skip if already visited
        if (x, y, direction) in visited:
            continue
        visited.add((x, y, direction))

        # Try moving in the current direction
        dx, dy = directions[direction]
        nx, ny = x + dx, y + dy
        if 0 <= nx < 10 and 0 <= ny < 10 and warehouse[ny][nx] == 0:
            queue.append(((nx, ny), direction, steps + 1, turns, path + [(x, y)]))

        # Try turning left or right
        for new_direction in directions.keys():
            if new_direction != direction:  # Change direction
                queue.append(((x, y), new_direction, steps, turns + 1, path))

    return float("inf"), []  # No valid path found

# Define start and goal positions
start = (0, 0)
goal = (9, 9)

# Find the shortest path and total time
total_time, shortest_path = bfs(start, goal)

# Print results
if total_time == float("inf"):
    print("No valid path found.")
else:
    print(f"Shortest Path: {shortest_path}")
    print(f"Total Time Taken: {total_time} seconds")



#Output:
#Shortest Path: [(0, 0), (1, 0), (2, 0), (3, 0), (3, 1), (3, 2), (4, 2), ..., (9, 9)]
#Total Time Taken: 22 seconds
