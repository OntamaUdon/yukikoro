import SwiftUI
import MapKit

/// 地図（メイン画面）。南の斜め上空から北を向いて見下ろす。雪だるまの高さが見えるように、傾きは約 75°。
struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    /// ビルを立体にする（見づらければ false にすると、平面になる）
    private static let realisticBuildings = true
    private static let cameraDistance = 450.0
    private static let cameraPitch = 75.0

    @State private var position: MapCameraPosition = .automatic
    @State private var didCenter = false
    @State private var selectedTower: Tower?
    @State private var showCarry = false

    var body: some View {
        ZStack {
            map
            VStack(spacing: 12) {
                hud
                Spacer()
                actionCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .onAppear { centerIfNeeded() }
        .onChange(of: model.currentPoint) { _, _ in centerIfNeeded() }
        .sheet(item: $selectedTower) { tower in
            TowerSheet(towerID: tower.id)
        }
        .sheet(isPresented: $showCarry) {
            CarrySheet()
        }
        .task {
            #if DEBUG
            if DemoMode.sheet == "carry" { showCarry = true }
            if DemoMode.sheet == "tower" {
                try? await Task.sleep(for: .seconds(2))
                selectedTower = model.towers.first
            }
            #endif
        }
    }

    // MARK: 地図

    private func coordinate(_ point: GeoPoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }

    private func camera(at point: GeoPoint) -> MapCameraPosition {
        .camera(MapCamera(centerCoordinate: coordinate(point), distance: Self.cameraDistance, heading: 0, pitch: Self.cameraPitch))
    }

    private func centerIfNeeded() {
        guard !didCenter, let point = model.currentPoint else { return }
        didCenter = true
        position = camera(at: point)
    }

    private var map: some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
            if let test = model.location.testPoint {
                Annotation("あなた", coordinate: coordinate(test), anchor: .bottom) {
                    meMarker
                }
            } else {
                UserAnnotation()
            }
            ForEach(model.towers) { tower in
                Annotation("", coordinate: coordinate(tower.location), anchor: .bottom) {
                    TowerMarker(tower: tower, inRange: isInRange(tower), config: model.config)
                        .onTapGesture { selectedTower = tower }
                }
            }
        }
        .mapStyle(.standard(elevation: Self.realisticBuildings ? .realistic : .flat,
                            emphasis: .muted,
                            pointsOfInterest: .excludingAll))
        .ignoresSafeArea()
    }

    private func isInRange(_ tower: Tower) -> Bool {
        guard let distance = model.distance(to: tower) else { return false }
        return distance <= model.config.stackRadius
    }

    private var meMarker: some View {
        VStack(spacing: 0) {
            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Soft.accent)
                .background(Circle().fill(Soft.background))
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(Soft.accent)
        }
    }

    // MARK: 上: 歩数と、持っている雪玉

    private var hud: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatSteps(model.todaySteps))
                        .font(Soft.font(40))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.6), value: model.todaySteps)
                    Text("歩").font(Soft.font(16, .semibold))
                }
                .foregroundStyle(Soft.ink)
                Text("今日の歩数")
                    .font(Soft.font(12, .medium))
                    .foregroundStyle(Soft.subInk)
            }
            Spacer(minLength: 8)
            Button {
                showCarry = true
            } label: {
                HStack(spacing: 10) {
                    SnowBallDisc(size: CGFloat(18 + min(26, 22 * pow(model.carriedDiameter, 0.5))))
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(formatLength(meters: model.carriedDiameter))
                            .font(Soft.font(20))
                            .monospacedDigit()
                        Text("持っている雪玉")
                            .font(Soft.font(11, .medium))
                            .foregroundStyle(Soft.subInk)
                    }
                    .foregroundStyle(Soft.ink)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("持っている雪玉を見る")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .softCard(radius: 28)
    }

    // MARK: 下: おく・積む

    @ViewBuilder
    private var actionCard: some View {
        VStack(spacing: 10) {
            if model.location.isDenied {
                Text("位置情報が許可されていません。設定で「ゆきころ」の位置情報を、「このAppの使用中」にしてください。")
                    .font(Soft.font(13, .medium))
                    .foregroundStyle(Soft.ink)
                    .multilineTextAlignment(.center)
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(SoftButtonStyle())
            } else if let error = model.loadError {
                Label(error, systemImage: "icloud.slash")
                    .font(Soft.font(13, .medium))
                    .foregroundStyle(Soft.ink)
                    .multilineTextAlignment(.center)
            } else if let tower = model.nearbyTower {
                nearbyCard(tower)
            } else {
                placeCard
            }
        }
        .padding(16)
        .softCard(radius: 28)
    }

    private func nearbyCard(_ tower: Tower) -> some View {
        let issue = model.stackIssue(for: tower)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                SoftChip(symbol: "arrow.up.to.line", text: formatLength(meters: tower.height))
                SoftChip(symbol: "circle.grid.2x1.fill", text: "\(tower.balls.count)こ")
                if let distance = model.distance(to: tower) {
                    SoftChip(symbol: "location.fill", text: formatDistance(meters: distance))
                }
                Spacer()
                Button {
                    selectedTower = tower
                } label: {
                    Image(systemName: "info")
                }
                .buttonStyle(SoftIconButtonStyle(size: 38))
                .accessibilityLabel("くわしく見る")
            }
            if let issue {
                Text(issue.message(config: model.config))
                    .font(Soft.font(13, .medium))
                    .foregroundStyle(Soft.subInk)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await model.stack(on: tower) }
            } label: {
                Label("近くの雪だるまにのせる", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(SoftButtonStyle(prominent: true))
            .disabled(issue != nil || model.isBusy)
        }
    }

    private var placeCard: some View {
        let issue = model.placeIssue
        return VStack(spacing: 10) {
            if let issue {
                Text(issue.message(config: model.config, carriedSteps: model.player.carriedSteps))
                    .font(Soft.font(13, .medium))
                    .foregroundStyle(Soft.subInk)
                    .multilineTextAlignment(.center)
            } else {
                Text("近くに雪だるまがありません。ここに、土台をおけます")
                    .font(Soft.font(13, .medium))
                    .foregroundStyle(Soft.subInk)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await model.place() }
            } label: {
                Label("ここに土台をおく", systemImage: "circle.fill")
            }
            .buttonStyle(SoftButtonStyle(prominent: true))
            .disabled(issue != nil || model.isBusy)
        }
    }
}
