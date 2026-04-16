import os
import glob
import numpy as np
from PIL import Image
from skimage.measure import marching_cubes
import json
import pyvista as pv
from ascribe_link.mesh_utils import extract_mesh_data

def load_ct_volume(directory_path):
    """Load CT head volume from PNG stack"""
    # Find all PNG files in the directory
    png_pattern = os.path.join(directory_path, "cthead-8bit*.png")
    png_files = sorted(glob.glob(png_pattern))

    if not png_files:
        raise ValueError(f"No PNG files found in {directory_path}")

    print(f"Found {len(png_files)} PNG files")

    # Load first image to get dimensions
    first_img = Image.open(png_files[0])
    height, width = first_img.size

    # Initialize volume array
    volume = np.zeros((len(png_files), height, width), dtype=np.uint8)

    # Load all images into the volume
    for i, png_file in enumerate(png_files):
        img = Image.open(png_file)
        if img.mode != 'L':
            img = img.convert('L')
        volume[i] = np.array(img)

        if i % 20 == 0:
            print(f"Loaded slice {i+1}/{len(png_files)}")

    print(f"Volume shape: {volume.shape}")
    return volume

def extract_isosurface(volume, threshold=100):
    """Extract isosurface using marching cubes"""
    print(f"Extracting isosurface at threshold {threshold}...")

    # Use marching cubes to extract the surface
    vertices, faces, normals, values = marching_cubes(volume, level=threshold)

    print(f"Extracted {len(vertices)} vertices and {len(faces)} faces")

    # Create PyVista mesh
    faces_formatted = np.column_stack([
        np.full(len(faces), 3, dtype=np.int32),
        faces.astype(np.int32)
    ]).flatten()

    mesh = pv.PolyData(vertices, faces_formatted)
    return mesh

def main():
    directory_path = r"C:\Users\rp\Documents\vr-start\specimen_data\cthead-8bit"

    # Load the CT volume
    volume = load_ct_volume(directory_path)

    # Extract isosurface at threshold 100
    mesh = extract_isosurface(volume, threshold=100)

    # Extract mesh data for submission
    vertices, indices = extract_mesh_data(mesh)

    print(f"Ready to submit mesh with {len(vertices)} vertices and {len(indices)} indices")

    # Return the data instead of printing
    return {"vertices": vertices, "indices": indices}

if __name__ == "__main__":
    mesh_data = main()
    print("Mesh processing complete!")