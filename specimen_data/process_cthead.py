#!/usr/bin/env python3
"""
Load CT head volume from PNG stack and extract isosurface using marching cubes.
"""

import os
import json
import numpy as np
from PIL import Image
from skimage.measure import marching_cubes
import glob

def load_png_stack(directory):
    """Load PNG files and stack into 3D volume."""
    print(f"Loading PNG files from {directory}...")

    # Get sorted list of PNG files
    pattern = os.path.join(directory, "cthead-8bit*.png")
    png_files = sorted(glob.glob(pattern))

    if not png_files:
        raise FileNotFoundError(f"No PNG files found in {directory}")

    print(f"Found {len(png_files)} PNG files")

    # Load first image to get dimensions
    first_img = Image.open(png_files[0])
    if first_img.mode != 'L':
        first_img = first_img.convert('L')
    first_array = np.array(first_img)
    height, width = first_array.shape

    print(f"Image dimensions: {width}x{height}")

    # Initialize 3D volume
    depth = len(png_files)
    volume = np.zeros((depth, height, width), dtype=np.uint8)

    # Load all images
    for i, png_file in enumerate(png_files):
        if i % 10 == 0:
            print(f"Loading slice {i+1}/{depth}...")

        img = Image.open(png_file)
        if img.mode != 'L':
            img = img.convert('L')
        volume[i] = np.array(img)

    print(f"Loaded volume shape: {volume.shape}")
    print(f"Volume data type: {volume.dtype}")
    print(f"Volume value range: {volume.min()} - {volume.max()}")

    return volume

def extract_isosurface(volume, threshold=100):
    """Extract isosurface using marching cubes."""
    print(f"Extracting isosurface at threshold {threshold}...")

    try:
        # Use marching cubes to extract isosurface
        verts, faces, normals, values = marching_cubes(
            volume,
            level=threshold,
            spacing=(1.0, 1.0, 1.0)  # Isotropic spacing
        )

        print(f"Extracted {len(verts)} vertices and {len(faces)} faces")

        return verts, faces, normals

    except Exception as e:
        print(f"Error in marching cubes: {e}")
        raise

def save_mesh_to_json(vertices, faces, normals, output_file):
    """Save mesh data to JSON file with flattened arrays."""
    print(f"Saving mesh to {output_file}...")

    # Flatten arrays as required by the submission format
    vertices_flat = vertices.flatten().tolist()  # [x, y, z, x, y, z, ...]
    indices_flat = faces.flatten().tolist()      # [i, j, k, i, j, k, ...]
    normals_flat = normals.flatten().tolist()    # [nx, ny, nz, nx, ny, nz, ...]

    mesh_data = {
        "vertices": vertices_flat,
        "indices": indices_flat,
        "normals": normals_flat
    }

    with open(output_file, 'w') as f:
        json.dump(mesh_data, f)

    print(f"Saved mesh with {len(vertices)} vertices to {output_file}")

    return output_file

def main():
    # Directory containing PNG files
    png_directory = r"C:\Users\rp\Documents\vr-start\specimen_data\cthead-8bit"

    # Output file
    output_file = r"C:\Users\rp\Documents\vr-start\specimen_data\cthead_mesh.json"

    try:
        # Load PNG stack
        volume = load_png_stack(png_directory)

        # Extract isosurface at threshold 100
        vertices, faces, normals = extract_isosurface(volume, threshold=100)

        # Save to JSON
        mesh_file = save_mesh_to_json(vertices, faces, normals, output_file)

        print(f"Successfully processed CT head volume!")
        print(f"Mesh saved to: {mesh_file}")

        return mesh_file

    except Exception as e:
        print(f"Error processing CT head volume: {e}")
        raise

if __name__ == "__main__":
    main()