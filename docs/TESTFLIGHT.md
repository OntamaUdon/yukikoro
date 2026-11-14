# TestFlight で、自分の iPhone に「ゆきころ」を入れるまで

はじめてでも迷わないように、順番にやることだけを書きます。
画面の名前や場所は Apple の更新で変わることがあります。違っていたら、似た名前の項目を探してください。

> **TestFlight とは**: Apple 公式の、アプリのテスト配信の仕組みです。アプリを App Store に公開する前に、自分や友だちの iPhone で試せます。インストールは iPhone の「TestFlight」アプリから行います。

---

## 0. 全体像（先に読んでください）

| 段階 | やること | 目安 |
|---|---|---|
| ① | Apple Developer Program に加入する（有料） | 申し込み10分＋審査（数時間〜数日） |
| ② | 自分の Bundle ID を決めて、プロジェクトに入れる | 10分 |
| ③ | App Store Connect で「アプリ」を作る | 15分 |
| ④ | ビルドを作って App Store Connect にアップロードする | 方式A（Macあり）30分／方式B（Macなし）1時間 |
| ⑤ | TestFlight でテスターを招待し、iPhone にインストールする | 15分＋処理待ち |

- **お金**: Apple Developer Program の年会費がかかります（99ドル／年。日本円ではおよそ1.5万円前後で、為替や税で変わります）。TestFlight 自体は無料です。
- **必要なもの**:
  - Apple ID（二段階認証をオンにしたもの）
  - iPhone（iOS 17 以降）
  - ③④の作業をする環境（次のどちらか）
    - **方式A: Mac ＋ Xcode 16 以降**（いちばん確実）
    - **方式B: Mac なし**（GitHub Actions の macOS を借りる。このリポジトリに用意済み。ただし**作者が認証情報なしで実行できていない未検証の手順**です）
- **シミュレーターでは歩数が動きません**。歩数の確認は実機（TestFlight）でします。

---

## 1. Apple Developer Program に加入する

1. https://developer.apple.com/programs/enroll/ を開き、Apple ID でサインインします。
2. 個人で加入する場合は「個人」を選びます（会社や団体名で出したいときだけ、D-U-N-S 番号が必要な「組織」を選びます）。
3. 本人確認、年会費の支払いを済ませます。
4. 承認のメールが届くまで待ちます（数時間〜数日）。
5. 承認されたら https://developer.apple.com/account にサインインして、右上や「Membership details（メンバーシップの詳細）」を開き、**Team ID（10文字の英数字）をメモ**します。

---

## 2. 自分の Bundle ID を決める

### Bundle ID とは
アプリの世界で唯一の名前です。他の人が使っている名前は使えません。ドメインを逆にした形で、
`com.自分の名前やハンドル.yukikoro` のようにします。

- 使えるのは **小文字の英数字、ハイフン、ドット** です。例: `com.taro.yukikoro`
- いまは仮の `com.example.yukikoro` が入っています。**そのままでは TestFlight に出せません**。

### 書き換える（コマンド1つ）
リポジトリのフォルダで次を実行します。Team ID が分かっていれば一緒に渡します。

```bash
python tools/set_bundle_id.py com.taro.yukikoro --team ABCDE12345
```

- 本当に書き換える前に内容を見たいときは、最後に `--dry-run` を付けます。
- 次の4つが一度に変わります（手で直す必要はありません）。
  - アプリ本体: `com.taro.yukikoro`
  - ウィジェット: `com.taro.yukikoro.widget`
  - テスト用: `com.taro.yukikoro.tests`
  - App Group（アプリとウィジェットでデータを共有する仕組み）: `group.com.taro.yukikoro`
- 変えたら、変更を git に保存（コミット）して push しておきます。

---

## 3. App Store Connect で「アプリ」を作る

ここは Web ブラウザだけでできます（MacもXcodeも要りません）。

1. https://appstoreconnect.apple.com にサインインします。
2. 「マイ App」を開き、「＋」→「新規 App」を選びます。
3. 次のように入力します。
   - **プラットフォーム**: iOS
   - **名前**: アプリの名前（App Store 上で他のアプリと重複できません。「ゆきころ」が使われていたら「ゆきころ - 雪だるま集め」など、少し変えます）
   - **プライマリ言語**: 日本語
   - **バンドル ID**: 手順2で決めた ID を選びます
     - **一覧に出ない場合**: 先に、下の「3-1」の手順でバンドル ID を登録してください。
   - **SKU**: 自分用の管理番号（何でもよい。例: `yukikoro-001`。後から変えられません）
   - **ユーザーアクセス**: 「フルアクセス」
