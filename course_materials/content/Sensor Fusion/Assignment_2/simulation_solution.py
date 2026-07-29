import numpy as np
import matplotlib.pyplot as plt

# Maze Representation (0: Empty, 1: Treasure, -1: Obstacle)
maze = np.array([
    [0, 1, -1, 0, 1],
    [0, -1, 0, 1, 0],
    [1, 0, 1, -1, 0],
    [0, 1, 0, 1, 0],
    [-1, 0, 0, 1, 1]
])

# A* Algorithm for Pathfinding (simplified for the example)
def heuristic(cell, goal):
    return abs(cell[0] - goal[0]) + abs(cell[1] - goal[1])

def get_neighbors(cell):
    directions = [(0, 1), (1, 0), (0, -1), (-1, 0)]
    result = []
    for d in directions:
        neighbor = (cell[0] + d[0], cell[1] + d[1])
        if 0 <= neighbor[0] < maze.shape[0] and 0 <= neighbor[1] < maze.shape[1]:
            result.append(neighbor)
    return result

def a_star(start, goal):
    open_set = {start}
    came_from = {}
    g_score = {cell: float('inf') for cell in np.ndindex(maze.shape)}
    g_score[start] = 0
    f_score = {cell: float('inf') for cell in np.ndindex(maze.shape)}
    f_score[start] = heuristic(start, goal)

    while open_set:
        current = min(open_set, key=lambda cell: f_score[cell])
        if current == goal:
            path = []
            while current in came_from:
                path.append(current)
                current = came_from[current]
            return path[::-1]

        open_set.remove(current)
        for neighbor in get_neighbors(current):
            if maze[neighbor] == -1:  # Obstacle
                continue
            tentative_g_score = g_score[current] + 1
            if tentative_g_score < g_score[neighbor]:
                came_from[neighbor] = current
                g_score[neighbor] = tentative_g_score
                f_score[neighbor] = tentative_g_score + heuristic(neighbor, goal)
                open_set.add(neighbor)

    return []

# Define Start and End Points
start, goal = (0, 0), (4, 4)

# Run Pathfinding
path = a_star(start, goal)

# Visualization
plt.imshow(maze, cmap='viridis')
plt.scatter([p[1] for p in path], [p[0] for p in path], c='red')
plt.scatter(start[1], start[0], c='green')
plt.scatter(goal[1], goal[0], c='blue')
plt.show()
