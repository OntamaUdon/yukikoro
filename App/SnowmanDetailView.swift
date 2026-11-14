import SwiftUI

struct SnowmanDetailView: View {
    let snowman: Snowman
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    SnowmanSceneView(snowman)
                        .frame(height: 340)
                        .padding(.top, 4)
                    VStack(spacing: 6) {
                        Text(snowman.name)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("\(snowman.tier.label)サイズ ・ \(snowman.species.rarity.label)")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("\(formatSteps(snowman.steps))歩ぶん転がしました")
                            .font(.system(.subheadline, design: .rounded))
                        Text(snowman.madeAt.formatted(date: .long, time: .omitted))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if !snowman.decorations.isEmpty {
                        VStack(spacing: 8) {
                            Text("つけているもの")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.secondary)
                            FlowLabels(labels: snowman.decorations.map { $0.kind.displayName })
                        }
                    }
                    ShareButton(snowman: snowman)
                        .padding(.top, 6)
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [Color(red: 0.88, green: 0.94, blue: 1.0), Color(red: 0.96, green: 0.98, blue: 1.0)],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("とじる") { dismiss() }
                }
            }
        }
    }
}

/// 飾りの名前を並べる小さなラベル
struct FlowLabels: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Palette.tint.opacity(0.14), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CompletionView: View {
    let result: CompletionResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let snowman = result.snowman
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.74, green: 0.88, blue: 0.98), Color(red: 0.96, green: 0.98, blue: 1.0)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
            SnowFall()
            VStack(spacing: 16) {
                Spacer(minLength: 12)
                if result.isNewKind {
                    Text("はじめて出会った！")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Palette.gold.opacity(0.35), in: Capsule())
                }
                SnowmanSceneView(snowman, popIn: true)
                    .frame(height: 340)
                Text("\(snowman.name)ができました")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("\(formatSteps(snowman.steps))歩ぶん転がしました")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                if !snowman.decorations.isEmpty {
                    FlowLabels(labels: snowman.decorations.map { $0.kind.displayName })
                }
                Spacer(minLength: 8)
                ShareButton(snowman: snowman)
                Button("とじる") { dismiss() }
                    .font(.system(.body, design: .rounded))
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
        }
        .presentationDetents([.large])
    }
}
