"""Normalize image_gen PNGs and derive unknown coats. Requires Pillow + numpy.

Usage: python3 tools/prepare_cow_images.py FULL_HOLSTEIN FULL_BROWN AVATAR_HOLSTEIN AVATAR_BROWN
Inputs are retained. Only the six application PNGs are overwritten.
"""
from pathlib import Path
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'apps/mobile/cowlog_flutter/assets/models'


def prepare(path, avatar):
    image = Image.open(path).convert('RGBA')
    # Drop invisible generation residue before determining the animal bounds.
    alpha = image.getchannel('A').point(lambda x: 0 if x < 8 else x)
    image.putalpha(alpha)
    image = image.crop(alpha.getbbox())
    if avatar:
        # Keep the complete ears and neck within the circular UI crop.
        image.thumbnail((800, 850), Image.Resampling.LANCZOS)
    else:
        image.thumbnail((870, 850), Image.Resampling.LANCZOS)
    result = Image.new('RGBA', (1024, 1024))
    result.alpha_composite(image, ((1024-image.width)//2, (1024-image.height)//2))
    return result


def unknown(image, avatar):
    pixels = np.asarray(image).copy()
    rgb = pixels[:, :, :3].astype(float)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    luminance = .299*r + .587*g + .114*b
    light = np.clip(.70*luminance + 86, 0, 248)
    gray = np.stack((light*.98, light*1.025, light), axis=-1)
    # Retain the yellow ear tag and dark neutral eyes, nose, collar and device.
    y, x = np.indices(luminance.shape)
    if avatar:
        tag_region = (x > 735) & (x < 830) & (y > 260) & (y < 380)
    else:
        tag_region = (x > 325) & (x < 385) & (y > 185) & (y < 280)
    yellow = tag_region & (r > 110) & (g > 85) & (b < g*.8) & (g > r*.70)
    dark_neutral = (luminance < 100) & ((rgb.max(2)-rgb.min(2)) < 27)
    gray[yellow | dark_neutral] = rgb[yellow | dark_neutral]
    pixels[:, :, :3] = np.clip(gray, 0, 255).astype('uint8')
    return Image.fromarray(pixels)


def main():
    if len(sys.argv) != 5:
        raise SystemExit(__doc__)
    for avatar, paths in ((False, sys.argv[1:3]), (True, sys.argv[3:5])):
        images = [prepare(p, avatar) for p in paths]
        images.append(unknown(images[1], avatar))
        suffix = '_avatar' if avatar else ''
        for name, image in zip(('holstein', 'brown', 'unknown'), images):
            path = DEST / f'cow_{name}{suffix}.png'
            image.save(path)
            print(path.relative_to(ROOT), image.size, image.getchannel('A').getbbox())


if __name__ == '__main__':
    main()
