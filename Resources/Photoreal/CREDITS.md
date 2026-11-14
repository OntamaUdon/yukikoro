# 素材の出典（CC0）

すべて [Poly Haven](https://polyhaven.com) の素材で、ライセンスは **CC0（パブリックドメイン相当、商用利用・改変可、表記不要）** です。

| ファイル | 素材名 | 作者 | 加工 |
|---|---|---|---|
| `snowy_forest_path_01_1k.hdr` | Snowy Forest Path 01 (HDRI, 1k) | Oliksiy Yakovlyev | 太陽の最大輝度を40に制限（照明計算が壊れないように） |
| `stierberg_sunrise_1k.hdr` | Stierberg Sunrise (HDRI, 1k) | Grzegorz Wronkowski | 太陽の最大輝度を40に制限（元は5万超） |
| `snow_albedo.jpg` | Snow 02 (色) | Rob Tuytel | 暗い筋を均して白くした |
| `snow_normal.jpg` `snow_rough.jpg` `snow_ao.jpg` | Snow 02 | Rob Tuytel | なし |
| `bark_*.jpg` | Bark Brown 01 | Rob Tuytel | 512px に縮小 |
| `fleece_*.jpg` | Polar Fleece | colormass（写真）/ Rico Cilliers（加工） | 色を無彩色にして512pxに縮小 |

加工は `tools/prepare_assets.py` で再現できます。

## 差し替え用（あなたの写真）

`custom_background.jpg` という名前のファイルをこのフォルダに置くと、ホームの背景がその写真になります
（横長の通常の写真でも、360度のパノラマでも使えます）。ライティングは引き続き上の HDRI を使います。
