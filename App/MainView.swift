import SwiftUI

/// ゆきころさんぽのメイン画面。歩くと雪玉が育つ。上限はなく、どこまでも大きくなる。
/// 小さいうちは雪玉が育つのが見え、画面いっぱいになったら、雪玉は同じ大きさのまま、まわりの目印（人・木・山）が小さくなっていく。
struct MainView: View {
    @Environment(GameStore.self) private var store
    @State private var showMenu = false
    /// 転がした分だけ回る雪玉の向き（ラジアン）
    @State private var angle: Double = 0

    private let shape = SnowShape.pristine(seed: 11)
    private var daypart: Daypart { Daypart.current(hour: Int(SkyClock.hour())) }

    var body: some View {
        ZStack {
            StoryBackground(daypart: daypart)
                .ignoresSafeArea()
            SnowFall(isDark: daypart.isDark)
            GeometryReader { geo in
                stage(size: geo.size)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer()
                infoCard
            }
        }
        .sheet(isPresented: $showMenu) { MenuSheet() }
        .onChange(of: store.state.rollingSteps) { old, new in
            guard new > old else { return }
            let r = max(0.02, BallScale.radius(steps: new))
            let turn = min(3 * Double.pi, max(0.5, Double(new - old) * 0.02 / r))
            withAnimation(.easeInOut(duration: 1.4)) { angle -= turn }
        }
    }

    // MARK: 舞台（雪玉と目印）

    private var extent: Double { Double(shape.maxExtent) }

    /// 雪玉のいちばん広い所の直径（メートル）
    private var ballDiameter: Double { store.state.diameter * extent }

    private func stage(size: CGSize) -> some View {
        let scale = StageScale.pixelsPerMeter(diameter: ballDiameter, width: size.width)
        let radius = CGFloat(store.state.radius) * scale
        let groundY = size.height * 0.58
        let center = CGPoint(x: size.width / 2, y: groundY - radius * 0.98)
        let limitPx = size.width * StageScale.maxBallFraction
        let visible = ScaleReference.all
            .map { ref -> (ref: ScaleReference, px: CGFloat, opacity: Double) in
                let px = CGFloat(ref.height) * scale
                return (ref, px, StageScale.opacity(forHeightPixels: px, limitPixels: limitPx))
            }
            .filter { $0.opacity > 0.02 }
            .sorted { $0.ref.height > $1.ref.height }
        let xs: [CGFloat] = [0.14, 0.86, 0.27, 0.73]

        return ZStack {
            Canvas { ctx, _ in
                SnowPainter.drawGroundShadow(in: &ctx, centerX: size.width / 2, groundY: groundY, width: max(radius * 2.4, 4), opacity: 0.28)
            }
            ForEach(Array(visible.enumerated()), id: \.element.ref.name) { index, item in
                referenceView(item.ref, pixels: item.px, opacity: item.opacity)
                    .position(x: size.width * xs[min(index, xs.count - 1)], y: groundY)
            }
            SnowBallView(shape: shape, radius: Double(radius), angle: angle)
                .position(center)
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeOut(duration: 1.0), value: scale)
    }

    /// 目印の絵と名前。下の端が地面に立つ。
    private func referenceView(_ ref: ScaleReference, pixels: CGFloat, opacity: Double) -> some View {
        let tone = daypart.isDark ? Color(red: 0.80, green: 0.86, blue: 1.0) : Color(red: 0.36, green: 0.42, blue: 0.62)
        return ZStack {
            Image(systemName: ref.symbol)
                .font(.system(size: 100))
                .foregroundStyle(tone.opacity(0.8))
                .frame(width: 100, height: 100)
                .scaleEffect(max(0.01, pixels / 92), anchor: .bottom)
                .offset(y: -50)
            Text("\(ref.name) \(formatLength(meters: ref.height).replacingOccurrences(of: "約", with: ""))")
                .font(Storybook.rounded(11, .semibold))
                .foregroundStyle(tone)
                .offset(y: 14)
        }
        .opacity(opacity)
    }

    // MARK: 上の帯

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                Text("今日 \(formatSteps(store.todaySteps))歩")
                    .monospacedDigit()
            }
            .font(Storybook.rounded(15))
            .foregroundStyle(Storybook.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .storyCard(corner: 20)

            // 一時的なテスト用（歩数を増やす）
            Menu {
                Button("+100歩") { store.addDebugSteps(100) }
                Button("+1,000歩") { store.addDebugSteps(1_000) }
                Button("+10,000歩") { store.addDebugSteps(10_000) }
                Button("+100,000歩") { store.addDebugSteps(100_000) }
                Button("+1,000,000歩") { store.addDebugSteps(1_000_000) }
            } label: {
                Text("テスト＋")
                    .font(Storybook.rounded(13))
                    .foregroundStyle(Storybook.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Storybook.warm.opacity(0.9)))
            }

            Spacer()

            Button {
                showMenu = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(StoryRoundButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: 下のカード

    private var infoCard: some View {
        let state = store.state
        let next = ScaleReference.next(after: ballDiameter)
        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(formatSteps(state.rollingSteps))歩")
                    .font(Storybook.rounded(34))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.6), value: state.rollingSteps)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("直径")
                        .font(Storybook.rounded(11, .semibold))
                        .foregroundStyle(Storybook.ink.opacity(0.6))
                    Text(formatLength(meters: ballDiameter))
                        .font(Storybook.rounded(22))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(Storybook.ink)

            if let next {
                let remain = max(0, BallScale.steps(forDiameter: next.height / extent) - state.rollingSteps)
                HStack(spacing: 6) {
                    Image(systemName: next.symbol)
                    Text("つぎは「\(next.name)」くらいの大きさ（あと \(formatSteps(remain))歩）")
                }
                .font(Storybook.rounded(13, .semibold))
                .foregroundStyle(Storybook.ink.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("「\(ScaleReference.all.last?.name ?? "やま")」よりも大きくなりました。まだまだ育ちます。")
                    .font(Storybook.rounded(13, .semibold))
                    .foregroundStyle(Storybook.ink.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .storyCard(corner: 30)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}
