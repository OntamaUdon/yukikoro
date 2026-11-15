# CloudKit の登録手順（ユーザーが行う作業）

アプリのコードは、この手順のとおりに登録すれば、動くように作ってあります。
**ここだけは、あなたの Apple アカウントでしかできません。** 所要時間は、慣れれば 30 分くらい。

- コンテナの名前（変えない）: `iCloud.com.ontamaudon.yukikoro`
- Bundle ID: `com.ontamaudon.yukikoro`
- 先に、いまの状態をまとめます: アプリは、iCloud（CloudKit）の権限を `App/Yukikoro.entitlements` に書いてあります（`project.yml` から生成）。通知（プッシュ）は、まだ使っていないので、設定は要りません。

---

## 1. App ID に iCloud を足す（developer.apple.com）

1. <https://developer.apple.com/account> → **Certificates, Identifiers & Profiles** → **Identifiers**。
2. `com.ontamaudon.yukikoro` を開く。
3. **Capabilities** の **iCloud** にチェック → **Include CloudKit support** を選ぶ（「Xcode 5 compatible」ではなく、CloudKit のほう）。
4. **Save**。

## 2. コンテナを作る

1. 同じ **Identifiers** 画面の左上のメニューを **iCloud Containers** にする。
2. **+** → Description: `ゆきころ`、Identifier: `iCloud.com.ontamaudon.yukikoro` → **Continue** → **Register**。
3. もう一度、手順 1 の App ID の画面へ戻り、iCloud の **Configure**（または Edit）で、いま作ったコンテナにチェックを入れて **Save**。

> TestFlight の書き出しは「自動署名」なので、ここまでで、プロファイルに iCloud が入ります。
> 万一、書き出しが署名のエラーで止まったら、エラーの文面を教えてください。

## 3. CloudKit Dashboard でデータの形を作る

<https://icloud.developer.apple.com/dashboard> を開き、コンテナ `iCloud.com.ontamaudon.yukikoro` を選ぶ。
**必ず「Development」の環境で作ってから、最後に「Production」へ反映（Deploy）する。**（TestFlight と本番は、Production の環境を使います。）

### 3.1 レコードの種類（Schema → Record Types → +）

次の 5 つを作る。**項目の名前と型は、そのとおりに。**（大文字・小文字も同じ）

**Tower**（塔。土台をおいた人が作る）

| 項目 | 型 |
|---|---|
| `location` | Location |
| `periodId` | String |
| `prefecture` | Int(64) |

**Ball**（雪玉。積んだ人が作る）

| 項目 | 型 |
|---|---|
| `towerID` | String |
| `index` | Int(64) |
| `diameter` | Double |
| `cumHeight` | Double |
| `ownerHash` | String |
| `nick` | String |
| `look` | Int(64) |
| `periodId` | String |
| `prefecture` | Int(64) |

**Report**（通報）

| 項目 | 型 |
|---|---|
| `towerID` | String |
| `periodId` | String |
| `reason` | Int(64) |

**Config**（設定データ。管理者だけが書く。なくても動く）

| 項目 | 型 |
|---|---|
| `json` | String |

**BetaClock**（試験版の「週を終える」ボタン用。試験の間だけ）

| 項目 | 型 |
|---|---|
| `seq` | Int(64) |

### 3.2 インデックス（各レコードの種類の Indexes）

| レコード | 項目 | 種類 |
|---|---|---|
| すべて | `recordName` | **Queryable** |
| Tower | `location` | **Queryable** |
| Tower | `periodId` | **Queryable** |
| Tower | `prefecture` | Queryable |
| Ball | `towerID` | **Queryable** |
| Ball | `index` | **Sortable** |
| Ball | `cumHeight` | **Sortable** |
| Ball | `periodId` | **Queryable** |
| Ball | `prefecture` | **Queryable** |
| Ball | `ownerHash` | **Queryable** |
| Report | `periodId` | **Queryable** |
| Report | `towerID` | Queryable |

> 迷ったら、Queryable は多めに付けて構いません。足りないと、アプリの画面に「つながりませんでした」や、読み込みの失敗が出ます。

### 3.3 権限（Security Roles）

Public Database の各レコードの種類について:

| レコード | World（だれでも） | Authenticated（iCloud にサインインした人） | Creator（作った人） |
|---|---|---|---|
| Tower | 読める | 読める・作れる | 読める・書ける |
| Ball | 読める | 読める・作れる | 読める・書ける |
| Report | 読めない | 作れる | 読める・書ける |
| Config | 読める | 読める | 読める・書ける |
| **BetaClock** | 読める | **読める・作れる・書ける** | 読める・書ける |

> BetaClock だけ、「他の人が作った 1 件を、みんなが書きかえる」ので、Authenticated に **書ける** を付けます（試験の間だけ）。
> Tower と Ball は、**他の人の記録を書きかえません**（積むときは、新しい Ball を作るだけ）。だから、Authenticated は「作れる」までで足ります。

### 3.4 本番へ反映（Deploy）

1. 左下の **Deploy Schema Changes…** → **Deploy to Production**。
2. 反映が終わったら、Production の環境でも、同じ形（レコードの種類・インデックス）が出ていることを確かめる。

---

## 4. 動作確認（TestFlight）

1. GitHub の Actions で、**TestFlight にアップロード（手動）** を、ブランチ `v2-tower` で実行する。
2. TestFlight に届いたら、2 台（2 人）で入れる。**2 人とも iCloud にサインインしていること。**
3. 1 人目: 設定 → テスト → 「雪玉の大きさ」を 30cm 以上にして、地図で「ここに土台をおく」。
4. 2 人目: 地図に、塔が出る → 塔の画面で、「この塔の位置へ移動」→「のせる」。（同じ場所にいなくても、テスト用の位置指定で積めます）
5. ランキングで、高さが出る。設定 → テスト → 「週を終える」→ ランキングの「前の週（殿堂）」に、名前つきで出る。

### うまくいかないとき
- 地図の下に「iCloud にサインインすると…」と出る → 端末の設定で iCloud にサインイン。
- 「この操作は、まだ許可されていません」 → 3.3 の権限。
- 「つながりませんでした」が続く → 3.2 のインデックス、または 3.4 の Deploy（Production への反映）が済んでいるか。
- 土台をおけない → 位置情報の許可、雪玉の大きさ（30cm 以上）、近くに塔がないこと。

## 5. あとで（いまは要らない）

- 通知（近くに塔ができた、積まれた）: プッシュ通知の設定（App ID の Push Notifications）と、CloudKit の購読を足すときに、また手順を書きます。
- 本番に出すとき: `AppEnvironment.isBeta` を `false` にする。`BetaClock` は、使わなくなります。`Config` に、数値を入れると、アプリを更新せずに調整できます（`json` に `{"stackRatio":0.8,...}` の形）。
