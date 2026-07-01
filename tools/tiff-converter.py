from pathlib import Path
import sys


import numpy as np
from PIL import Image
import tifffile


input_path = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
down_sampling_factor_x = int(sys.argv[3])
down_sampling_factor_y = int(sys.argv[4])
down_sampling_factor_z = int(sys.argv[5])
frame_steps = int(sys.argv[6])
invert = int(sys.argv[7]) # this should be a 0 or 1

output_dir.mkdir(parents=True, exist_ok=True)

# Accept either a single .tif/.tiff file or a directory of them
if input_path.is_file():
    tif_files = [input_path]
else:
    tif_files = sorted(list(input_path.glob("*.tif")) + list(input_path.glob("*.tiff")))

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