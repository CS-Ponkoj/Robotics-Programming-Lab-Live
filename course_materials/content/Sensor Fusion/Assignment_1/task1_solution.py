import numpy as np
import matplotlib.pyplot as plt
import heapq

# Constants for the grid size and start/target positions
GRID_SIZE = 100
START = (10, 10)
TARGET = (90, 90)
# Sample obstacles in the environment
OBSTACLES = [(40, 40), (50, 50), (60, 60)]

# Function to plot the grid, obstacles, start, target, and path
def plot_grid(grid, path):
    fig, ax = plt.subplots(figsize=(10, 10))
    ax.imshow(grid, cmap='Greys', interpolation='nearest')
    # Plot each point in the path
    for y, x in path:
        ax.text(x, y, '•', ha='center', va='center', color='blue')
    # Mark the start and target positions
    ax.text(START[1], START[0], 'S', ha='center', va='center', color='green')
    ax.text(TARGET[1], TARGET[0], 'T', ha='center', va='center', color='red')
    plt.show()

# Heuristic function for A* (Euclidean distance)
def heuristic(a, b):
    return np.linalg.norm(np.array(a) - np.array(b))

# A* search algorithm
def a_star_search(grid, start, goal):
    # Movement vectors for 4-directional movement
    neighbors = [(0, 1), (1, 0), (0, -1), (-1, 0)]
    close_set = set()  # Set to keep track of visited nodes
    came_from = {}  # Map each node to its parent
    gscore = {start: 0}  # Cost from start to current node
    fscore = {start: heuristic(start, goal)}  # Estimated cost from start to goal through current node
    oheap = []  # Open heap for exploring nodes

    heapq.heappush(oheap, (fscore[start], start))
    
    while oheap:
        # Pop the node with the lowest fscore
        current = heapq.heappop(oheap)[1]

        # If the goal is reached, reconstruct and return the path
        if current == goal:
            path = []
            while current in came_from:
                path.append(current)
                current = came_from[current]
            return path[::-1]  # Return reversed path

        close_set.add(current)
        # Explore neighbors
        for i, j in neighbors:
            neighbor = current[0] + i, current[1] + j            
            tentative_g_score = gscore[current] + heuristic(current, neighbor)  # Tentative gscore for neighbor
            
            # Check bounds and if neighbor is not an obstacle
            if 0 <= neighbor[0] < grid.shape[0] and 0 <= neighbor[1] < grid.shape[1] and grid[neighbor[0]][neighbor[1]] != 1:
                # If neighbor is already visited with a lower gscore, skip
                if neighbor in close_set and tentative_g_score >= gscore.get(neighbor, 0):
                    continue
                
                # If this path to neighbor is better, record it
                if tentative_g_score < gscore.get(neighbor, 0) or neighbor not in [i[1] for i in oheap]:
                    came_from[neighbor] = current
                    gscore[neighbor] = tentative_g_score
                    fscore[neighbor] = tentative_g_score + heuristic(neighbor, goal)
                    heapq.heappush(oheap, (fscore[neighbor], neighbor))
                
    return False  # Return False if no path is found

# Main function to run the simulation
def main():
    grid = np.zeros((GRID_SIZE, GRID_SIZE), dtype=np.int8)  # Initialize grid
    for obs in OBSTACLES:  # Add obstacles to the grid
        grid[obs] = 1

    path = a_star_search(grid, START, TARGET)  # Find path using A* search
    if path:  # If a path is found, plot it
        plot_grid(grid, path)
    else:
        print("No path found")

if __name__ == "__main__":
    main()
