"""アプリアイコン(1024x1024, 透過なし)を生成する。 python tools/make_icon.py"""
import os
from PIL import Image, ImageDraw, ImageFilter

S = 2048  # 2倍で描いて縮小（アンチエイリアス）
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


img = Image.new("RGB", (S, S))
px = img.load()
top, bottom = (150, 200, 245), (226, 240, 255)
for y in range(S):
    c = lerp(top, bottom, y / S)
    for x in range(S):
        px[x, y] = c

d = ImageDraw.Draw(img, "RGBA")

# 雪の丘
d.ellipse([-400, 1560, S + 400, S + 900], fill=(244, 249, 255))
d.ellipse([-100, 1700, S + 700, S + 1100], fill=(255, 255, 255))


def ball(cx, cy, r, base=(252, 253, 255), shade=(196, 215, 240)):
    # 影つきの丸（簡易グラデーション）
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    steps = 40
    for i in range(steps):
        t = i / (steps - 1)
        rr = r * (1 - 0.55 * t)
        ox = -r * 0.22 * t
        oy = -r * 0.26 * t
        col = lerp(shade, base, t) + (255,)
        ld.ellipse([cx + ox - rr, cy + oy - rr, cx + ox + rr, cy + oy + rr], fill=col)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    img.paste(layer, (0, 0), mask)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(140, 170, 215, 190), width=10)


# 影
d.ellipse([560, 1700, 1500, 1800], fill=(60, 80, 130, 45))

# 体と頭
ball(1030, 1330, 420)
ball(1030, 720, 290)

# ニット帽
cap = [(760, 640), (1300, 640), (1280, 520), (1030, 400), (790, 520)]
d.polygon(cap, fill=(236, 92, 96))
d.rounded_rectangle([735, 600, 1325, 690], radius=40, fill=(190, 56, 69))
d.ellipse([985, 360, 1075, 450], fill=(252, 253, 255), outline=(140, 170, 215, 190), width=8)

# 顔
d.ellipse([890, 700, 940, 750], fill=(48, 56, 82))
d.ellipse([1120, 700, 1170, 750], fill=(48, 56, 82))
d.ellipse([903, 708, 920, 725], fill=(255, 255, 255))
d.ellipse([1133, 708, 1150, 725], fill=(255, 255, 255))
d.ellipse([800, 770, 880, 820], fill=(255, 168, 184, 170))
d.ellipse([1180, 770, 1260, 820], fill=(255, 168, 184, 170))
d.polygon([(995, 755), (1065, 755), (1030, 850)], fill=(255, 153, 56))

# マフラー
d.ellipse([740, 940, 1320, 1060], fill=(92, 158, 235), outline=(56, 112, 194), width=8)
d.rounded_rectangle([1130, 990, 1260, 1290], radius=34, fill=(92, 158, 235), outline=(56, 112, 194), width=8)
d.rectangle([1134, 1130, 1256, 1160], fill=(56, 112, 194))
d.rectangle([1134, 1210, 1256, 1240], fill=(56, 112, 194))

# ボタン
for y in (1230, 1340, 1450):
    d.ellipse([1005, y - 30, 1055, y + 20], fill=(48, 56, 82))

# 枝の腕
arm = (120, 84, 60)
d.line([(660, 1290), (330, 1090)], fill=arm, width=26)
d.line([(500, 1190), (440, 1030)], fill=arm, width=20)
d.line([(1400, 1290), (1730, 1090)], fill=arm, width=26)
d.line([(1560, 1190), (1620, 1030)], fill=arm, width=20)

# 降る雪
for (x, y, r) in [(300, 300, 22), (520, 160, 14), (1560, 240, 26), (1760, 500, 16), (240, 700, 18),
                  (1820, 880, 22), (420, 460, 12), (1680, 150, 12), (140, 1000, 14), (1900, 1200, 16)]:
    d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, 230))

img = img.resize((1024, 1024), Image.LANCZOS)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT, "PNG")
print("wrote", os.path.normpath(OUT))
