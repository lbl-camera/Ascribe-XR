import pickle

# Load the mesh data
with open('ct_mesh_data.pkl', 'rb') as f:
    mesh_data = pickle.load(f)

# Get vertices and indices
vertices = mesh_data["vertices"]
indices = mesh_data["indices"]

print(f"Loaded mesh with {len(vertices)} vertices and {len(indices)} indices")

# Export the first few elements to verify format
print("Sample vertices:")
for i in range(min(5, len(vertices))):
    print(f"  {vertices[i]}")

print("Sample indices:")
print(f"  {indices[:15]}...")

# Save data for submission
import sys
sys.path.append('.')