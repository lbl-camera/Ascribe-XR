from pathlib import Path
import sys


import numpy as np
from PIL import Image
import tifffile

"""
TIFF to JPEG Volume Converter

This script converts TIFF image data into JPEG image slices.

It supports two TIFF input layouts:

1. A directory of 2D TIFF files
   - Each TIFF is treated as one slice of a larger 3D volume.
   - All 2D TIFF files are loaded and stacked into one 3D NumPy array.
   - The combined volume has shape:

        z, y, x

2. Individual 3D TIFF stack files
   - Each 3D TIFF is treated as an already-combined volume.
   - The volume is processed directly.

Usage:
    python tiff-converter.py <input_dir> <output_dir> <x_factor> <y_factor> <z_factor> <frame_steps> <invert>

Arguments:
    input_dir:
        Directory containing .tif or .tiff files.

    output_dir:
        Directory where JPEG files will be written.
        The directory is created if it does not already exist.

    x_factor:
        Downsampling factor for the x-axis, or image width.
        Use 1 to keep full resolution.
        Use 2 to keep every 2nd pixel.
        Use 4 to keep every 4th pixel.

    y_factor:
        Downsampling factor for the y-axis, or image height.
        Use 1 to keep full resolution.

    z_factor:
        Downsampling factor for the z-axis, or stack depth.
        Use 1 to keep every slice.
        Use 2 to keep every 2nd slice.

    frame_steps:
        Controls which frames are saved as JPEGs after downsampling.
        Use 1 to save every frame.
        Use 2 to save every 2nd frame.
        Use 10 to save every 10th frame.

    invert:
        Whether to invert image brightness.
        Use 0 for normal brightness.
        Use 1 to invert, so dark becomes light and light becomes dark.

Example:
    python tiff-converter.py ./input_tiffs ./output_jpegs 2 2 2 1 0

    This reads TIFFs from ./input_tiffs, downsamples x/y/z by 2,
    saves every frame, does not invert brightness, and writes JPEGs
    to ./output_jpegs.

Processing flow:
    1. Read TIFF files from the input directory.
    2. If TIFFs are 2D, collect them and stack them into one 3D volume.
    3. If a TIFF is already 3D, process it directly.
    4. Downsample the volume using NumPy slicing:

           volume[::z_factor, ::y_factor, ::x_factor]

    5. Normalize the image intensity values to 8-bit range, 0-255.
    6. Optionally invert brightness.
    7. Save selected frames as JPEG files.

Notes:
    - JPEG images must be 8-bit, so the script normalizes input data.
    - The downsampling method is simple decimation, meaning it keeps every nth voxel.
      It does not average or interpolate between pixels.
    - Output JPEG files are named using the source file or combined stack name,
      followed by the frame index.
"""

input_dir = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
down_sampling_factor_x = int(sys.argv[3])
down_sampling_factor_y = int(sys.argv[4])
down_sampling_factor_z = int(sys.argv[5])
frame_steps = int(sys.argv[6])
invert = int(sys.argv[7]) # this should be a 0 or 1

output_dir.mkdir(parents=True, exist_ok=True)

tif_files = sorted(list(input_dir.glob("*.tif")) + list(input_dir.glob("*.tiff")))

if not tif_files:
    print("No TIFF files found.")
    sys.exit(0)





def normalize_to_uint8(data):
    data = data.astype(np.float32)

    data -= data.min()

    if data.max() > 0:
        data /= data.max()
    if invert:
        data = np.max(data)-data
        
    return (data * 255).astype(np.uint8)


def save_stack_as_jpegs(stack, output_dir, base_name):
    print(f"Stack shape for {base_name}: {stack.shape}")

    image8 = normalize_to_uint8(stack)

    for frame_idx in range(0,image8.shape[0], frame_steps):
        frame = image8[frame_idx]
        
        frame = np.squeeze(frame)

        if frame.ndim != 2:
            raise ValueError(f"Frame is not 2D after squeeze: {frame.shape}")

        img = Image.fromarray(frame)

        output_path = output_dir / f"{base_name}_{frame_idx:04d}.jpeg"
        img.save(output_path, "JPEG", quality=95)

        print(f"Saved: {output_path}")



two_d_slices = []

for tif_path in tif_files:
    print(f"Reading {tif_path.name}")

    data = tifffile.imread(tif_path)
    data = np.squeeze(data)

    print("Original TIFF shape after squeeze:", data.shape)
    # we don't want to do processing on 2d tiffs, we need to combine them to stack
    if data.ndim == 2:
        two_d_slices.append(data)

    elif data.ndim == 3:
        # This file is already a stack
        data = data[::down_sampling_factor_z, ::down_sampling_factor_y, ::down_sampling_factor_x]
        save_stack_as_jpegs(
            stack=data,
            output_dir=output_dir,
            base_name=tif_path.stem
        )

    else:
        raise ValueError(f"Unsupported TIFF shape for {tif_path.name}: {data.shape}")


# if were in a case where our data had 2 dimensions, then we should now combine those 2d tiffs into one big stack 
if two_d_slices:
    print("Combining 2D TIFF files into one stack...")

    combined_stack = np.stack(two_d_slices, axis=0)
    print("Before downsample:", combined_stack.shape)

    combined_stack = combined_stack[::down_sampling_factor_z, ::down_sampling_factor_y, ::down_sampling_factor_x]

    print("After downsample:", combined_stack.shape)
    save_stack_as_jpegs(
        stack=combined_stack,
        output_dir=output_dir,
        base_name="combined_stack"
    )

print("Done.")