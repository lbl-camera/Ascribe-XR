import numpy as np
from skimage import data as sk_data
from matplotlib import pyplot as plt

if __name__ == '__main__':
    data = sk_data.cells3d().astype(np.uint8)[:,1,:,:]
    data.tofile("cells.bin")
    print(data.shape)
    plt.imshow(data[5])
    plt.show()