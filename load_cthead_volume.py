import numpy as np
import os
import glob
from PIL import Image
from skimage.measure import marching_cubes
import json

def load_ct_volume():
    """Load CT head volume from PNG stack and extract isosurface"""

    # Path to the CT head PNG files
    data_dir = r"C:\Users\rp\Documents\vr-start\specimen_data\cthead-8bit"

    # Get all PNG files in sorted order
    png_files = sorted(glob.glob(os.path.join(data_dir, "cthead-8bit*.png")))
    print(f"Found {len(png_files)} PNG files")

    if not png_files:
        print("No PNG files found!")
        return

    # Load the first image to get dimensions
    first_img = Image.open(png_files[0])
    if first_img.mode != 'L':
        first_img = first_img.convert('L')  # Convert to grayscale if needed

    height, width = np.array(first_img).shape
    num_slices = len(png_files)

    print(f"Volume dimensions: {num_slices} x {height} x {width}")

    # Initialize the 3D volume array
    volume = np.zeros((num_slices, height, width), dtype=np.uint8)

    # Load all slices
    for i, png_file in enumerate(png_files):
        img = Image.open(png_file)
        if img.mode != 'L':
            img = img.convert('L')  # Convert to grayscale if needed
        volume[i] = np.array(img)

        if i % 10 == 0:
            print(f"Loaded slice {i+1}/{num_slices}")

    print("Volume loading complete!")
    print(f"Volume shape: {volume.shape}")
    print(f"Volume data type: {volume.dtype}")
    print(f"Volume value range: {volume.min()} - {volume.max()}")

    # Extract isosurface using marching cubes at threshold 100
    print("Extracting isosurface using marching cubes (threshold=100)...")

    try:
        verts, faces, normals, values = marching_cubes(volume, level=100)
        print(f"Marching cubes complete!")
        print(f"Vertices: {verts.shape[0]}")
        print(f"Faces: {faces.shape[0]}")

        # Convert to the required format for submission
        # MUST flatten vertices and normals to 1D arrays
        vertices = verts.flatten().tolist()  # [x, y, z, x, y, z, ...]
        indices = faces.flatten().tolist()   # [i, j, k, ...]
        normals_flat = normals.flatten().tolist()  # [nx, ny, nz, nx, ny, nz, ...]

        print(f"Flattened vertices length: {len(vertices)} (should be {verts.shape[0] * 3})")
        print(f"Flattened normals length: {len(normals_flat)} (should be {normals.shape[0] * 3})")
        print(f"Indices length: {len(indices)} (should be {faces.shape[0] * 3})")

        # Save to JSON file
        mesh_data = {
            "vertices": vertices,
            "indices": indices,
            "normals": normals_flat
        }

        output_file = r"C:\Users\rp\Documents\vr-start\cthead_mesh.json"
        with open(output_file, "w") as f:
            json.dump(mesh_data, f)

        print(f"Mesh saved to: {output_file}")
        print(f"Saved {len(vertices)//3} vertices, {len(indices)//3} triangles")

        return output_file

    except Exception as e:
        print(f"Error during marching cubes: {e}")
        return None

if __name__ == "__main__":
    mesh_file = load_ct_volume()
    if mesh_file:
        print(f"Success! Mesh ready for submission at: {mesh_file}")
    else:
        print("Failed to generate mesh")