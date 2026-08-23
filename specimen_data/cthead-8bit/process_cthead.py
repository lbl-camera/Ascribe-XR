#!/usr/bin/env python3
"""
Load CT head volume from PNG stack and extract isosurface using marching cubes
"""
import os
import json
import glob
import numpy as np
from PIL import Image
from skimage import measure
import re

def load_png_stack(directory):
    """Load PNG files and stack them into a 3D volume"""
    print(f"Loading PNG files from {directory}")

    # Get all PNG files and sort them by number
    png_files = glob.glob(os.path.join(directory, "cthead-8bit*.png"))

    # Sort by the numeric part of the filename
    def get_number(filename):
        match = re.search(r'cthead-8bit(\d+)\.png', filename)
        return int(match.group(1)) if match else 0

    png_files.sort(key=get_number)

    print(f"Found {len(png_files)} PNG files")

    # Load the first image to get dimensions
    first_img = Image.open(png_files[0])
    first_array = np.array(first_img)
    if len(first_array.shape) == 3:  # RGB image
        first_array = np.mean(first_array, axis=2)  # Convert to grayscale

    height, width = first_array.shape
    depth = len(png_files)

    print(f"Volume dimensions: {depth} x {height} x {width}")

    # Initialize the 3D volume
    volume = np.zeros((depth, height, width), dtype=np.uint8)

    # Load all PNG files
    for i, png_file in enumerate(png_files):
        img = Image.open(png_file)
        img_array = np.array(img)

        # Convert to grayscale if needed
        if len(img_array.shape) == 3:
            img_array = np.mean(img_array, axis=2)

        volume[i] = img_array.astype(np.uint8)

        if (i + 1) % 10 == 0:
            print(f"Loaded {i + 1}/{len(png_files)} slices")

    print(f"Volume loaded. Min: {volume.min()}, Max: {volume.max()}")
    return volume

def extract_isosurface(volume, threshold=100):
    """Extract isosurface using marching cubes"""
    print(f"Extracting isosurface at threshold {threshold}")

    # Apply marching cubes
    try:
        verts, faces, normals, values = measure.marching_cubes(
            volume,
            level=threshold,
            spacing=(1.0, 1.0, 1.0)
        )

        print(f"Generated mesh with {len(verts)} vertices and {len(faces)} faces")

        # Convert to the required flat list format
        vertices = verts.flatten().tolist()  # [x, y, z, x, y, z, ...]
        indices = faces.flatten().tolist()   # [i, j, k, i, j, k, ...]
        normals_flat = normals.flatten().tolist()  # [nx, ny, nz, nx, ny, nz, ...]

        return vertices, indices, normals_flat

    except Exception as e:
        print(f"Error during marching cubes: {e}")
        return None, None, None

def save_mesh_json(vertices, indices, normals, output_file):
    """Save mesh data to JSON file"""
    mesh_data = {
        "vertices": vertices,
        "indices": indices,
        "normals": normals
    }

    with open(output_file, 'w') as f:
        json.dump(mesh_data, f)

    print(f"Saved mesh to {output_file}")
    print(f"Mesh contains {len(vertices)//3} vertices, {len(indices)//3} triangles")

def main():
    # Directory containing the PNG files
    png_directory = r"C:\Users\rp\Documents\vr-start\specimen_data\cthead-8bit"
    output_file = os.path.join(png_directory, "cthead_mesh.json")

    # Load the PNG stack
    volume = load_png_stack(png_directory)

    if volume is None:
        print("Failed to load volume")
        return

    # Extract isosurface using marching cubes at threshold 100
    vertices, indices, normals = extract_isosurface(volume, threshold=100)

    if vertices is None:
        print("Failed to extract isosurface")
        return

    # Save mesh to JSON file
    save_mesh_json(vertices, indices, normals, output_file)

    print("Processing complete!")
    return output_file

if __name__ == "__main__":
    main()