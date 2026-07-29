import heapq

# Graph representation as an adjacency list
graph = {
    'A': [('B', 7), ('C', 9), ('F', 14)],
    'B': [('A', 7), ('D', 15)],
    'C': [('A', 9), ('D', 11), ('E', 10)],
    'D': [('B', 15), ('C', 11), ('E', 6)],
    'E': [('C', 10), ('D', 6), ('F', 9)],
    'F': [('A', 14), ('E', 9)]
}

# Dijkstra's algorithm function
def dijkstra(graph, start):
    # Priority queue to explore nodes based on the shortest distance
    queue = [(0, start)]
    distances = {node: float('infinity') for node in graph}
    distances[start] = 0  # The start node has distance 0
    visited = set()

    while queue:
        current_distance, current_node = heapq.heappop(queue)

        if current_node in visited:
            continue
        
        visited.add(current_node)

        # Explore neighbors
        for neighbor, weight in graph[current_node]:
            distance = current_distance + weight

            # If the calculated distance is less, update the shortest distance
            if distance < distances[neighbor]:
                distances[neighbor] = distance
                heapq.heappush(queue, (distance, neighbor))

    return distances

# Starting node
start_node = 'A'

# Get shortest paths from A
shortest_paths = dijkstra(graph, start_node)

# Display results
print(f"Shortest paths from {start_node}:")
for node, distance in shortest_paths.items():
    print(f"Node {node}: {distance}")