4. 「作成」を押します。

### 3-1. バンドル ID が一覧に出ないとき（手でIDを登録する）
1. https://developer.apple.com/account を開き、「Certificates, Identifiers & Profiles（証明書、ID、プロファイル）」→「Identifiers（ID）」。
2. 「＋」→「App IDs」→「App」。
3. 説明に「ゆきころ」、Bundle ID に「Explicit」で `com.taro.yukikoro` を入れます。
4. 「Capabilities（機能）」の一覧で、**HealthKit** と **App Groups** にチェックを入れて登録します。
5. 同じ手順でウィジェット用も作ります（`com.taro.yukikoro.widget`、機能は **App Groups** だけでよい。HealthKit も付けておくと安全です）。
6. 左の「Identifiers」の絞り込みを「App Groups」にして「＋」で `group.com.taro.yukikoro` を登録します。
7. 作った2つの App ID を開き、「App Groups」の「Edit」で、登録した App Group を選んで保存します。

> 方式Aで Xcode の自動署名（Automatically manage signing）を使う場合は、Xcode が上の登録を自動でしてくれることが多いです。うまくいかないときだけ、この手順を手でやります。

---

## 4A. 【方式A: Mac あり】ビルドして TestFlight にアップロード

### 準備
- Mac に **Xcode 16 以降**を入れます（Mac App Store から無料）。
- Xcode の「Settings → Accounts」で、Developer Program に加入した Apple ID を追加します。

### 手順
1. リポジトリを Mac に取得します。
   ```bash
   git clone https://github.com/<あなたのアカウント>/yukikoro.git
   cd yukikoro
   ```
2. `Yukikoro.xcodeproj` をダブルクリックして Xcode で開きます。
   - 手順2のコマンドを Mac で実行する場合は、先にそれを済ませてから開きます。
   - `project.yml` を直接変えた場合だけ、`brew install xcodegen` のあと `xcodegen generate` で作り直します。
3. 左のファイル一覧で一番上の **Yukikoro（青いアイコン）** を選び、**TARGETS** の中の次の**2つ**それぞれで設定します。
   - **Yukikoro**（アプリ本体）
   - **YukikoroWidget**（ウィジェット）
   - 「Signing & Capabilities」タブを開き、
     - 「Automatically manage signing」に**チェック**
     - 「Team」に自分の Team（Developer Program のもの）を選択
     - 「Bundle Identifier」が手順2で決めた ID になっているか確認
     - **HealthKit** と **App Groups** が表示され、App Group の中身が `group.com.taro.yukikoro` になっているか確認（赤い警告が出ていれば、クリックして Xcode に直させます）
4. 実機で動かして確認します（任意ですが、強く推奨）。
   - iPhone を USB でつなぎ、画面上部の実行先で自分の iPhone を選んで「▶」を押します。
   - 初回は iPhone の「設定 → プライバシーとセキュリティ → デベロッパモード」をオンにして再起動します。
   - 「信頼されていないデベロッパ」と出たら、「設定 → 一般 → VPNとデバイス管理」で自分のアカウントを信頼します。
5. **実行先を「Any iOS Device (arm64)」にして**、メニューの「Product → Archive」を選びます（シミュレーターを選んだままだと Archive は選べません）。
6. 完了すると「Organizer」が開きます。ビルドを選び、「Distribute App」→「App Store Connect」→「Upload」の順に進み、基本は表示される初期設定のまま「Next」を押していきます。
7. 「Upload Successful」と出たら完了です。**ビルドが App Store Connect に出てくるまで、数分〜30分ほど**かかります（メールで届くこともあります）。

> 2回目以降は、ビルド番号（Xcode の「General → Build」）を**前より大きく**してからアーカイブしてください。同じ番号は受け付けられません。

---

## 4B. 【方式B: Mac なし】GitHub Actions でアップロード

