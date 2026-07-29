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

# Attractive potential function
def attractive_potential(q, goal):
    distance_to_goal = np.linalg.norm(np.array(q) - np.array(goal))
    return 0.5 * att_strength * (distance_to_goal ** 2)

# Repulsive potential function
def repulsive_potential(q, obstacles, rep_strength, rep_range):
    U_rep = 0
    for obs in obstacles:
        distance_to_obstacle = np.linalg.norm(np.array(q) - np.array(obs))
        if distance_to_obstacle <= rep_range:
            U_rep += 0.5 * rep_strength * (1 / distance_to_obstacle - 1 / rep_range) ** 2
    return U_rep

# Total potential field
def total_potential(q, goal, obstacles, att_strength, rep_strength, rep_range):
    U_att = attractive_potential(q, goal)
    U_rep = repulsive_potential(q, obstacles, rep_strength, rep_range)
    return U_att + U_rep

# Gradient descent function
def gradient_descent(q, goal, obstacles, step_size):
    grad_x = (total_potential((q[0] + 0.01, q[1]), goal, obstacles, att_strength, rep_strength, rep_range)
              - total_potential(q, goal, obstacles, att_strength, rep_strength, rep_range)) / 0.01
    grad_y = (total_potential((q[0], q[1] + 0.01), goal, obstacles, att_strength, rep_strength, rep_range)
              - total_potential(q, goal, obstacles, att_strength, rep_strength, rep_range)) / 0.01
    
    new_x = q[0] - step_size * grad_x
    new_y = q[1] - step_size * grad_y
    
    return new_x, new_y

# Plotting the path
def plot_path(start, goal, obstacles, path):
    plt.plot([p[0] for p in path], [p[1] for p in path], 'g-', label='Path')
    plt.plot(start[0], start[1], 'bo', label='Start')
    plt.plot(goal[0], goal[1], 'ro', label='Goal')

    for obs in obstacles:
        plt.plot(obs[0], obs[1], 'bx', label='Obstacle')

    plt.grid()
    plt.legend()
    plt.show()

# Main function
def main():
    current_position = start
    path = [current_position]

    while np.linalg.norm(np.array(current_position) - np.array(goal)) > step_size:
        current_position = gradient_descent(current_position, goal, obstacles, step_size)
        path.append(current_position)

    plot_path(start, goal, obstacles, path)

main()
