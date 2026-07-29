import heapq

# Dijkstra's algorithm starter template

# Graph representation as an adjacency list
graph = {
    'A': [('B', 7), ('C', 9), ('F', 14)],
    'B': [('A', 7), ('D', 15)],
    'C': [('A', 9), ('D', 11), ('E', 10)],
    'D': [('B', 15), ('C', 11), ('E', 6)],
    'E': [('C', 10), ('D', 6), ('F', 9)],
    'F': [('A', 14), ('E', 9)]
}

def dijkstra(graph, start):
    """
    Dijkstra's algorithm to find the shortest path from a start node to all other nodes.
    
    Args:
    - graph (dict): Adjacency list representing the graph.
    - start (str): The starting node.

    Returns:
    - dict: The shortest distance to each node from the start node.
    """
    # Step 1: Initialize distances dictionary
    distances = {node: float('infinity') for node in graph}
    distances[start] = 0  # Distance to start node is zero

    # Priority queue (heap) to store (distance, node) pairs
    queue = [(0, start)]
    
    # Step 2: Create a set to track visited nodes
    visited = set()

    # Step 3: Process the priority queue until it's empty
    while queue:
        # Step 3a: Pop the node with the smallest distance
        current_distance, current_node = heapq.heappop(queue)

        # If we have already visited this node, skip
        if current_node in visited:
            continue

        # Mark the node as visited
        visited.add(current_node)

        # Step 3b: Loop through neighbors of the current node
        for neighbor, weight in graph[current_node]:
            # Calculate the new potential distance to the neighbor
            distance = current_distance + weight

            # TODO: If the calculated distance is shorter, update the neighbor's distance
            # and add it to the priority queue
            # Hint: Update both the distances dictionary and the queue

            # YOUR CODE HERE
    
    # Return the final distances dictionary
    return distances

# Starting node
start_node = 'A'

# Run Dijkstra's algorithm and print results
shortest_paths = dijkstra(graph, start_node)

print(f"Shortest paths from {start_node}:")
for node, distance in shortest_paths.items():
    print(f"Node {node}: {distance}")