> **注意**: この方式は、作者が認証情報を持っておらず、**実際に動かして確認できていません**。失敗したら、Actions のログ（赤いステップ）を見て、書かれているエラーを手がかりに調整します。確実に出したいなら、Mac を借りられる人に方式Aで1回だけ出してもらうのも手です。

### 準備1: App Store Connect API キーを作る
1. App Store Connect を開き、「ユーザとアクセス」→「統合」→「App Store Connect API」。
2. 「キーを生成」。名前は何でもよく、**アクセス権は「App Manager」以上**にします。
3. 次の3つを**必ず控えます**。
   - **Issuer ID**（ページ上部に表示される長い ID）
   - **Key ID**（キー一覧に出る10文字）
   - **`AuthKey_XXXXXXXXXX.p8` ファイル**（**ダウンロードは一度しかできません**。無くしたら作り直しです）
4. **.p8 ファイルは秘密鍵です。人に渡したり、チャットに貼ったり、GitHub に置いたりしないでください。**

### 準備2: 手順3（アプリの作成と、必要なら 3-1 のID登録）を済ませる
方式Bでは Xcode の代わりに自動署名を API キーで行うので、**ID と App Group を先に登録しておくと失敗しにくい**です（3-1 を実施）。

### 準備3: GitHub に秘密情報を登録する
リポジトリの「Settings → Secrets and variables → Actions」で、「New repository secret」から次の4つを追加します。
（GitHub CLI を使う場合は、`gh secret set 名前` で追加できます。）

| 名前 | 中身 |
|---|---|
| `ASC_TEAM_ID` | 手順1でメモした Team ID |
| `ASC_KEY_ID` | API キーの Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | .p8 ファイルの**中身を全部**（`-----BEGIN PRIVATE KEY-----` から `-----END PRIVATE KEY-----` まで） |

### 実行
1. 手順2の書き換えをコミットして push 済みであること。
2. GitHub のリポジトリで「Actions」→「TestFlight にアップロード（手動）」→「Run workflow」。
3. 緑になれば、数分〜30分で App Store Connect にビルドが出ます。
4. 2回目以降は、もう一度「Run workflow」を押すだけです。**ビルド番号は実行ごとに自動で増えます**。

---

## 5. TestFlight でテスターを招待し、インストールする

### 5-1. ビルドの確認（初回だけ）
1. App Store Connect のアプリを開き、「TestFlight」タブを開きます。
2. ビルドが「処理中」から変わるのを待ちます。
3. 「輸出コンプライアンス」の質問は出ないはずです（Info.plist に「暗号化を使わない」と設定済みのため）。もし出たら「いいえ（標準の暗号化のみ）」を選びます。

### 5-2. 自分だけで試す（いちばん簡単）
1. 「内部テスト」の横の「＋」で内部テストのグループを作り、自分（Developer Program の Apple ID）をテスターに入れます。
   - 内部テスターは、**App Store Connect のユーザ**（最大100人）です。**審査は要りません**。
2. グループにビルドを追加します。
3. iPhone に **TestFlight アプリ**（App Store で「TestFlight」と検索、無料）を入れ、同じ Apple ID でサインインします。
4. TestFlight アプリに「ゆきころ」が出るので、「インストール」を押します。

### 5-3. 友だちにも配る（外部テスト）
1. 「外部テスト」でグループを作り、テスターをメールで追加するか、**公開リンク**を作って共有します。
2. 外部に配る最初のビルドには、**ベータ版 App 審査（Beta App Review）**が入ります（通常1日以内。内部テストには要りません）。
3. 次の情報を入力するよう求められます。
   - **テスト内容（What to Test）**: 例は次のとおり。
     > 歩くと雪玉が大きくなります。歩数が増えるか、雪だるまを作れるか、図鑑・共有・ウィジェットが動くかを試してください。気になったことは TestFlight のフィードバックで送ってください。
   - **ベータ版 App の説明**、**連絡先メール**、**フィードバック用メール**
   - **プライバシーポリシーの URL**（[PRIVACY.md](../PRIVACY.md) の内容を、誰でも開ける Web ページとして公開して、その URL を入れます。GitHub Pages や、ブログ、Notion の公開ページなどで構いません）
4. 招待された人は、メールのリンクか公開リンクを iPhone で開いて TestFlight アプリから入れます。

> **注意**: TestFlight のビルドは、**アップロードから90日で期限切れ**になります。長く試すときは、期限前に新しいビルドを出してください。

