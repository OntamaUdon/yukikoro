import WidgetKit
import SwiftUI

struct YukikoroEntry: TimelineEntry {
    let date: Date
    let state: GameState
}

struct YukikoroProvider: TimelineProvider {
    func placeholder(in context: Context) -> YukikoroEntry {
        var sample = GameState()
        sample.rollingSteps = 3_200
        return YukikoroEntry(date: Date(), state: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (YukikoroEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(YukikoroEntry(date: Date(), state: GameStorage.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<YukikoroEntry>) -> Void) {
        Task {
            var state = GameStorage.load()
            // アプリを開いていなくても最新に近い歩数を見せる。ここでは保存はせず、表示用に計算するだけ。
            // 実際の加算はアプリ側の同じ台帳ロジックで行われるので、二重には増えない。
            if state.initialized {
                let daily = await HealthSteps.dailySteps(days: 7)
                state.apply(daily: daily, todayKey: DayKey.key(for: Date()))
            }
            let entry = YukikoroEntry(date: Date(), state: state)
            let next = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct YukikoroWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: YukikoroEntry

    private var diameter: CGFloat {
        BallScale.diameter(steps: entry.state.rollingSteps, minimum: 34, maximum: family == .systemSmall ? 84 : 96)
    }

    var body: some View {
        switch family {
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var ball: some View {
        let side = diameter / 0.92
        return RollingBall(rotation: 0.6)
            .frame(width: side, height: side)
    }

    private var small: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            ball
            Text("\(formatSteps(entry.state.rollingSteps))歩")
                .font(.system(.headline, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
            Text(caption)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Palette.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var medium: some View {
        HStack(spacing: 8) {
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                ball
                Text("\(formatSteps(entry.state.rollingSteps))歩")
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                Text(caption)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.6))
            }
            .frame(maxWidth: .infinity)

            if let latest = entry.state.snowmen.last {
                VStack(spacing: 2) {
                    SnowmanView(latest)
                        .frame(maxWidth: 96, maxHeight: 96)
                    Text(latest.name)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("ぜんぶで\(entry.state.snowmen.count)体")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 4) {
                    Text("最初の雪だるまを\nつくろう")
                        .font(.system(.footnote, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.ink.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var caption: String {
        if let tier = entry.state.currentTier {
            return "\(tier.adjective)サイズ"
        }
        return "ころがし中"
    }
}

struct YukikoroWidget: Widget {
    let kind = "YukikoroWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: YukikoroProvider()) { entry in
            YukikoroWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.80, green: 0.91, blue: 0.99), Color(red: 0.95, green: 0.98, blue: 1.0)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("ゆきころ")
        .description("いま転がしている雪玉を、ホーム画面で見守れます。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct YukikoroWidgetBundle: WidgetBundle {
    var body: some Widget {
        YukikoroWidget()
    }
}
