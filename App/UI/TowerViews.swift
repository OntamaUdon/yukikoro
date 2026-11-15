import SwiftUI
import SceneKit
import UIKit
import simd

// MARK: 地図の印

/// 地図に立つ、塔の印。高さが見えるように、雪玉を積み重ねた形で、縦に長く描く（高さは誇張した見た目）。
struct TowerMarker: View {
    let tower: Tower
    var inRange = false
    var config: TowerConfig = .standard

    /// 雪玉ごとに、でこぼこの形が変わるための数（雪玉の id から決まる）
    static func seed(for ball: Ball) -> UInt64 {
        ball.id.unicodeScalars.reduce(UInt64(17)) { $0 &* 31 &+ UInt64($1.value) } % 100_000
    }

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
                    .fill(Soft.drop)
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
                    SnowBallDisc(size: sizes[index], seed: TowerMarker.seed(for: tower.balls[index]))
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
                .background(Capsule().fill(Soft.surface))
        }
    }
}

// MARK: 3D の塔

enum TowerScene {
    /// 雪のざらざら（白地に、うす青のつぶ）
    private static func speckle(size: Int = 256) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let cg = context.cgContext
            UIColor(red: 0.98, green: 0.99, blue: 1.0, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            var generator = SplitMix64(seed: 11)
            for _ in 0..<300 {
                let x = CGFloat(generator.next() % 1_000) / 1_000 * CGFloat(size)
                let y = CGFloat(generator.next() % 1_000) / 1_000 * CGFloat(size)
                let r = 1.2 + CGFloat(generator.next() % 100) / 100 * 7
                let alpha = 0.04 + CGFloat(generator.next() % 100) / 100 * 0.09
                UIColor(red: 0.70, green: 0.82, blue: 0.98, alpha: alpha).setFill()
                for dx in [-CGFloat(size), 0, CGFloat(size)] {
                    for dy in [-CGFloat(size), 0, CGFloat(size)] {
                        cg.fillEllipse(in: CGRect(x: x + dx - r, y: y + dy - r, width: r * 2, height: r * 2))
                    }
                }
            }
        }
    }

    /// きらきら光る点（つやの地図。ほとんど黒で、白い点だけ光る）
    private static func glitter(size: Int = 256) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            var generator = SplitMix64(seed: 29)
            for _ in 0..<150 {
                let x = CGFloat(generator.next() % 1_000) / 1_000 * CGFloat(size)
                let y = CGFloat(generator.next() % 1_000) / 1_000 * CGFloat(size)
                let r = 0.8 + CGFloat(generator.next() % 100) / 100 * 1.6
                UIColor(white: 0.9 + CGFloat(generator.next() % 100) / 1_000, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
    }

    /// 足もとの、うす青いかげ
    private static func shadowImage(size: Int = 128) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let cg = context.cgContext
            let colors = [UIColor(red: 0.20, green: 0.34, blue: 0.62, alpha: 0.55).cgColor, UIColor(red: 0.20, green: 0.34, blue: 0.62, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                let c = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
                cg.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2, options: [])
            }
        }
    }

    /// でこぼこの雪玉（球の表面を、ゆるやかにへこませたりふくらませたりする）
    private static func lumpySphere(radius: Double, seed: Double, material: SCNMaterial) -> SCNGeometry {
        let rings = 28
        let segments = 48
        let stride = segments + 1
        func noise(_ x: Double, _ y: Double, _ z: Double) -> Double {
            0.55 * sin(2.3 * x + 1.7 * y + seed) * cos(1.9 * z - 0.7 * x + seed * 0.7)
                + 0.30 * sin(4.7 * y - 3.1 * z + seed * 1.3) * cos(3.7 * x + 2.1 * y)
                + 0.15 * sin(8.9 * x + 6.3 * z + seed * 2.1)
        }
        var positions: [SIMD3<Float>] = []
        var uvs: [CGPoint] = []
        for i in 0...rings {
            let v = Double(i) / Double(rings)
            let phi = v * .pi
            for j in 0...segments {
                let u = Double(j) / Double(segments)
                let theta = u * 2 * .pi
                let x = sin(phi) * cos(theta)
                let y = cos(phi)
                let z = sin(phi) * sin(theta)
                let r = radius * (1 + 0.04 * noise(x, y, z))
                positions.append(SIMD3(Float(x * r), Float(y * r), Float(z * r)))
                uvs.append(CGPoint(x: u * 2, y: v * 2))
            }
        }
        var indices: [UInt32] = []
        var accumulated = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for i in 0..<rings {
            for j in 0..<segments {
                let a = UInt32(i * stride + j)
                let b = a + 1
                let c = UInt32((i + 1) * stride + j)
                let d = c + 1
                for tri in [(a, c, b), (b, c, d)] {
                    indices += [tri.0, tri.1, tri.2]
                    let p0 = positions[Int(tri.0)], p1 = positions[Int(tri.1)], p2 = positions[Int(tri.2)]
                    let n = simd_cross(p1 - p0, p2 - p0)
                    accumulated[Int(tri.0)] += n
                    accumulated[Int(tri.1)] += n
                    accumulated[Int(tri.2)] += n
                }
            }
        }
        // つなぎめ（東西の端）と、てっぺん・底の、法線をそろえる
        for i in 0...rings {
            let left = i * stride
            let right = i * stride + segments
            let sum = accumulated[left] + accumulated[right]
            accumulated[left] = sum
            accumulated[right] = sum
        }
        for row in [0, rings] {
            var sum = SIMD3<Float>.zero
            for j in 0...segments { sum += accumulated[row * stride + j] }
            for j in 0...segments { accumulated[row * stride + j] = sum }
        }
        var normals: [SCNVector3] = []
        for (index, n) in accumulated.enumerated() {
            var unit = simd_length(n) > 1e-8 ? simd_normalize(n) : simd_normalize(positions[index])
            // 外向きにそろえる
            if simd_dot(unit, simd_normalize(positions[index])) < 0 { unit = -unit }
            normals.append(SCNVector3(unit.x, unit.y, unit.z))
        }
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) }),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: uvs),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.materials = [material]
        return geometry
    }

    static func make(diameters: [Double], dark: Bool = false) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let snow = SCNMaterial()
        snow.lightingModel = .blinn
        snow.diffuse.contents = speckle()
        snow.diffuse.wrapS = .repeat
        snow.diffuse.wrapT = .repeat
        snow.specular.contents = glitter()
        snow.specular.wrapS = .repeat
        snow.specular.wrapT = .repeat
        snow.shininess = 0.35
        snow.isDoubleSided = true

        var y = 0.0
        var placed: [(bottom: Double, diameter: Double)] = []
        for (index, d) in diameters.enumerated() {
            let node = SCNNode(geometry: lumpySphere(radius: d / 2, seed: Double(index) * 1.7 + 0.5, material: snow))
            node.position = SCNVector3(0, Float(y + d / 2), 0)
            node.eulerAngles = SCNVector3(Float(index) * 0.4, Float(index) * 1.3, Float(index) * 0.2)
            scene.rootNode.addChildNode(node)
            placed.append((y, d))
            y += d * 0.94
        }
        // 玉と玉のつなぎめに、押しかためた雪のふくらみ
        for index in 1..<max(1, placed.count) {
            let joint = SCNNode(geometry: SCNSphere(radius: placed[index].diameter * 0.34))
            joint.geometry?.materials = [snow]
            joint.scale = SCNVector3(1, 0.4, 1)
            joint.position = SCNVector3(0, Float(placed[index].bottom + placed[index].diameter * 0.03), 0)
            scene.rootNode.addChildNode(joint)
        }
        let height = max(0.2, y + (diameters.last ?? 0) * 0.06)
        let baseDiameter = diameters.first ?? 0.3

        // 足もとのかげ（地面は描かない。まわりの面と、なじませるため）
        let shadow = SCNPlane(width: baseDiameter * 2.2, height: baseDiameter * 2.2)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.diffuse.contents = shadowImage()
        shadowMaterial.writesToDepthBuffer = false
        shadowMaterial.isDoubleSided = true
        shadow.materials = [shadowMaterial]
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        shadowNode.position = SCNVector3(0, 0.003, 0)
        scene.rootNode.addChildNode(shadowNode)

        // 光（左上から。きらきらが光るように、強めの 1 本）
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 1)
        ambient.light?.intensity = dark ? 800 : 1_150
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1)
        sun.light?.intensity = 1_100
        sun.eulerAngles = SCNVector3(-0.7, 0.55, 0)
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
    @Environment(\.colorScheme) private var colorScheme

    final class Coordinator {
        var last: [Double] = []
        var lastDark = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        let dark = colorScheme == .dark
        view.scene = TowerScene.make(diameters: diameters, dark: dark)
        context.coordinator.last = diameters
        context.coordinator.lastDark = dark
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let dark = colorScheme == .dark
        if context.coordinator.last != diameters || context.coordinator.lastDark != dark {
            context.coordinator.last = diameters
            context.coordinator.lastDark = dark
            view.scene = TowerScene.make(diameters: diameters, dark: dark)
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
