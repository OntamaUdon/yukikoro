"""Poly Haven (CC0) の HDRI（.hdr）から、背景の画像（昼・夕方・夜）を作って Resources/Backgrounds に置く。

使い方: python tools/make_backgrounds.py <HDRI を置いたフォルダ>
 - snowy_forest_path_01_1k.hdr（昼）と stierberg_sunrise_1k.hdr（夕方・夜）が必要。
 - 出典とライセンスは Resources/Backgrounds/CREDITS.md を参照。
"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw

src = sys.argv[1]
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "Backgrounds")
os.makedirs(dst, exist_ok=True)


def read_hdr(path):
    f = open(path, "rb")
    while f.readline().strip() != b"":
        pass
    res = f.readline().split(); h = int(res[1]); w = int(res[3])
    img = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        hdr = f.read(4)
        assert hdr[0] == 2 and hdr[1] == 2, "RLE 形式の .hdr のみ対応"
        for c in range(4):
            x = 0
            while x < w:
                n = f.read(1)[0]
                if n > 128:
                    n -= 128; v = f.read(1)[0]; img[y, x:x + n, c] = v; x += n
                else:
                    img[y, x:x + n, c] = np.frombuffer(f.read(n), np.uint8); x += n
    e = img[..., 3].astype(np.int32)
    scale = np.where(e > 0, 2.0 ** (e - 136), 0)[..., None]
    return img[..., :3] * scale


def tone(rgb, ex=1.0):
    t = rgb * ex
    t = t / (1 + t)
    return np.clip(t, 0, 1) ** (1 / 2.2)


def save(arr, path):
    im = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
    im = im.resize((im.width * 2, im.height * 2), Image.LANCZOS)
    im.save(path, quality=86)


day = read_hdr(os.path.join(src, "snowy_forest_path_01_1k.hdr"))
dusk = read_hdr(os.path.join(src, "stierberg_sunrise_1k.hdr"))
save(tone(day[:, 60:700]), os.path.join(dst, "bg_day.jpg"))
save(tone(dusk[:, 290:930]), os.path.join(dst, "bg_dusk.jpg"))
night = tone(dusk[:, 290:930]) * np.array([0.22, 0.28, 0.50])
night_path = os.path.join(dst, "bg_night.jpg")
save(night, night_path)
im = Image.open(night_path)
dr = ImageDraw.Draw(im)
rng = np.random.default_rng(3)
for _ in range(140):
    x = int(rng.integers(0, im.width)); y = int(rng.integers(0, int(im.height * 0.45)))
    r = int(rng.choice([1, 1, 1, 2])); v = int(rng.integers(150, 255))
    dr.ellipse((x - r, y - r, x + r, y + r), fill=(v, v, min(255, v + 10)))
im.save(night_path, quality=86)
