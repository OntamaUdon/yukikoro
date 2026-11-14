import SwiftUI

/// 雪玉の大きさの変化を、ゆっくり見せるためのアニメーション（半径と重さを、対数で補間する）
struct RadiusAnimation {
    var fromRadius: Double
    var toRadius: Double
    var fromMass: Double
    var toMass: Double
    var start: Date
    var duration: TimeInterval
    /// 変化の間に雪玉が転がる回数
    var turns: Double
    /// このアニメーションが始まる前までに、転がっていた角度
    var baseAngle: Double

    static func still(radius: Double, mass: Double) -> RadiusAnimation {
        RadiusAnimation(fromRadius: radius, toRadius: radius, fromMass: mass, toMass: mass,
                        start: Date(), duration: 0, turns: 0, baseAngle: 0)
    }

    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        let t = min(1, max(0, now.timeIntervalSince(start) / duration))
        return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    func radius(at now: Date) -> Double { radius(progress: progress(at: now)) }
    func mass(at now: Date) -> Double { mass(progress: progress(at: now)) }

    func radius(progress p: Double) -> Double {
        exp(log(fromRadius) + (log(toRadius) - log(fromRadius)) * p)
    }

    func mass(progress p: Double) -> Double {
        exp(log(fromMass) + (log(toMass) - log(fromMass)) * p)
    }

    func extraAngle(at now: Date) -> Double {
        baseAngle + turns * 2 * Double.pi * progress(at: now)
    }
}

private struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// ゆきころさんぽのメイン画面。歩くと仲間が雪玉を転がして、雪玉が育つ。
/// 雪玉の見かけの大きさはいつも同じで、大きくなるほど、まわりの木や仲間が小さく遠くなる。
struct MainView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showMenu = false
    @State private var showShop = false
    @State private var squishTick = 0
    @State private var anim = RadiusAnimation.still(radius: SnowPhysics.initialRadius, mass: SnowPhysics.initialMass())
    @State private var appearedAt = Date()
    @State private var cardHeight: CGFloat = 150

    private var daypart: Daypart { Daypart.current(hour: Int(SkyClock.hour())) }

    var body: some View {
        TimelineView(.animation) { timeline in
            content(now: timeline.date)
        }
        .onAppear { prepare() }
        .onChange(of: store.state.mass) { _, _ in retarget() }
        .onChange(of: store.state.pack) { _, _ in retarget() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { prepare() }
        }
        .sheet(isPresented: $showMenu) { MenuSheet() }
        .sheet(isPresented: $showShop) { ShopSheet() }
    }

    // MARK: 変化の見せ方

    /// 開いたとき: 前に見た雪玉から始めて、1秒後に、いまの雪玉へ3秒かけて変わる。
    private func prepare() {
        appearedAt = Date()
        let state = store.state
        let seenMass = state.seenMass ?? state.mass
        anim = .still(radius: state.seenRadius, mass: seenMass)
        retarget()
    }

    private func retarget() {
        let state = store.state
        let now = Date()
        let currentRadius = anim.radius(at: now)
        let currentMass = anim.mass(at: now)
        let radiusChange = abs(log(state.radius / max(currentRadius, 1e-12)))
        let massChange = abs(log(state.mass / max(currentMass, 1e-12)))
        guard radiusChange > 1e-5 || massChange > 1e-5 else { return }

        let intro = now.timeIntervalSince(appearedAt) < 6
        let start = intro ? max(now, appearedAt.addingTimeInterval(1)) : now
        let big = max(radiusChange, massChange)
        let duration = intro ? 3.0 : min(3.0, 0.25 + 1.5 * big)
        let turns = big < 0.01 ? 0 : min(6, 0.5 + 1.2 * big)
        anim = RadiusAnimation(
            fromRadius: currentRadius, toRadius: state.radius,
            fromMass: currentMass, toMass: state.mass,
            start: start, duration: reduceMotion ? 0.01 : duration,
            turns: reduceMotion ? 0 : turns,
            baseAngle: anim.extraAngle(at: now)
        )
        store.markSeen()
    }

    // MARK: 画面

    private func crewLook(_ state: GameState) -> CrewLook {
        var tier = 0
        var count = 1
        for (index, id) in ["kid", "big", "plank", "crawler", "heavy"].enumerated() {
            let n = state.ownedCount(id)
            if n > 0 {
                tier = index
                count = n
            }
        }
        return CrewLook(tier: tier, count: min(count, 8), gravity: state.ownedCount("gravity"))
    }

    private func content(now: Date) -> some View {
        let state = store.state
        let p = anim.progress(at: now)
        let radius = anim.radius(progress: p)
        let mass = anim.mass(progress: p)
        let idle = reduceMotion ? 0 : now.timeIntervalSince(appearedAt) * 0.35
        let input = StageInput(
            radius: radius,
            angle: idle + anim.extraAngle(at: now),
            daypart: daypart,
            crew: crewLook(state),
            blackHole: state.blackHole,
            squishTick: squishTick
        )
        return GeometryReader { outer in
            // 3D の舞台は、下のカードにかぶらない高さに収める
            let inset = cardHeight + 6 + outer.safeAreaInsets.bottom
            ZStack {
                StoryPanorama(daypart: daypart, bottomInset: inset)
                    .ignoresSafeArea()
                GeometryReader { full in
                    SnowStage(input: input)
                        .frame(width: full.size.width, height: max(1, full.size.height - inset))
                }
                .ignoresSafeArea()
                SnowFall(isDark: daypart.isDark)

                VStack(spacing: 0) {
                    header(state)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.packSnow()
                            squishTick += 1
                        }
                    infoCard(state: state, radius: radius, mass: mass)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: CardHeightKey.self, value: geo.size.height)
                            }
                        )
                }
                .onPreferenceChange(CardHeightKey.self) { cardHeight = $0 }

                if state.blackHole && p >= 1 {
                    endingView
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: 上の帯

    private func header(_ state: GameState) -> some View {
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
                showShop = true
            } label: {
                Image(systemName: "cart.fill")
                    .overlay(alignment: .topTrailing) {
                        if Shop.items.contains(where: { state.canBuy($0) }) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 11, height: 11)
                                .offset(x: 6, y: -6)
                        }
                    }
            }
            .buttonStyle(StoryRoundButtonStyle())

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

    private func infoCard(state: GameState, radius: Double, mass: Double) -> some View {
        let diameter = 2 * radius
        let easiness = SnowPhysics.easiness(mass: state.mass, team: state.team)
        return VStack(spacing: 8) {
            HStack(alignment: .top) {
                stat("つかえる歩数", "\(formatSteps(state.points))歩", big: true)
                Spacer(minLength: 8)
                stat("資材", formatSteps(state.materials), align: .center)
                Spacer(minLength: 8)
                stat("直径", formatLength(meters: diameter), align: .trailing)
            }
            .foregroundStyle(Storybook.ink)

            HStack(spacing: 10) {
                Label(formatMass(kg: mass), systemImage: "scalemass.fill")
                Label(String(format: "%.0f kg/m³", state.density), systemImage: "square.stack.3d.down.right.fill")
                Spacer(minLength: 0)
                Text(easinessText(easiness))
            }
            .font(Storybook.rounded(12, .semibold))
            .foregroundStyle(Storybook.ink.opacity(0.75))
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            laneLine(state: state, diameter: diameter)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .storyCard(corner: 28)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func stat(_ title: String, _ value: String, big: Bool = false, align: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: align, spacing: 0) {
            Text(title)
                .font(Storybook.rounded(11, .semibold))
                .foregroundStyle(Storybook.ink.opacity(0.6))
            Text(value)
                .font(Storybook.rounded(big ? 26 : 20))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// 木の道の状況（ぶつかって止まっているとき・道の幅・次の目印）
    @ViewBuilder
    private func laneLine(state: GameState, diameter: Double) -> some View {
        if state.isBlockedByTrees, let needed = state.toppleForceNeeded {
            let now = state.team.force + state.team.lift * state.mass * SnowPhysics.gravity
            HStack(spacing: 6) {
                Image(systemName: "tree.fill")
                Text("木にぶつかった！ 倒すには \(formatForce(needed)) の力が要ります（いま \(formatForce(now))）")
                    .lineLimit(2)
            }
            .font(Storybook.rounded(12, .bold))
            .foregroundStyle(Color(red: 0.78, green: 0.30, blue: 0.22))
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if state.laneCapMass.isFinite {
            HStack(spacing: 6) {
                Image(systemName: "tree.fill")
                Text("木の道の幅は \(formatLength(meters: state.laneWidth).replacingOccurrences(of: "約", with: ""))。これより大きくなると木にぶつかります")
                    .lineLimit(2)
            }
            .font(Storybook.rounded(12, .semibold))
            .foregroundStyle(Storybook.ink.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let next = ScaleReference.next(after: diameter) {
            HStack(spacing: 6) {
                Image(systemName: next.symbol)
                Text("つぎは「\(next.name)」くらいの大きさ（\(formatLength(meters: next.height))）")
            }
            .font(Storybook.rounded(12, .semibold))
            .foregroundStyle(Storybook.ink.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func easinessText(_ value: Double) -> String {
        if value >= 0.995 { return "すいすい" }
        if value >= 0.01 { return "\(Int((value * 100).rounded()))%" }
        if value >= 1e-6 { return "ほぼ動かない" }
        return "止まって見える"
    }

    // MARK: ブラックホール

    private var endingView: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "circle.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.2))
                Text("ブラックホールになった")
                    .font(Storybook.rounded(26))
                    .foregroundStyle(.white)
                Text("雪玉は、自分の重さでぎゅっとつぶれて、\nシュワルツシルト半径より小さくなりました。\nここまで育てて、ありがとう。")
                    .font(Storybook.rounded(15, .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                Text("歩いた歩数 \(formatSteps(store.state.totalSteps))歩")
                    .font(Storybook.rounded(14, .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Button("新しい雪玉ではじめる") {
                    store.startOver()
                }
                .buttonStyle(StoryButtonStyle(kind: .primary))
            }
            .padding(24)
        }
    }
}
