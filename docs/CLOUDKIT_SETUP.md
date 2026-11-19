# CloudKit の登録手順（あなたが行う作業・くわしい版）

アプリのコードは、この手順のとおりに登録すれば動くように、もう作ってあります。
**ここだけは、あなたの Apple アカウントでしかできません。** 所要時間の目安は 30〜60 分です。

## 0. まず、全体の流れと言葉の説明

### なぜ必要なのか
このアプリは「みんなの雪だるま」を、全員で共有します。そのためには、インターネット上に、データをためておく場所が要ります。
その場所に、Apple が無料で用意している **CloudKit（クラウドキット）** を使います。自分でサーバーを借りる必要はありません。
ただし、使うには「このアプリは、この置き場を使います」と Apple に**登録**する必要があります。それがこの手順です。

### 出てくる言葉
| 言葉 | 意味 |
|---|---|
| **Apple Developer** | アプリを作る人向けの Apple のサイト。有料の登録（年額）が済んでいる前提です |
| **App ID / Identifier** | アプリの「身分証」。このアプリは `com.ontamaudon.yukikoro` |
| **Capability（ケイパビリティ）** | アプリに許す「機能」。ここでは iCloud |
| **コンテナ（Container）** | データをためる「箱」の名前。このアプリは `iCloud.com.ontamaudon.yukikoro` |
| **CloudKit Dashboard** | 箱の中身の設計図（どんなデータを入れるか）を作る、別のサイト |
| **Record Type（レコードタイプ）** | 「データの種類」。表計算でいう「シート」。ここでは 5 つ作る |
| **Field（フィールド）** | 種類の中の「項目」。表計算でいう「列」 |
| **Index（インデックス）** | 検索や並べ替えを速く・可能にする「しかけ」。付け忘れると、データが読めません |
| **Development / Production** | 「練習用の環境」と「本番の環境」。**最初に練習用で作り、最後に本番へコピーする** |

### 4 つのステップ
1. App ID に iCloud を足す（developer.apple.com）
2. コンテナ（箱）を作り、アプリに結びつける（developer.apple.com）
3. CloudKit Dashboard で、データの設計図を作る → 本番へコピーする
4. TestFlight で動かして確かめる

> **いちばん大事な注意**: 名前（`com.ontamaudon.yukikoro` や `iCloud.com.ontamaudon.yukikoro`）は、**1 文字も変えないでください**。コードにそのまま書いてあります。ただし、手順 2 の Description（説明）だけは別で、何でも構いません。

---

## 1. App ID に iCloud を足す

**場所**: <https://developer.apple.com/account>

1. サインインして、**Certificates, Identifiers & Profiles**（証明書、識別子、プロファイル）をクリックします。
2. 左のメニューの **Identifiers**（識別子）をクリックします。
3. 一覧から `com.ontamaudon.yukikoro` をクリックします。（名前は「ゆきころ」などになっていることがあります。右側の Identifier 欄で見分けます。）
4. 下にスクロールして、**Capabilities**（機能）の一覧から **iCloud** を探し、**チェックを入れます**。
5. チェックの横に出る **Configure**（または Edit）ボタンはあとで使います。まず、選択肢が出たら **Include CloudKit support** を選びます。
   - 「Xcode 5 compatible」と書かれたほうは**選ばない**でください。古い方式です。
6. 右上の **Save**（保存）→ 確認が出たら **Confirm**。

**できたかの見分け方**: もう一度同じ App ID を開いて、iCloud にチェックが入っていれば成功です。

---

## 2. コンテナ（データの箱）を作る

### 2-1. 箱を作る
1. 同じ Identifiers の画面の、**左上にあるプルダウン**（初期は「App IDs」）をクリックして、**iCloud Containers** に切りかえます。
2. 右上の **＋** ボタンをクリックします。
3. 2 つの欄を入れます。
   - **Description（説明）**: `yukikoro`
     - Apple 側の管理用の名前です。アプリの画面には出ません。
     - **日本語は「invalid（正しくない）」と出ます。英数字にしてください。**
   - **Identifier（識別子）**: `iCloud.com.ontamaudon.yukikoro`
     - **ここは、一文字も変えないでください。** 頭の `iCloud.` も必要です。
