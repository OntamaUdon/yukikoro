# ゆきころ：みんなの雪だるまを作る散歩アプリ

歩くと雪玉が育つ。その雪玉を、いる場所の「雪だるま（塔）」にのせる。知らない誰かが、その上に、もっと小さな雪玉をのせる。1週間で、いちばん高い雪だるまを、県ごとに競う。iOS 17+、SwiftUI、CloudKit。

- **仕様書（これが正）**: [docs/DESIGN_V2.md](docs/DESIGN_V2.md)
- **CloudKit の登録手順（ユーザーが行う作業）**: [docs/CLOUDKIT_SETUP.md](docs/CLOUDKIT_SETUP.md)
- TestFlight の手順: [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md)
- プライバシー: [PRIVACY.md](PRIVACY.md)
- 前の版（歩数で雪玉を育てる3Dゲーム）は、タグ `v1-snowball-game` に残してある。

## 中身

| 場所 | 役割 |
|---|---|
| `Shared/` | 決まり（雪玉の大きさ、積む条件、完成、高さ、位置の格子、期間、順位、名前、都道府県）、歩数の台帳。画面なしで単体テストできる |
| `App/Data/` | 塔の置き場。`TowerRepository`（本体は CloudKit、メモリ版は試験・画面確認用） |
| `App/Services/` | 位置情報、保存、「おけない理由」の文 |
| `App/UI/` | 画面（地図、塔、持っている雪玉、ランキング、きろく、せってい）と、やわらかい雪のスタイル（`Soft.swift`） |
| `App/AppModel.swift` | 画面から使う窓口 |
| `Tests/` | 単体テスト |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) の設定（`Yukikoro.xcodeproj` はここから生成） |

## 確認のしかた（Mac なし）

- 単体テスト・ビルド: push すると GitHub Actions の CI が動く。
- 画面: Actions →「画面の撮影（手動）」。見本の塔を置いた「デモ表示」で撮る（起動引数 `-yukikoro-demo`、DEBUG のみ）。
- CloudKit は署名のあるビルドでしか動かない。TestFlight の実機で確かめる。
