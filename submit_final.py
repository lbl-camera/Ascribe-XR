import pickle
import json

def load_and_prepare_mesh():
    """Load the CT head mesh and return vertices and indices for submission"""

    # Load the mesh data
    print('Loading CT head mesh data...')
    with open('ct_mesh_data.pkl', 'rb') as f:
        mesh_data = pickle.load(f)

    vertices = mesh_data['vertices']
    indices = mesh_data['indices']

    print(f'Loaded: {len(vertices)} vertices, {len(indices)} indices')

    # Verify data format
    print('Verifying data format...')
    assert isinstance(vertices, list), "Vertices must be a list"
    assert isinstance(indices, list), "Indices must be a list"
    assert len(vertices[0]) == 3, "Each vertex must have 3 coordinates"

    print('Data format verified!')
    print('Ready to submit CT head isosurface mesh.')

    return vertices, indices

if __name__ == "__main__":
    vertices, indices = load_and_prepare_mesh()