4. **Continue** → 内容を確かめて **Register**（登録）。

### 2-2. 箱を、アプリに結びつける
1. 左上のプルダウンを **App IDs** に戻して、`com.ontamaudon.yukikoro` を開きます。
2. iCloud の横の **Configure**（または Edit）をクリックします。
3. いま作った `iCloud.com.ontamaudon.yukikoro` に**チェック**を入れて、**Continue** → **Save** → **Confirm**。

**できたかの見分け方**: App ID の画面の iCloud の欄に、コンテナ名が出ていれば成功です。

> TestFlight に送る作業は「自動で署名する」設定にしてあるので、ここまで済めば、署名（アプリの証明）にも iCloud が入ります。
> もし、あとで TestFlight への送信が「署名」や「provisioning profile」というエラーで止まったら、エラーの文面を私に貼ってください。

---

## 3. CloudKit Dashboard で、データの設計図を作る

**場所**: <https://icloud.developer.apple.com/dashboard>
（手順 1 と同じ Apple ID でサインインします。）

### 3-0. 最初にやること
1. `iCloud.com.ontamaudon.yukikoro` のコンテナをクリックして開きます。
2. 画面のどこかに **Development** と **Production** の切りかえがあります。**今は必ず「Development」を選びます。**
   - 練習用の環境なので、間違えても、やり直せます。
3. 左のメニューの **Schema**（スキーマ＝設計図）の中の **Record Types** を開きます。

### 3-1. データの種類（Record Type）を 5 つ作る

**作り方（1 つぶん）**
1. Record Types の画面の **＋**（New Type）をクリックします。
2. 上の名前の欄に、種類の名前を入れます（例: `Tower`）。
3. **Add Field**（項目を足す）をクリックして、**項目名**と**型**（Type）を入れます。項目の数だけ繰り返します。
4. 右下の **Save**（保存）。

> **名前は、大文字・小文字まで、下の表のとおりに。** 例えば `towerID` を `towerId` や `TowerID` にすると動きません。
> 型の名前は、画面で次のように出ます。「Int(64)」は整数、「Double」は小数、「String」は文字、「Location」は緯度と経度です。

#### ① `Tower`（塔。土台をおいた人が作る）
| 項目名 | 型 | 入れる中身 |
|---|---|---|
| `location` | Location | 塔の場所（約 50m 四方の中のランダムな点） |
| `periodId` | String | どの週の塔か（例: `2026-W47`） |
| `prefecture` | Int(64) | どの県か（1〜47） |

#### ② `Ball`（雪玉。積んだ人が作る）
| 項目名 | 型 | 入れる中身 |
|---|---|---|
| `towerID` | String | どの塔の雪玉か |
| `index` | Int(64) | 下から何番目か（0 が土台） |
| `diameter` | Double | 直径（メートル） |
| `cumHeight` | Double | ここまでの塔の高さ（メートル） |
| `ownerHash` | String | 持ち主を見分ける印（名前そのものではありません） |
| `nick` | String | 殿堂に出す名前（例: ふわふわのペンギン） |
| `look` | Int(64) | 雪玉の見た目の番号 |
| `periodId` | String | どの週か |
| `prefecture` | Int(64) | どの県か |

#### ③ `Report`（通報）
| 項目名 | 型 |
|---|---|
| `towerID` | String |
| `periodId` | String |
| `reason` | Int(64) |

#### ④ `Config`（設定データ。管理者だけが書く。**なくても動く**）
| 項目名 | 型 |
|---|---|
| `json` | String |

#### ⑤ `BetaClock`（試験版の「週を終える」ボタン用。試験の間だけ使う）
| 項目名 | 型 |
|---|---|
| `seq` | Int(64) |

> **`recordName` などは、自動で付く項目です。** 自分で足さなくて構いません。

### 3-2. インデックス（検索のしかけ）を付ける

**これを忘れるのが、いちばん多い失敗です。** 付けないと、アプリの画面に「つながりませんでした」と出て、データが読めません。

