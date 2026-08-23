import numpy as np
from PIL import Image
import glob
import os
from skimage.measure import marching_cubes
from skimage.filters import threshold_otsu
import json

# Path to the directory containing PNG files
data_dir = r"C:\Users\rp\Documents\vr-start\specimen_data\cthead-8bit"

# Find all PNG files matching the pattern
png_files = sorted(glob.glob(os.path.join(data_dir, "cthead-8bit*.png")))
print(f"Found {len(png_files)} PNG files")

# Load the first image to get dimensions
first_img = Image.open(png_files[0])
height, width = np.array(first_img).shape[:2]
print(f"Image dimensions: {width}x{height}")

# Initialize 3D volume array
volume = np.zeros((len(png_files), height, width), dtype=np.uint8)

# Load all PNG slices into the volume
print("Loading PNG stack...")
for i, png_file in enumerate(png_files):
    img = Image.open(png_file)
    # Convert to grayscale if needed
    if img.mode != 'L':
        img = img.convert('L')
    volume[i] = np.array(img)
    if (i + 1) % 20 == 0:
        print(f"  Loaded {i + 1}/{len(png_files)} slices")

print(f"Volume shape: {volume.shape}")
print(f"Volume dtype: {volume.dtype}")
print(f"Volume range: [{volume.min()}, {volume.max()}]")

# Apply Otsu thresholding to determine the threshold value
print("\nComputing Otsu threshold...")
threshold = threshold_otsu(volume)
print(f"Otsu threshold: {threshold}")

# Extract isosurface using marching cubes
print("\nExtracting isosurface with marching cubes...")
verts, faces, norms, values = marching_cubes(volume, level=threshold, spacing=(1.0, 1.0, 1.0))

print(f"Extracted mesh:")
print(f"  Vertices: {len(verts)}")
print(f"  Faces: {len(faces)}")
print(f"  Normals: {len(norms)}")

# Flatten the arrays as required by the submission format
print("\nFlattening arrays for submission...")
vertices = verts.flatten().tolist()  # MUST flatten to [x, y, z, x, y, z, ...]
indices = faces.flatten().tolist()
normals = norms.flatten().tolist()   # MUST flatten to [nx, ny, nz, nx, ny, nz, ...]

print(f"Flattened vertices length: {len(vertices)} (should be {len(verts) * 3})")
print(f"Flattened indices length: {len(indices)} (should be {len(faces) * 3})")
print(f"Flattened normals length: {len(normals)} (should be {len(norms) * 3})")

# Save to JSON file
output_file = os.path.join(data_dir, "cthead_mesh.json")
print(f"\nSaving mesh to {output_file}...")
with open(output_file, "w") as f:
    json.dump({
        "vertices": vertices,
        "indices": indices,
        "normals": normals
    }, f)

print(f"Saved mesh with {len(verts)} vertices to {output_file}")
print("\nDone! Ready to submit.")
