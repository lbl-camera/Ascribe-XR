import pickle

# Load the mesh data
with open('ct_mesh_data.pkl', 'rb') as f:
    mesh_data = pickle.load(f)

# Extract the vertices and indices
vertices = mesh_data['vertices']
indices = mesh_data['indices']

print("CT Head Mesh - Ready for Submission")
print("="*50)
print(f"Vertices: {len(vertices):,}")
print(f"Indices: {len(indices):,}")
print(f"Triangles: {len(indices)//3:,}")

# Export the data - this will be used for the function call
CT_VERTICES = vertices
CT_INDICES = indices

print("\nMesh data extracted successfully!")
print("Variables CT_VERTICES and CT_INDICES are ready.")