import numpy as np
import matplotlib.pyplot as plt

# Parameters
goal = (8, 8)  # Goal position
obstacles = [(3, 4), (5, 3), (7, 2)]  # Obstacles as (x, y) positions
start = (0, 0)  # Start position
step_size = 0.2  # Step size for robot movement
att_strength = 5.0  # Strength of attractive potential
rep_strength = 100.0  # Strength of repulsive potential
rep_range = 1.5  # Influence range of obstacles
# Calculate the attractive potential at point q
def attractive_potential(q, goal):
    """
    Calculate the attractive potential U_att at point q.

    Args:
    - q (tuple): Current position (x, y)
    - goal (tuple): Goal position (x, y)

    Returns:
    - float: Attractive potential at q
    """
    # TODO: Calculate the attractive potential using Euclidean distance
    # Hint: U_att(q) = 0.5 * att_strength * (distance_to_goal)^2
    # YOUR CODE HERE

# Calculate the repulsive potential at point q
def repulsive_potential(q, obstacles, rep_strength, rep_range):
    """
    Calculate the repulsive potential U_rep at point q.

    Args:
    - q (tuple): Current position (x, y)
    - obstacles (list): List of obstacle positions [(x1, y1), (x2, y2), ...]
    - rep_strength (float): Strength of repulsive potential
    - rep_range (float): Influence range of obstacles

    Returns:
    - float: Repulsive potential at q
    """
    U_rep = 0
    for obs in obstacles:
        distance_to_obstacle = np.linalg.norm(np.array(q) - np.array(obs))
        if distance_to_obstacle <= rep_range:
            # TODO: Calculate the repulsive potential
            # Hint: U_rep(q) = 0.5 * rep_strength * (1/distance - 1/rep_range)^2
            # YOUR CODE HERE
            pass
    return U_rep

# Total potential field function
def total_potential(q, goal, obstacles, att_strength, rep_strength, rep_range):
    """
    Calculate the total potential at point q by combining attractive and repulsive potentials.

    Args:
    - q (tuple): Current position (x, y)
    - goal (tuple): Goal position (x, y)
    - obstacles (list): List of obstacle positions [(x1, y1), (x2, y2), ...]
    - att_strength (float): Strength of attractive potential
    - rep_strength (float): Strength of repulsive potential
    - rep_range (float): Influence range of obstacles

    Returns:
    - float: Total potential at q
    """
    U_att = attractive_potential(q, goal)
    U_rep = repulsive_potential(q, obstacles, rep_strength, rep_range)
    return U_att + U_rep

# Move the robot in the direction that decreases potential
def gradient_descent(q, goal, obstacles, step_size):
    """
    Move the robot in the direction that minimizes the total potential.

    Args:
    - q (tuple): Current position (x, y)
    - goal (tuple): Goal position (x, y)
    - obstacles (list): List of obstacle positions [(x1, y1), (x2, y2), ...]
    - step_size (float): Step size for movement

    Returns:
    - tuple: New position after taking a step
    """
    # TODO: Compute the gradients (partial derivatives) of the total potential field
    # Take a small step in the direction of the negative gradient
    # YOUR CODE HERE

# Plot the robot's path
def plot_path(start, goal, obstacles, path):
    """
    Plot the robot's path from start to goal, including obstacles.

    Args:
    - start (tuple): Start position (x, y)
    - goal (tuple): Goal position (x, y)
    - obstacles (list): List of obstacle positions [(x1, y1), (x2, y2), ...]
    - path (list): List of robot positions representing the path
    """
    plt.figure()
    plt.plot([p[0] for p in path], [p[1] for p in path], marker='o', label="Robot Path")
    plt.plot(start[0], start[1], 'go', label='Start')
    plt.plot(goal[0], goal[1], 'ro', label='Goal')

    for obs in obstacles:
        plt.plot(obs[0], obs[1], 'bx', label='Obstacle')

    plt.legend()
    plt.grid()
    plt.show()

# Main function
def main():
    current_position = start
    path = [current_position]

    while np.linalg.norm(np.array(current_position) - np.array(goal)) > step_size:
        current_position = gradient_descent(current_position, goal, obstacles, step_size)
        path.append(current_position)

    # Plot the final path
    plot_path(start, goal, obstacles, path)

# Run the path planning
main()
