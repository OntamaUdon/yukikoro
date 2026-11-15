import SwiftUI

/// 順位と殿堂。高さが高い順。県ごと・全国。前の週の殿堂には、積んだ人の名前も出す（場所は出さない）。
struct RankingScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showHall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("期間", selection: $showHall) {
                        Text("今週").tag(false)
                        Text("前の週（殿堂）").tag(true)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Menu {
                            Button("全国") { setPrefecture(nil) }
                            ForEach(1...47, id: \.self) { code in
                                Button(Prefecture.name(code: code)) { setPrefecture(code) }
                            }
                        } label: {
                            Label(model.rankingPrefecture.map { Prefecture.name(code: $0) } ?? "全国", systemImage: "mappin.and.ellipse")
                                .font(Soft.font(15))
                                .foregroundStyle(Soft.ink)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .softCard(radius: 18, depth: 0.6)
                        }
                        Spacer()
                        Text(showHall ? (model.previousPeriodId ?? "") : model.periodId)
                            .font(Soft.font(12, .medium))
                            .foregroundStyle(Soft.subInk)
                    }

                    let towers = showHall ? model.hall : model.ranking
                    if let error = model.rankingError {
                        Text(error)
                            .font(Soft.font(14, .medium))
                            .foregroundStyle(Soft.subInk)
                            .padding(30)
                    } else if towers.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: showHall ? "trophy" : "snowflake")
                                .font(.system(size: 34))
                                .foregroundStyle(Soft.accent.opacity(0.7))
                            Text(model.rankingLoading || model.hallLoading
                                 ? "読みこみ中…"
                                 : (showHall ? "前の週の殿堂は、まだありません" : "今週の雪だるまは、まだありません。最初の土台をおいてみましょう"))
                                .font(Soft.font(14, .medium))
                                .foregroundStyle(Soft.subInk)
                                .multilineTextAlignment(.center)
                        }
                        .padding(36)
                    } else {
                        ForEach(Array(towers.enumerated()), id: \.element.id) { index, tower in
                            row(rank: index + 1, tower: tower, showNames: showHall)
                        }
                    }
                }
                .padding(20)
            }
            .softScreen()
            .navigationTitle("ランキング")
            .refreshable { await model.loadRanking() }
            .task { await model.loadRanking() }
            .onChange(of: model.betaSeq) { _, _ in Task { await model.loadRanking() } }
        }
    }

    private func setPrefecture(_ code: Int?) {
        model.rankingPrefecture = code
        Task { await model.loadRanking() }
    }

    private func row(rank: Int, tower: Tower, showNames: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(rank)")
                .font(Soft.font(22))
                .foregroundStyle(rank <= 3 ? Soft.gold : Soft.subInk)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formatLength(meters: tower.height))
                        .font(Soft.font(26))
                        .monospacedDigit()
                    Text("\(tower.balls.count)こ").font(Soft.font(13, .medium)).foregroundStyle(Soft.subInk)
                    Spacer()
                    Text(Prefecture.name(code: tower.prefecture)).font(Soft.font(12, .semibold)).foregroundStyle(Soft.subInk)
                }
                if showNames {
                    Text(tower.nicks.joined(separator: "、"))
                        .font(Soft.font(12, .medium))
                        .foregroundStyle(Soft.subInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Soft.ink)
        }
        .padding(16)
        .softCard(radius: 22, depth: 0.7)
    }
}
