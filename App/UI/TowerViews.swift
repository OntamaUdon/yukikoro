import SwiftUI
import SceneKit
import UIKit

// MARK: 地図の印

/// 地図に立つ、塔の印。高さが見えるように、雪玉を積み重ねた形で、縦に長く描く（高さは誇張した見た目）。
struct TowerMarker: View {
    let tower: Tower
    var inRange = false
    var config: TowerConfig = .standard

    /// 雪玉 1 つの、画面での大きさ（直径 m から）
    static func discSize(_ diameter: Double) -> CGFloat {
        CGFloat(10 + 26 * pow(max(diameter, 0.01), 0.6))
    }

    var body: some View {
        let sizes = tower.balls.map { Self.discSize($0.diameter) }
        let overlap: CGFloat = 0.80
        let base = sizes.first ?? 20
        let stackHeight = sizes.dropLast().reduce(0) { $0 + $1 * overlap } + (sizes.last ?? 0)
        let closed = tower.isClosed(config: config)
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(Soft.shade)
                    .frame(width: base * 0.95, height: base * 0.26)
                    .blur(radius: 2)
                    .offset(y: base * 0.06)
                if inRange {
                    Ellipse()
                        .stroke(Soft.accent.opacity(0.85), lineWidth: 3)
                        .frame(width: base * 1.45, height: base * 0.5)
                        .offset(y: base * 0.14)
                }
                ForEach(0..<tower.balls.count, id: \.self) { index in
                    let lower = sizes.prefix(index).reduce(0) { $0 + $1 * overlap }
                    SnowBallDisc(size: sizes[index], face: index == tower.balls.count - 1)
                        .offset(y: -lower)
                        .accessibilityHidden(true)
                }
                if closed {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Soft.gold)
                        .offset(x: base * 0.5, y: -stackHeight)
                }
            }
            .frame(width: max(base, 24) * 1.5, height: stackHeight + 6, alignment: .bottom)
            Text(formatLength(meters: tower.height))
                .font(Soft.font(11))
                .foregroundStyle(Soft.ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Soft.background.opacity(0.92)))
        }
    }
}

// MARK: 3D の塔

enum TowerScene {
    private static func speckle(size: Int = 128) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let cg = context.cgContext
            UIColor(white: 0.98, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            var generator = SplitMix64(seed: 11)
            for _ in 0..<160 {
                let x = CGFloat(generator.next() % 1_000) / 1_000 * CGFloat(size)
                let y = CGFloat(generator.next() % 1_000) / 1_000 * CGFloat(size)
                let r = 1.2 + CGFloat(generator.next() % 100) / 100 * 5
                let alpha = 0.10 + CGFloat(generator.next() % 100) / 100 * 0.16
                UIColor(red: 0.78, green: 0.88, blue: 1.0, alpha: alpha).setFill()
                for dx in [-CGFloat(size), 0, CGFloat(size)] {
                    for dy in [-CGFloat(size), 0, CGFloat(size)] {
                        cg.fillEllipse(in: CGRect(x: x + dx - r, y: y + dy - r, width: r * 2, height: r * 2))
                    }
                }
            }
        }
    }

    static func make(diameters: [Double]) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        let texture = speckle()
        let snow = SCNMaterial()
        snow.lightingModel = .lambert
        snow.diffuse.contents = texture
        snow.diffuse.wrapS = .repeat
        snow.diffuse.wrapT = .repeat

        func paint(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .lambert
            m.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
            return m
        }
        let dark = paint(0.14, 0.17, 0.27)
        let carrot = paint(1.0, 0.58, 0.20)
        let scarf = paint(0.88, 0.30, 0.34)

        var y = 0.0
        var tops: [(center: Double, radius: Double)] = []
        for d in diameters {
            let sphere = SCNSphere(radius: d / 2)
            sphere.segmentCount = 48
            sphere.materials = [snow]
            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(0, Float(y + d / 2), 0)
            scene.rootNode.addChildNode(node)
            tops.append((y + d / 2, d / 2))
            y += d * 0.94
        }
        let height = max(0.2, y + (diameters.last ?? 0) * 0.06)

        // 一番上の雪玉に、顔
        if let last = tops.last {
            let r = last.radius
            let c = last.center
            for sign in [-1.0, 1.0] {
                let eye = SCNNode(geometry: SCNSphere(radius: r * 0.09))
                eye.geometry?.materials = [dark]
                eye.position = SCNVector3(Float(sign * r * 0.3), Float(c + r * 0.2), Float(r * 0.92))
                scene.rootNode.addChildNode(eye)
            }
            let nose = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: r * 0.11, height: r * 0.5))
            nose.geometry?.materials = [carrot]
            nose.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            nose.position = SCNVector3(0, Float(c), Float(r * 1.12))
            scene.rootNode.addChildNode(nose)
            for k in -2...2 {
                let dot = SCNNode(geometry: SCNSphere(radius: r * 0.04))
                dot.geometry?.materials = [dark]
                let t = Double(k) / 2
                let smile = c - r * 0.28 + abs(t) * r * 0.06
                dot.position = SCNVector3(Float(t * r * 0.3), Float(smile), Float(r * 0.93))
                scene.rootNode.addChildNode(dot)
            }
            // 首に、マフラー（2 つ以上積まれているとき）
            if tops.count >= 2 {
                let neckY = c - r * 0.92
                let ring = SCNNode(geometry: SCNTorus(ringRadius: r * 0.62, pipeRadius: r * 0.12))
                ring.geometry?.materials = [scarf]
                ring.position = SCNVector3(0, Float(neckY + r * 0.1), 0)
                scene.rootNode.addChildNode(ring)
            }
        }

        // 地面
        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.materials = [paint(0.90, 0.94, 0.99)]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        // 光
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(red: 0.78, green: 0.84, blue: 0.96, alpha: 1)
        ambient.light?.intensity = 850
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 900
        sun.eulerAngles = SCNVector3(-0.8, 0.6, 0)
        scene.rootNode.addChildNode(sun)

        // カメラ
        let camera = SCNCamera()
        camera.fieldOfView = 40
        camera.zNear = 0.01
        camera.zFar = 1_000
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let distance = max(height * 1.7, 1.2)
        cameraNode.position = SCNVector3(0, Float(height * 0.5), Float(distance))
        let target = SCNNode()
        target.position = SCNVector3(0, Float(height * 0.48), 0)
        scene.rootNode.addChildNode(target)
        cameraNode.constraints = [SCNLookAtConstraint(target: target)]
        scene.rootNode.addChildNode(cameraNode)
        return scene
    }
}