---

## 6. 実機でのチェックリスト

TestFlight で入れたら、次を確認します（企画書 [DESIGN.md](../DESIGN.md) の「TestFlight で確かめること」と同じです）。

- [ ] 初回起動で説明画面が出て、「はじめる」でヘルスケアの許可を聞かれる
- [ ] 許可後、歩くとホームの歩数が増え、雪玉が大きくなる
- [ ] 歩いたのに増えない場面がない（取りこぼしがない）
- [ ] 設定の「バージョン」を**5回タップ**すると「テスト用」メニューが出て、歩数を足せる（雪だるまの完成や、30,000歩の上限の確認に使えます）
- [ ] 「雪だるまにする」で完成の演出が出て、ずかんに登録される
- [ ] 共有ボタンで画像を送れる
- [ ] ホーム画面にウィジェットを追加できて、雪玉が表示される
- [ ] 画面が重くない、電池の減りが極端でない
- [ ] 夜に開くと、夜の背景になる

---

## 7. うまくいかないとき

| 症状 | 原因と対処 |
|---|---|
| Xcode で「No profiles for 'com.…' were found」 | Team が未選択、または ID が登録されていません。Team を選び、「Automatically manage signing」にチェック。直らなければ手順 3-1 で ID を手で登録します。 |
| 「App Group … is not available」や App Groups が赤い | App Group を作成できていません。Signing & Capabilities の App Groups の「＋」で `group.…` を追加、または 3-1 の 6〜7 を実施します。 |
| HealthKit が使えないとエラー | App ID の Capabilities に HealthKit が入っていません（3-1 の 4）。 |
| 「Bundle ID が一致しない」「アプリが見つからない」 | App Store Connect に作ったアプリの Bundle ID と、プロジェクトの ID が違います。手順2をやり直します。 |
| アップロードしたのにビルドが出ない | 処理待ちです。最大1時間ほど待ちます。「Apple からのメール」に無効なビルドの理由が届くこともあります。 |
| 「ビルド番号が既に使われている」 | 同じビルド番号は出せません。番号を増やして再アップロード（方式Bは自動で増えます）。 |
| TestFlight アプリに出ない | ビルドをテストグループに追加したか、招待メールを承認したか、TestFlight に同じ Apple ID でサインインしているか確認。 |
| 実機にインストールしたら歩数が 0 のまま | ヘルスケアの許可がオフです。「設定 → プライバシーとセキュリティ → ヘルスケア → ゆきころ」で歩数の読み取りをオンにします。 |
| ウィジェットの雪玉が表示されない／古い | アプリを一度開くと更新されます。それでも出ない場合、App Group の設定（Bundle ID を変えたのに `group.…` が古いまま）が原因のことが多いです。手順2のスクリプトで直ります。 |
| 方式B: ワークフローが赤い | 赤いステップのログの最後を読みます。Secrets の入力ミス（.p8 の途中が欠けている）、ID や App Group の未登録、API キーの権限不足が多い原因です。 |

---

## 8. App Store に公開する場合に、さらに必要なもの（今回は不要）

- プライバシーポリシーの公開 URL（TestFlight の外部テストでも必要）
- App Store 用のスクリーンショット、説明文、キーワード、年齢制限の回答
- 審査でのヘルスケア（歩数）の使用目的の説明（アプリは「雪玉を育てるために歩数を読み取る」だけで、外部に送信しません）
- 雪だるまは冬の題材なので、**出すなら冬のうち**がおすすめです（[DESIGN.md](../DESIGN.md) の「季節性リスク」）。

---

## 付録: 設定ファイルのありか

| 内容 | ファイル |
|---|---|
| Bundle ID・Team・バージョン | `project.yml`（元の設定）、`Yukikoro.xcodeproj`（Xcode 用に生成済み） |
| 権限（HealthKit・App Group） | `App/Yukikoro.entitlements`、`Widget/YukikoroWidget.entitlements` |
| ヘルスケア許可の説明文・暗号化の申告 | `App/Info.plist` |
| App Group 名（アプリ内） | `Shared/Storage.swift` の `SharedConfig.appGroup` |
| 一括書き換え | `tools/set_bundle_id.py` |
| 方式B のワークフロー | `.github/workflows/testflight.yml` |
