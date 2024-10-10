from pdb import set_trace
from pathlib import Path
import numpy as np
from PIL import Image
import matplotlib.pyplot as plt
from argparse import ArgumentParser
import cv2
from scipy.ndimage import generic_filter

def norm(npa): return cv2.normalize(npa, None, 0, 1, cv2.NORM_MINMAX)

def local_variance(image_np, k=7):
    # Define a function to compute local variance
    def lv(window):
        return window.var() ** 2

    variance_image = generic_filter(image_np, lv, size=k)

    # Calculate the detail density as the mean of local variances
    detail_density = np.mean(variance_image) / np.var(image_np)  # Normalize
    print(f'Detail Density: {detail_density:.4f}')

    return variance_image

if __name__ == "__main__":
    parser = ArgumentParser()
    parser.add_argument('--color', type=Path, help='Color pixels')
    parser.add_argument('--depth', type=Path, help='Depth Map')
    parser.add_argument('--d24', type=bool, help='Depthmap is RGB24 encoded')
    parser.add_argument('--k', type=int, default=14, help='Kernel size')
    parser.add_argument('--cmap', type=str, default='viridis', help='plot colors')
    args = parser.parse_args()
    cmap = args.cmap

    image = Image.open(args.color)
    image_np = np.array(image)

    depth_map = Image.open(args.depth)
    d_np = np.array(depth_map)

    if args.d24 is None or not args.d24:
        d_np = d_np[:, :, 0] / 255 # Use Red
    else:
        # Decode RGB24
        scaled = (d_np[:, :, 0].astype(np.uint32) << 16) | \
            (d_np[:, :, 1].astype(np.uint32) << 8) | \
            d_np[:, :, 2]
        d_np = scaled / (2**24 - 1)

    # a = show_localvariance(image_np, k=args.k)
    d_variance = local_variance(d_np, k=args.k)

    d_variance = norm(d_variance)
    d_variance = np.clip(d_variance, 0, 0.000001)
    d_variance = norm(d_variance)

    plt.imshow(d_variance, cmap=cmap)
    plt.title('Detail Map (Local Variance²)')
    plt.axis('off')
    plt.show()
