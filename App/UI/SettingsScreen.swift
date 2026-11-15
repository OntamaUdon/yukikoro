import SwiftUI

/// せってい。名前、位置情報、プライバシーの説明、データのリセット。試験版には「テスト」もある。
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    nameCard
                    privacyCard
                    if AppEnvironment.isBeta { testCard }
                    Button("データをリセットする", role: .destructive) { confirmReset = true }
                        .buttonStyle(SoftButtonStyle())
                        .confirmationDialog("歩数の記録と、ポイントを消します。おいた・積んだ雪だるまは、消えません。", isPresented: $confirmReset, titleVisibility: .visible) {
                            Button("リセットする", role: .destructive) { model.resetAll() }
                            Button("やめる", role: .cancel) {}
                        }
                }
                .padding(20)
            }
            .softScreen()
            .navigationTitle("せってい")
        }
    }

    // MARK: 名前

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("あなたの名前", systemImage: "person.fill")
                .font(Soft.font(14, .semibold))
            Text(model.player.nickname)
                .font(Soft.font(24))
            Text("名前は、決まった言葉から選べます。週の終わりの殿堂にだけ、出ます。")
                .font(Soft.font(12, .medium))
                .foregroundStyle(Soft.subInk)
            HStack(spacing: 10) {
                Menu {
                    ForEach(Array(Nickname.adjectives.enumerated()), id: \.offset) { index, word in
                        Button(word) { model.setNickname(adjective: index, animal: model.player.nickAnimal) }
                    }
                } label: {
                    Text(Nickname.adjectives[model.player.nickAdjective % Nickname.adjectives.count])
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle())
                Menu {
                    ForEach(Array(Nickname.animals.enumerated()), id: \.offset) { index, word in
                        Button(word) { model.setNickname(adjective: model.player.nickAdjective, animal: index) }
                    }
                } label: {
                    Text(Nickname.animals[model.player.nickAnimal % Nickname.animals.count])
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
        .foregroundStyle(Soft.ink)
        .padding(18)
        .softCard(radius: 26)
    }

    // MARK: プライバシー

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("あなたの場所のこと", systemImage: "lock.fill")
                .font(Soft.font(14, .semibold))
            Group {
                Text("・あなたの今いる場所は、サーバーに送りません。")
                Text("・おいた雪玉の位置は、約50m四方の中の、ランダムな点にずらして保存します。")
                Text("・名前・連絡先・写真は、ありません。ほかの人と話すこともできません。")
                Text("・位置は、アプリを開いている間だけ使います。")
            }
            .font(Soft.font(12, .medium))
            .foregroundStyle(Soft.subInk)
            HStack {
                Text("位置情報")
                Spacer()
                Text(model.location.isAuthorized ? "使えます" : (model.location.isDenied ? "許可されていません" : "まだ許可していません"))
                    .foregroundStyle(model.location.isAuthorized ? Soft.good : Soft.warn)
            }
            .font(Soft.font(13, .semibold))
        }
        .foregroundStyle(Soft.ink)
        .padding(18)
        .softCard(radius: 26)
    }

    // MARK: テスト（試験版だけ）

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("テスト（試験版だけ）", systemImage: "wrench.and.screwdriver.fill")
                .font(Soft.font(14, .semibold))
            HStack {
                Text("いまの期間")
                Spacer()
                Text(model.isReady ? model.periodId : "—").monospacedDigit()
            }
            .font(Soft.font(13, .semibold))
            Button {
                Task { await model.betaAdvanceWeek() }
            } label: {
                Label("週を終える（順位と殿堂を確かめる）", systemImage: "calendar.badge.checkmark")
            }
            .buttonStyle(SoftButtonStyle(prominent: true))

            Text("歩数を足す").font(Soft.font(12, .semibold)).foregroundStyle(Soft.subInk)
            HStack(spacing: 8) {
                ForEach([100, 1_000, 10_000, 100_000], id: \.self) { n in
                    Button("+\(formatSteps(n))") { model.betaAddSteps(n) }
                        .buttonStyle(SoftButtonStyle(radius: 16))
                        .font(Soft.font(12))
                }
            }
            Text("雪玉の大きさを決める").font(Soft.font(12, .semibold)).foregroundStyle(Soft.subInk)
            HStack(spacing: 8) {
                ForEach([(0.30, "30cm"), (0.50, "50cm"), (1.0, "1m"), (2.0, "2m")], id: \.1) { item in
                    Button(item.1) { model.betaSetBallSteps(BallSize.steps(forDiameter: item.0, config: model.config)) }
                        .buttonStyle(SoftButtonStyle(radius: 16))
                        .font(Soft.font(12))
                }
            }
            Button {
                model.betaResetUsage()
            } label: {
                Label("今日のおく・積む回数を戻す（\(model.usedToday)/\(model.config.dailyLimit)）", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(SoftButtonStyle())
            if model.location.testPoint != nil {
                Button {
                    model.betaClearTestPoint()
                } label: {
                    Label("テスト用の位置をやめる", systemImage: "location.slash")
                }
                .buttonStyle(SoftButtonStyle())
            } else {
                Text("塔の画面にある「この塔の位置へ移動」で、その場所にいることにできます（1 人でも積めます）。")
                    .font(Soft.font(11, .medium))
                    .foregroundStyle(Soft.subInk)
            }
        }
        .foregroundStyle(Soft.ink)
        .padding(18)
        .softCard(radius: 26)
    }
}