**付け方（1 つぶん）**
1. 左メニューの **Schema → Indexes** を開き、**＋**（Add Index）をクリックします。（Record Types の画面の **Edit Indexes ↗** からも開けます。）
2. 「Add Index」の画面で、次の 4 つの欄を入れます。
   - **Record Type**: どの種類か（例: `Tower`）。**毎回、合っているか確かめる。**
   - **Name**: インデックスの**名前**。あなたが決める管理用のラベルで、動きには関係しません。**項目ではありません。** 下の一覧のとおり、`項目名_種類` の形で入れます（例: `location_queryable`）。英数字とアンダースコアだけ。
   - **Type**: `QUERYABLE`（探す）か `SORTABLE`（並べ替える）。
   - **Field**: どの**項目**に付けるか。▼ から選びます（例: `location`）。
3. **Add** をクリックします。
4. 次のインデックスのために、また ＋ から繰り返します。

**種類の意味**
- **QUERYABLE**: 「この項目で探す」ができる。
- **SORTABLE**: 「この項目で並べ替える」ができる。
- 迷ったら、**QUERYABLE も SORTABLE も付けて構いません**（多めで困ることはありません）。

**付ける一覧（全部で 16 個。Name はコピーして使えます）**

| Record Type | Name | Type | Field |
|---|---|---|---|
| Tower | `recordName_queryable` | QUERYABLE | `recordName` |
| Tower | `location_queryable` | QUERYABLE | `location` |
| Tower | `periodId_queryable` | QUERYABLE | `periodId` |
| Tower | `prefecture_queryable` | QUERYABLE | `prefecture` |
| Ball | `recordName_queryable` | QUERYABLE | `recordName` |
| Ball | `towerID_queryable` | QUERYABLE | `towerID` |
| Ball | `index_sortable` | SORTABLE | `index` |
| Ball | `cumHeight_sortable` | SORTABLE | `cumHeight` |
| Ball | `periodId_queryable` | QUERYABLE | `periodId` |
| Ball | `prefecture_queryable` | QUERYABLE | `prefecture` |
| Ball | `ownerHash_queryable` | QUERYABLE | `ownerHash` |
| Report | `recordName_queryable` | QUERYABLE | `recordName` |
| Report | `periodId_queryable` | QUERYABLE | `periodId` |
| Report | `towerID_queryable` | QUERYABLE | `towerID` |
| Config | `recordName_queryable` | QUERYABLE | `recordName` |
| BetaClock | `recordName_queryable` | QUERYABLE | `recordName` |

**気をつけること**
- 別の種類に、同じ Name（例: `recordName_queryable`）を付けて大丈夫です。名前は、種類ごとに別々です。
- 「同じ名前がある」と言われたら、末尾に `2` を付けます。
- `index_sortable` と `cumHeight_sortable` だけ、Type を **SORTABLE** に切りかえます。
- Name が空欄でも通る場合があります。ただし、あとで見分けやすいので、入れておくのをおすすめします。
- 付け終えたら、Schema → Indexes の一覧で、16 個そろっているか確かめます。

### 3-3. 権限（だれが何をしていいか）を決める

**場所**: 左のメニューの **Security Roles**（セキュリティロール）。**Public Database**（公開データベース）のほうを選びます。

3 つの立場があります。
- **World（ワールド）**: iCloud にサインインしていない人も含む、だれでも
- **Authenticated（オーセンティケイテッド）**: iCloud にサインインしている人（＝ふつうのアプリの利用者）
- **Creator（クリエイター）**: その記録を作った本人

**設定表**（「読める」＝Read、「作れる」＝Create、「書ける」＝Write）
| レコードの種類 | World | Authenticated | Creator |
|---|---|---|---|
| Tower | 読める | 読める・作れる | 読める・書ける |
| Ball | 読める | 読める・作れる | 読める・書ける |
| Report | 読めない | 作れる | 読める・書ける |
| Config | 読める | 読める | 読める・書ける |
| **BetaClock** | 読める | **読める・作れる・書ける** | 読める・書ける |

**考え方（なぜこうなっているか）**
- 塔と雪玉は、**他の人の記録を書きかえません**。積むときは、新しい雪玉の記録を**作る**だけです。だから、Authenticated は「作れる」までで足ります。これは、いたずらで他人の塔を書きかえられないようにするためです。
- 通報は、**読めない**ようにして、他人の通報を見られなくします。
- `BetaClock` だけは、試験の間だけの特別あつかいです。「週を終える」ボタンは、**1 つの記録を、みんなが書きかえる**ので、Authenticated に「書ける」が要ります。

