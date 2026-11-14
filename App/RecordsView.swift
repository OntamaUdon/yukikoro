import SwiftUI
import Charts

/// 直近7日の歩数と、これまでの記録
struct RecordsView: View {
    @Environment(GameStore.self) private var store

    private struct Day: Identifiable {
        let id: String
        let date: Date
        let steps: Int
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = DayKey.key(for: date)
            return Day(id: key, date: date, steps: store.state.creditedSteps(on: key))
        }
    }

    var body: some View {
        let list = days
        let total = list.reduce(0) { $0 + $1.steps }
        NavigationStack {
            List {
                Section("この7日間の歩数") {
                    Chart(list) { day in
                        BarMark(
                            x: .value("日", day.date, unit: .day),
                            y: .value("歩数", day.steps)
                        )
                        .foregroundStyle(Palette.tint.gradient)
                        .cornerRadius(5)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }
                    }
                    .frame(height: 190)
                    .padding(.vertical, 6)

                    LabeledContent("7日間の合計", value: "\(formatSteps(total))歩")
                    LabeledContent("1日の平均", value: "\(formatSteps(total / 7))歩")
                }

                Section("これまで") {
                    LabeledContent("転がした歩数", value: "\(formatSteps(store.state.totalSteps))歩")
                    LabeledContent("つくった雪だるま", value: "\(store.state.snowmen.count)体")
                    LabeledContent("ずかん", value: "\(store.state.discoveredKindCount) / \(GameState.totalKindCount)")
                    if let biggest = store.state.snowmen.max(by: { $0.steps < $1.steps }) {
                        LabeledContent("いちばん大きい雪だるま", value: "\(biggest.name)（\(formatSteps(biggest.steps))歩）")
                    }
                }

                Section {
                    Text("ヘルスケアに記録された歩数をもとにしています。ゆきころを入れる前の日も、直近7日ぶんは表示されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("きろく")
        }
    }
}
