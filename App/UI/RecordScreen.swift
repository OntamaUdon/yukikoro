import SwiftUI

/// きろく: 自分が参加した塔、ポイント、名前。
struct RecordScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summary
                    if model.record.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 34))
                                .foregroundStyle(Soft.accent.opacity(0.7))
                            Text(model.recordLoading ? "読みこみ中…" : "まだ、参加した雪だるまがありません")
                                .font(Soft.font(14, .medium))
                                .foregroundStyle(Soft.subInk)
                        }
                        .padding(36)
                    } else {
                        ForEach(model.record) { entry in
                            row(entry)
                        }
                    }
                }
                .padding(20)
            }
            .softScreen()
            .navigationTitle("きろく")
            .refreshable { await model.loadRecord() }
            .task { await model.loadRecord() }
        }
    }

    private var summary: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                SnowBallDisc(size: 54, face: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.player.nickname)
                        .font(Soft.font(20))
                    Text("あなたの名前（殿堂に出ます）")
                        .font(Soft.font(11, .medium))
                        .foregroundStyle(Soft.subInk)
                }
                .foregroundStyle(Soft.ink)
                Spacer()
            }
            HStack(spacing: 10) {
                stat("star.fill", "\(formatSteps(model.player.points))", "ポイント", tint: Soft.gold)
                stat("circle.fill", "\(model.player.placedCount)", "おいた")
                stat("arrow.down.to.line", "\(model.player.stackedCount)", "のせた")
            }
        }
        .padding(18)
        .softCard(radius: 26)
    }

    private func stat(_ symbol: String, _ value: String, _ title: String, tint: Color = Soft.accent) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value).font(Soft.font(20)).monospacedDigit()
            Text(title).font(Soft.font(11, .medium)).foregroundStyle(Soft.subInk)
        }
        .foregroundStyle(Soft.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .softWell(radius: 18)
    }

    private func row(_ entry: RecordEntry) -> some View {
        let tower = entry.tower
        let closed = tower.isClosed(config: model.config)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formatLength(meters: tower.height))
                        .font(Soft.font(24))
                        .monospacedDigit()
                    Text("\(tower.balls.count)こ").font(Soft.font(13, .medium)).foregroundStyle(Soft.subInk)
                }
                HStack(spacing: 8) {
                    SoftChip(symbol: "mappin.and.ellipse", text: Prefecture.name(code: tower.prefecture))
                    if closed { SoftChip(symbol: "sparkles", text: "完成", tint: Soft.good) }
                    SoftChip(symbol: "calendar", text: tower.periodId)
                }
            }
            .foregroundStyle(Soft.ink)
            Spacer()
            Text("\(entry.myBallIDs.count)こ\n参加")
                .font(Soft.font(11, .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Soft.subInk)
        }
        .padding(16)
        .softCard(radius: 22, depth: 0.7)
    }
}