### 3-4. 本番へコピーする（Deploy）

練習用（Development）で作った設計図を、本番（Production）へコピーします。**TestFlight は、本番の環境を使います**。これをしないと、TestFlight で何も動きません。

1. 画面の **Deploy Schema Changes…**（スキーマの変更を反映する）をクリックします。
   - 見つからないときは、左下や右上、Schema の画面の上のほうを探してください。
2. 確認の画面で、内容（5 つの種類と、インデックス）を見て、**Deploy to Production** をクリックします。
3. 終わったら、画面の環境を **Production** に切りかえて、**Record Types の一覧に 5 つの種類が出ていて、インデックスも付いていること**を確かめます。
   - 権限（Security Roles）が本番に入っていない場合は、本番でも同じ表になっているか確かめてください。

> ⚠️ 本番に入れたあとで、項目を**消す・型を変える**ことはできません（足すことだけ可能）。間違えたときは、私に相談してください。

---

## 4. 動作確認（TestFlight）

**TestFlight（テストフライト）**: アプリをテストする人に、配るしくみです。**これはまだ、私は送っていません。あなたの許可を待ちます**（許可をもらえれば、私から送ることもできます）。

### 4-1. 送る（GitHub のボタン）
1. GitHub の `OntamaUdon/yukikoro` → **Actions** タブ。
2. 左の **TestFlight にアップロード（手動）** をクリック。
3. **Run workflow** → ブランチは **`v2-tower`** を選ぶ → **Run workflow**。
4. 数分から 10 分ほどで、App Store Connect → TestFlight に、新しいビルドが出ます（処理中の表示が消えるまで待つ）。

### 4-2. 2 人で試す（あなた＋もう 1 人）
どちらも、**iPhone の設定で iCloud にサインイン**している必要があります。

1. **1 人目（A さん）**
   1. アプリを開き、位置情報を許可。
   2. せってい → **テスト** → 「雪玉の大きさ」で **30cm** 以上を選ぶ。
   3. ちず（地図）で、**「ここに土台をおく」**。
2. **2 人目（B さん）**
   1. ちず（地図）に、A さんの塔が出ることを確かめる。
   2. 塔をタップ → 塔の画面で **「この塔の位置へ移動」**（同じ場所にいなくても、テスト用に、そこにいることにできる）。
   3. せってい → テスト → 雪玉の大きさを、塔の一番上より小さい大きさ（上の 80％ 以下）にして、塔の画面で **「のせる」**。
3. **ランキング**で、高さが出ることを確かめる。
4. せってい → テスト → **「週を終える」** → ランキングの **「前の週（殿堂）」** に、名前つきで出ることを確かめる。

### うまくいかないとき
| 症状 | 原因と対処 |
|---|---|
| 地図の下に「iCloud にサインインすると…」と出る | iPhone の 設定 → いちばん上の自分の名前 → iCloud で、サインイン |
| 「この操作は、まだ許可されていません」 | 3-3 の権限（Security Roles）を見直す |
| 「つながりませんでした」が続く | 3-2 のインデックス不足、または 3-4 の本番への反映（Deploy）が未実施 |
| 土台をおけない | 位置情報の許可 / 雪玉が 30cm 未満 / 50m 以内に別の塔がある / 日本国外 / 今日の 20 回を使い切った |
| 塔に積めない | 自分が上に積んだ直後 / 50m より遠い / 雪玉が上の 80％ より大きい / 塔が閉じている |
| TestFlight に送るところで「署名」エラー | エラーの文面を私に貼る（手順 1・2 の見直しが必要かも） |

---

## 5. あとで（いまは要らない）

- **通知**（近くに塔ができた、積まれた）: App ID の Push Notifications と、CloudKit の購読が要ります。作るときに、またくわしい手順を書きます。
- **本番に出すとき**: `AppEnvironment.isBeta` を `false` にします。`BetaClock` は使わなくなります。`Config` に数値を入れると、アプリを更新せずに調整できます（`json` に `{"stackRatio":0.8,...}` の形）。
