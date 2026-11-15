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

private struct TopBlockHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct BottomPanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// ゆきころさんぽのメイン画面。歩くと仲間が雪玉を転がして、雪玉が育つ。
/// 主役は、今日の歩数。雪玉の見かけの大きさはいつも同じで、大きくなるほど、まわりの木や仲間が小さく遠くなる。
struct MainView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showMenu = false
    /// ブラックホールになる演出を始めた時刻（6 秒かける）
    @State private var bhStart: Date?
    @State private var squishTick = 0
    @State private var anim = RadiusAnimation.still(radius: SnowPhysics.initialRadius, mass: SnowPhysics.initialMass())
    @State private var appearedAt = Date()
    @State private var topHeight: CGFloat = 80
    /// 拾った資材（ふえた分を、ちょっとのあいだ見せる）
    @State private var pickupGain: Int?
    @State private var pickupToken = 0

    private var daypart: Daypart { Daypart.current(hour: Int(SkyClock.hour())) }
    private let gold = Color(red: 0.98, green: 0.72, blue: 0.20)

    var body: some View {
        GeometryReader { outer in
            let safeTop = outer.safeAreaInsets.top
            let safeBottom = outer.safeAreaInsets.bottom
            let fullH = outer.size.height + safeTop + safeBottom
            let half = fullH * 0.5
            let hudTop = safeTop + topHeight
            ZStack {
                VStack(spacing: 0) {
                    // 上半分: 3D の舞台と、今日の歩数
                    ZStack(alignment: .top) {
                        // 動く絵だけを、毎フレーム描き直す（メニューなどの部品は描き直さない）
                        TimelineView(.animation) { timeline in
                            scene(now: timeline.date, top: hudTop, height: half)
                        }
                        VStack(spacing: 0) {
                            topHud
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(key: TopBlockHeightKey.self, value: geo.size.height)
                                    }
                                )
                                .padding(.top, safeTop)
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    store.packSnow()
                                    squishTick += 1
                                }
                        }
                    }
                    .frame(height: half)
                    .clipped()

                    // 下半分: 雪玉の大きさ・重さ・資材と、おみせ
                    bottomHalf(safeBottom: safeBottom)
                        .frame(maxHeight: .infinity)
                }

                // ブラックホールになる演出（まぶしい光）と、そのあとの案内
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: bhStart == nil && !store.state.blackHole)) { timeline in
                    blackHoleLayer(now: timeline.date)
                }
            }
            .frame(width: outer.size.width, height: fullH)
            .ignoresSafeArea()
            .onPreferenceChange(TopBlockHeightKey.self) { topHeight = $0 }
        }
        .onAppear {
            prepare()
            #if DEBUG
            if DemoMode.sheet == "menu" { showMenu = true }
            #endif
        }
        .onChange(of: store.state.materials) { old, new in
            guard new > old, !store.state.blackHole else { return }
            pickupToken += 1
            let token = pickupToken
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pickupGain = new - old }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if token == pickupToken { withAnimation(.easeOut(duration: 0.3)) { pickupGain = nil } }
            }
        }
        .onChange(of: store.state.mass) { _, _ in retarget() }
        .onChange(of: store.state.pack) { _, _ in retarget() }
        .onChange(of: store.state.blackHole) { _, isHole in
            if isHole { startCollapseIfNeeded() } else { bhStart = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { prepare() }
        }
        .sheet(isPresented: $showMenu) { MenuSheet() }
    }

    /// ブラックホールになる演出を、まだ見ていなければ、いまの変化のあとで始める
    private func startCollapseIfNeeded() {
        let state = store.state
        guard state.blackHole, !state.seenBlackHole, bhStart == nil else { return }
        bhStart = max(Date().addingTimeInterval(0.6), anim.start.addingTimeInterval(anim.duration))
    }

    /// ブラックホールになる動きの進み（0〜1）。演出がないときは、ブラックホールなら 1。
    private func collapseProgress(now: Date) -> Double {
        let state = store.state
        guard state.blackHole else { return 0 }
        guard let start = bhStart else { return state.seenBlackHole ? 1 : 0 }
        return min(1, max(0, now.timeIntervalSince(start) / 6))
    }

    // MARK: 変化の見せ方

    /// 開いたとき: 前に見た雪玉から始めて、1秒後に、いまの雪玉へ3秒かけて変わる。
    private func prepare() {
        appearedAt = Date()
        let state = store.state
        let seenMass = state.seenMass ?? state.mass
        anim = .still(radius: state.seenRadius, mass: seenMass)
        retarget()
        startCollapseIfNeeded()
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

    // MARK: 動く絵（空・3Dの舞台・雪）

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

    private func scene(now: Date, top: CGFloat, height: CGFloat) -> some View {
        let state = store.state
        let p = anim.progress(at: now)
        let radius = anim.radius(progress: p)
        let idle = reduceMotion ? 0 : now.timeIntervalSince(appearedAt) * 0.35
        let input = StageInput(
            radius: radius,
            angle: idle + anim.extraAngle(at: now),
            daypart: daypart,
            crew: crewLook(state),
            blackHole: state.blackHole,
            collapse: collapseProgress(now: now),
            squishTick: squishTick
        )
        return ZStack {
            StoryPanorama(daypart: daypart, topInset: top, bottomInset: 0)
            GeometryReader { full in
                SnowStage(input: input)
                    .frame(width: full.size.width, height: max(1, full.size.height - top))
                    .padding(.top, top)
            }
            SnowFall(isDark: daypart.isDark)
        }
        .frame(height: height)
    }

    // MARK: 上: 今日の歩数

    private var topHud: some View {
        let state = store.state
        let steps = store.todaySteps
        let fraction = DailyGoal.fraction(steps: steps)
        let reached = fraction >= 1
        let tint = reached ? gold : Storybook.accent
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(1, fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: fraction)
                Image(systemName: reached ? "star.fill" : "figure.walk")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formatSteps(steps))
                        .font(Storybook.rounded(40))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.6), value: steps)
                    Text("歩")
                        .font(Storybook.rounded(16))
                }
                .foregroundStyle(Storybook.ink)
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "shoeprints.fill")
                        Text("\(formatSteps(state.totalSteps))歩")
                            .monospacedDigit()
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.circle.fill")
                            .foregroundStyle(gold)
                        Text("つかえる \(formatSteps(state.points))")
                            .monospacedDigit()
                    }
                }
                .font(Storybook.rounded(12))
                .foregroundStyle(Storybook.ink.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    // 一時的なテスト用（歩数を増やす）
                    Menu {
                        Button("+100歩") { store.addDebugSteps(100) }
                        Button("+1,000歩") { store.addDebugSteps(1_000) }
                        Button("+10,000歩") { store.addDebugSteps(10_000) }
                        Button("+100,000歩") { store.addDebugSteps(100_000) }
                        Button("+1,000,000歩") { store.addDebugSteps(1_000_000) }
                    } label: {
                        Text("テスト＋")
                            .font(Storybook.rounded(11))
                            .foregroundStyle(Storybook.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Storybook.warm.opacity(0.9)))
                    }
                    Button {
                        showMenu = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(StoryRoundButtonStyle(size: 32))
                }
                growthChip(state)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .storyCard(corner: 26)
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    /// 今日ふえた分
    @ViewBuilder
    private func growthChip(_ state: GameState) -> some View {
        let growth = state.todayGrowth
        if growth >= 0.005 {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.forward.circle.fill")
                Text("+" + formatLength(meters: growth).replacingOccurrences(of: "約", with: ""))
                    .monospacedDigit()
            }
            .font(Storybook.rounded(14))
            .foregroundStyle(Color(red: 0.22, green: 0.58, blue: 0.40))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(red: 0.22, green: 0.58, blue: 0.40).opacity(0.14)))
        }
    }

    /// 過去 7 日の歩数（右が今日。目標に届いた日は金色）
    private func weekBars(_ state: GameState) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days: [(steps: Int, isToday: Bool)] = (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let steps = offset == 0 ? store.todaySteps : state.walkedSteps(on: DayKey.key(for: date))
            return (steps, offset == 0)
        }
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                let fraction = min(1, DailyGoal.fraction(steps: day.steps))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(day.steps >= DailyGoal.steps ? gold : Storybook.accent.opacity(day.isToday ? 1 : 0.5))
                    .frame(width: 9, height: 5 + 25 * fraction)
            }
        }
        .frame(height: 30, alignment: .bottom)
    }

    // MARK: 下: 雪玉の大きさと、おみせ

    private func bottomHalf(safeBottom: CGFloat) -> some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
                statsCard(now: timeline.date)
            }
            .padding(.horizontal, 12)
            ShopPanel()
        }
        .padding(.top, 12)
        .padding(.bottom, safeBottom)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.86, green: 0.93, blue: 1.0), Storybook.paper], startPoint: .top, endPoint: .bottom))
                .shadow(color: Storybook.shadow, radius: 8, y: -2)
        )
    }

    private func statsCard(now: Date) -> some View {
        let state = store.state
        let p = anim.progress(at: now)
        let radius = anim.radius(progress: p)
        let mass = anim.mass(progress: p)
        let diameter = 2 * radius
        let lengthRef = ScaleReference.nearest(to: diameter)
        let massRef = MassReference.nearest(to: mass)
        return VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                bigStat(symbol: "arrow.left.and.right.circle.fill", value: formatLength(meters: diameter),
                        refSymbol: lengthRef?.reference.symbol, refName: lengthRef?.reference.name, times: lengthRef?.times)
                Divider().frame(height: 52)
                bigStat(symbol: "scalemass.fill", value: formatMass(kg: mass),
                        refSymbol: massRef?.reference.symbol, refName: massRef?.reference.name, times: massRef?.times)
                Divider().frame(height: 52)
                VStack(spacing: 2) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(red: 0.70, green: 0.48, blue: 0.28))
                    Text(formatSteps(state.materials))
                        .font(Storybook.rounded(20))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(Storybook.ink)
                }
                .frame(width: 62)
                .overlay(alignment: .top) {
                    if let gain = pickupGain {
                        Text("+\(formatSteps(gain))")
                            .font(Storybook.rounded(17))
                            .foregroundStyle(Color(red: 0.70, green: 0.48, blue: 0.28))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.95)))
                            .offset(y: -26)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            laneBar(state: state, diameter: diameter)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .storyCard(corner: 26)
    }

    /// 大きな数字と、「何と同じくらいか」の目印
    private func bigStat(symbol: String, value: String, refSymbol: String?, refName: String?, times: Double?) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Storybook.accent)
                Text(value.replacingOccurrences(of: "約", with: ""))
                    .font(Storybook.rounded(24))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .foregroundStyle(Storybook.ink)
            }
            if let refSymbol, let refName, let times {
                HStack(spacing: 4) {
                    Image(systemName: refSymbol)
                    Text(refName)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(formatTimes(times))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .font(Storybook.rounded(12))
                .foregroundStyle(Storybook.ink.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func laneSymbol(_ kind: LaneKind) -> String {
        switch kind {
        case .tree: return "tree.fill"
        case .pole: return "lightbulb.fill"
        case .helicopter: return "airplane"
        case .house: return "house.fill"
        case .building: return "building.2.fill"
        case .mountain, .range: return "mountain.2.fill"
        }
    }

    /// 雪玉が木の道の幅にどれだけ近づいたか。ぶつかって止まっているときは赤で、必要な力を出す。
    @ViewBuilder
    private func laneBar(state: GameState, diameter: Double) -> some View {
        if state.laneCapMass.isFinite {
            let blocked = state.isBlockedByTrees
            let fraction = min(1, diameter / state.laneWidth)
            let tint = blocked ? Color(red: 0.88, green: 0.32, blue: 0.26) : Storybook.accent
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Storybook.ink.opacity(0.5))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Storybook.ink.opacity(0.10))
                            Capsule().fill(tint).frame(width: max(8, geo.size.width * fraction))
                        }
                    }
                    .frame(height: 12)
                    Image(systemName: laneSymbol(Lane.kind(stage: state.stage)))
                        .font(.system(size: 17))
                        .foregroundStyle(Color(red: 0.28, green: 0.52, blue: 0.38))
                }
                if blocked, let needed = state.toppleForceNeeded {
                    let now = state.team.force + state.team.lift * state.mass * SnowPhysics.gravity
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                        Text("\(formatForce(now)) / \(formatForce(needed))")
                            .monospacedDigit()
                    }
                    .font(Storybook.rounded(12))
                    .foregroundStyle(tint)
                }
            }
        } else if let next = ScaleReference.next(after: diameter) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                Image(systemName: next.symbol)
                Text(next.name)
            }
            .font(Storybook.rounded(13))
            .foregroundStyle(Storybook.ink.opacity(0.7))
        }
    }

    // MARK: ブラックホール

    /// なる瞬間のまぶしい光と、なったあとの案内（つづける）、宇宙をのみこんだ最後の画面
    @ViewBuilder
    private func blackHoleLayer(now: Date) -> some View {
        let state = store.state
        let k = collapseProgress(now: now)
        if state.blackHole {
            let flash = max(0, 1 - abs(k - 0.38) / 0.1)
            ZStack {
                Color.white.opacity(flash * 0.95).ignoresSafeArea().allowsHitTesting(false)
                if state.finished {
                    endingCard(
                        title: "宇宙をのみこんだ",
                        message: "雪玉だったブラックホールは、\nとうとう、宇宙ぜんぶをのみこみました。\nここまで育てて、ありがとう。",
                        button: "新しい雪玉ではじめる"
                    ) { store.startOver(); bhStart = nil }
                } else if !state.seenBlackHole && k >= 1 {
                    endingCard(
                        title: "ブラックホールになった",
                        message: "雪玉は自分の重さでぎゅっとつぶれました。\nここからは、歩くたびに、まわりの星を\nすいこんで育ちます。",
                        button: "つづける"
                    ) { store.acknowledgeBlackHole() }
                }
            }
        }
    }

    private func endingCard(title: String, message: String, button: String, action: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "circle.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.2))
                Text(title)
                    .font(Storybook.rounded(26))
                    .foregroundStyle(.white)
                Text(message)
                    .font(Storybook.rounded(15, .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                Text("歩いた歩数 \(formatSteps(store.state.totalSteps))歩")
                    .font(Storybook.rounded(14, .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Button(button, action: action)
                    .buttonStyle(StoryButtonStyle(kind: .primary))
            }
            .padding(24)
        }
    }
}
