import numpy as np

def calculate_certainty(distance, max_range=6.0):
  """Calculates the certainty of an obstacle based on its distance."""
  return (max_range - distance) / max_range

def normalize_histogram(histogram):
  """Normalizes the histogram values so they sum to 1."""
  histogram_sum = np.sum(histogram)
  return histogram / histogram_sum

# Parameters
num_sectors = 10
max_detection_range = 6.0
blocking_threshold = 0.6

# Obstacle data (distances, angles in degrees)
obstacles = [(3, 30), (5, 100), (2, 150)]

# Initialize the histogram
histogram = np.zeros(num_sectors)

# Calculate certainty and update histogram
for distance, angle in obstacles:
    # Determine the sector
  
    # Accumulate certainty

# Normalize the histogram
normalized_histogram = 

# Identify blocked sectors
blocked_sectors = 

print("Normalized Histogram:", normalized_histogram)
print("Blocked Sectors:", blocked_sectors)
