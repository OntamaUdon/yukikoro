import SwiftUI

/// 持っている雪玉。大きさ、歩数、けずる。
struct CarrySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var shaveTarget: Double = 0

    var body: some View {
        let config = model.config
        let diameter = model.carriedDiameter
        let minBall = config.minBall
        let canShave = diameter > minBall + 0.005
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    SnowBallDisc(size: CGFloat(110 + min(130, 110 * pow(diameter, 0.5))))
                        .padding(.top, 10)
                    VStack(spacing: 4) {
                        Text(formatLength(meters: diameter))
                            .font(Soft.font(48))
                            .monospacedDigit()
                        Text("歩くほど、大きく育ちます（\(formatSteps(model.player.carriedSteps))歩ぶん）")
                            .font(Soft.font(13, .medium))
                            .foregroundStyle(Soft.subInk)
                    }
                    .foregroundStyle(Soft.ink)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("土台にするまで")
                            .font(Soft.font(14, .semibold))
                        SoftBar(fraction: diameter / config.minBase)
                        HStack {
                            Text(diameter + TowerRules.epsilon >= config.minBase
                                 ? "土台にできます"
                                 : "あと約\(formatSteps(max(0, BallSize.steps(forDiameter: config.minBase, config: config) - model.player.carriedSteps)))歩")
                            Spacer()
                            Text("\(formatLength(meters: config.minBase))から")
                        }
                        .font(Soft.font(12, .medium))
                        .foregroundStyle(Soft.subInk)
                    }
                    .foregroundStyle(Soft.ink)
                    .padding(18)
                    .softCard(radius: 24, depth: 0.8)

                    VStack(alignment: .leading, spacing: 12) {
                        Label("けずって、小さくする", systemImage: "scissors")
                            .font(Soft.font(14, .semibold))
                            .foregroundStyle(Soft.ink)
                        Text("小さい雪玉しか積めない塔に、のせたいときに。けずった歩数は、もどりません。")
                            .font(Soft.font(12, .medium))
                            .foregroundStyle(Soft.subInk)
                        if canShave {
                            HStack {
                                Text(formatLength(meters: minBall)).font(Soft.font(12, .medium))
                                Slider(value: $shaveTarget, in: minBall...max(minBall + 0.01, diameter))
                                    .tint(Soft.accent)
                                Text(formatLength(meters: shaveTarget)).font(Soft.font(12, .medium)).monospacedDigit()
                            }
                            .foregroundStyle(Soft.subInk)
                            Button {
                                model.shave(to: shaveTarget)
                                shaveTarget = model.carriedDiameter
                            } label: {
                                Text("この大きさまで、けずる")
                            }
                            .buttonStyle(SoftButtonStyle())
                            .disabled(shaveTarget >= diameter - 0.005)
                        } else {
                            Text("もう、けずれる大きさではありません")
                                .font(Soft.font(12, .medium))
                                .foregroundStyle(Soft.subInk)
                        }
                    }
                    .padding(18)
                    .softCard(radius: 24, depth: 0.8)
                }
                .padding(20)
            }
            .softScreen()
            .navigationTitle("持っている雪玉")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }.font(Soft.font(16))
                }
            }
            .onAppear { shaveTarget = model.carriedDiameter }
        }
        .presentationDetents([.large])
    }
}