struct TowerSceneView: UIViewRepresentable {
    let diameters: [Double]

    final class Coordinator {
        var last: [Double] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = TowerScene.make(diameters: diameters)
        context.coordinator.last = diameters
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if context.coordinator.last != diameters {
            context.coordinator.last = diameters
            view.scene = TowerScene.make(diameters: diameters)
        }
    }
}

// MARK: 塔の画面

struct TowerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let towerID: String
    @State private var showReport = false

    private var tower: Tower? { model.towers.first { $0.id == towerID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let tower {
                    content(tower)
                } else {
                    Text("この塔は、もう見えません")
                        .font(Soft.font(16, .medium))
                        .foregroundStyle(Soft.subInk)
                        .padding(40)
                }
            }
            .softScreen()
            .navigationTitle("雪だるま")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let tower {
                        Menu {
                            Button("通報する", role: .destructive) { showReport = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("そのほか")
                        .confirmationDialog("どんな理由ですか？", isPresented: $showReport, titleVisibility: .visible) {
                            Button("人がたくさん集まって、迷惑") { Task { await model.report(tower, reason: 1) } }
                            Button("危ない場所・入ってはいけない場所") { Task { await model.report(tower, reason: 2) } }
                            Button("そのほか") { Task { await model.report(tower, reason: 3) } }
                            Button("やめる", role: .cancel) {}
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }.font(Soft.font(16))
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func content(_ tower: Tower) -> some View {
        let issue = model.stackIssue(for: tower)
        let closed = tower.isClosed(config: model.config)
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatLength(meters: tower.height))
                    .font(Soft.font(46))
                    .monospacedDigit()
                Text("の高さ").font(Soft.font(16, .semibold)).foregroundStyle(Soft.subInk)
                Spacer()
            }
            HStack(spacing: 10) {
                SoftChip(symbol: "circle.grid.2x1.fill", text: "\(tower.balls.count)こ")
                SoftChip(symbol: "mappin.and.ellipse", text: Prefecture.name(code: tower.prefecture))
                if closed {
                    SoftChip(symbol: "sparkles", text: "完成", tint: Soft.good)
                } else if let max = tower.maxNextDiameter(config: model.config) {
                    SoftChip(symbol: "arrow.up.to.line", text: "\(formatLength(meters: max))まで")
                }
                Spacer()
            }
            TowerSceneView(diameters: tower.balls.map(\.diameter))
                .frame(height: 300)
                .softWell(radius: 26)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "figure.walk")
                    Text("いま持っている雪玉")
                    Spacer()
                    Text(formatLength(meters: model.carriedDiameter)).monospacedDigit()
                }
                .font(Soft.font(15, .semibold))
                .foregroundStyle(Soft.ink)
                if let distance = model.distance(to: tower) {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("この塔まで")
                        Spacer()
                        Text(formatDistance(meters: distance)).monospacedDigit()
                    }
                    .font(Soft.font(15, .semibold))
                    .foregroundStyle(Soft.ink)
                }
            }
            .padding(16)
            .softCard(radius: 22, depth: 0.7)

            if let issue {
                Text(issue.message(config: model.config))
                    .font(Soft.font(14, .medium))
                    .foregroundStyle(Soft.subInk)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task {
                    if await model.stack(on: tower) { dismiss() }
                }
            } label: {
                Label("この塔にのせる", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(SoftButtonStyle(prominent: true))
            .disabled(issue != nil || model.isBusy)

            if AppEnvironment.isBeta {
                Button {
                    model.betaMove(to: tower)
                } label: {
                    Label("（テスト）この塔の位置へ移動", systemImage: "scope")
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
        .padding(20)
    }
}
