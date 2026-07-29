import math
from queue import PriorityQueue

# Heuristic function (Manhattan distance)
def heuristic(a, b):
    """
    Calculate the Manhattan distance between points a and b.
    """
    return abs(a[0] - b[0]) + abs(a[1] - b[1])

# A* Algorithm
def a_star(grid, start, goal):
    """
    A* algorithm to find the shortest path in a 2D grid.

    Args:
    - grid (list of lists): 2D grid where 0 is a walkable cell and 1 is an obstacle.
    - start (tuple): Starting coordinates (x, y).
    - goal (tuple): Goal coordinates (x, y).

    Returns:
    - list: List of tuples representing the path from start to goal.
    """
    rows, cols = len(grid), len(grid[0])
    open_list = PriorityQueue()
    open_list.put((0, start))  # Add the start node to the open list
    came_from = {}
    g_score = {start: 0}
    f_score = {start: heuristic(start, goal)}

    while not open_list.empty():
        # Step 1: Get the current node with the lowest f_score
        current = open_list.get()[1]

        # If we reached the goal, reconstruct the path
        if current == goal:
            path = []
            while current in came_from:
                path.append(current)
                current = came_from[current]
            path.append(start)  # Add the start to complete the path
            return path[::-1]  # Return the reversed path

        # Explore the neighbors of the current node
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            neighbor = (current[0] + dx, current[1] + dy)

            # Ensure the neighbor is within grid bounds and not an obstacle
            if 0 <= neighbor[0] < rows and 0 <= neighbor[1] < cols and grid[neighbor[0]][neighbor[1]] == 0:
                # Step 2: Calculate tentative g_score for the neighbor
                tentative_g_score = g_score[current] + 1  # Each move costs 1

                # TODO: If the new path to the neighbor is shorter, update its g_score and f_score
                # Add it to the open list if it's not there, or update its priority if it is

                # YOUR CODE HERE

    return None  # Return None if no path is found

# Example 2D grid (0 is walkable, 1 is obstacle)
grid = [
    [0, 1, 0, 0, 0],
    [0, 1, 0, 1, 0],
    [0, 0, 0, 1, 0],
    [0, 1, 0, 0, 0],
    [0, 0, 0, 1, 0]
]

start = (0, 0)
goal = (4, 4)

# Run the A* algorithm and display the path
path = a_star(grid, start, goal)

if path:
    print(f"Path from {start} to {goal}: {path}")
else:
    print(f"No path found from {start} to {goal}.")
