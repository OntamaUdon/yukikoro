"""Poly Haven (CC0) から取得した素材を、アプリで使う形に加工して Resources/Photoreal に置く。

使い方: python tools/prepare_assets.py <ダウンロードしたフォルダ>
 - 雪: 色は泥のような暗い筋があるため、明るく均して「白い雪」にする（法線・粗さ・AO はそのまま）
 - 布(フリース): 色を無彩色に落とし、あとからアプリ側で好きな色を掛けられるようにする
 - 樹皮: そのまま（サイズだけ縮小）
 素材の出典とライセンスは Resources/Photoreal/CREDITS.md を参照。
"""
import os, shutil, sys
import numpy as np
from PIL import Image, ImageFilter

src = sys.argv[1]
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "Photoreal")
os.makedirs(dst, exist_ok=True)

def load(name):
    return Image.open(os.path.join(src, name))

# HDRI（空と雪道の写真。そのまま使う）
for n in ("snowy_forest_path_01_1k.hdr", "stierberg_sunrise_1k.hdr"):
    shutil.copy(os.path.join(src, n), os.path.join(dst, n))

# 雪: 色を白く均す
diff = np.asarray(load("snow_02_diff_1k.jpg").convert("RGB"), dtype=np.float32) / 255.0
lum = diff.mean(axis=2, keepdims=True)
blur = np.asarray(Image.fromarray((lum[..., 0] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(24)), dtype=np.float32)[..., None] / 255.0
detail = lum - blur                      # 細かい凹凸の濃淡だけ残す
albedo = 0.955 + detail * 0.35           # ほぼ白＋ごく弱い濃淡
albedo = np.clip(albedo, 0.80, 1.0)
tint = np.array([0.985, 0.995, 1.0], dtype=np.float32)   # ほんのり青白く
Image.fromarray((np.clip(albedo * tint, 0, 1) * 255).astype(np.uint8)).save(os.path.join(dst, "snow_albedo.jpg"), quality=90)
for a, b in (("snow_02_nor_gl_1k.jpg", "snow_normal.jpg"), ("snow_02_rough_1k.jpg", "snow_rough.jpg"), ("snow_02_ao_1k.jpg", "snow_ao.jpg")):
    shutil.copy(os.path.join(src, a), os.path.join(dst, b))

# 樹皮（512に縮小）
for a, b in (("bark_brown_01_diff_1k.jpg", "bark_diffuse.jpg"), ("bark_brown_01_nor_gl_1k.jpg", "bark_normal.jpg"), ("bark_brown_01_rough_1k.jpg", "bark_rough.jpg")):
    load(a).resize((512, 512), Image.LANCZOS).save(os.path.join(dst, b), quality=88)

# フリース（無彩色の明るさだけ。色はアプリ側で掛ける）
fd = np.asarray(load("polar_fleece_diff_1k.jpg").convert("L").resize((512, 512), Image.LANCZOS), dtype=np.float32) / 255.0
fd = np.clip((fd - fd.mean()) * 1.4 + 0.86, 0, 1)
Image.fromarray((fd * 255).astype(np.uint8)).save(os.path.join(dst, "fleece_luma.jpg"), quality=90)
for a, b in (("polar_fleece_nor_gl_1k.jpg", "fleece_normal.jpg"), ("polar_fleece_rough_1k.jpg", "fleece_rough.jpg")):
    load(a).convert("RGB" if "nor" in a else "L").resize((512, 512), Image.LANCZOS).save(os.path.join(dst, b), quality=88)

print("done ->", os.path.normpath(dst))
for f in sorted(os.listdir(dst)):
    print(f, os.path.getsize(os.path.join(dst, f)) // 1024, "KB")
