import Foundation
import simd

/// 刃（ヘラ）の大きさ。縦の板の高さで、一度に削れる幅が変わる。
enum BladeSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }

    /// 刃の高さ（雪玉の半径 = 1 としたときの長さ）
    var height: Float {
        switch self {
        case .small: return 0.45
        case .medium: return 1.0
        case .large: return 3.2
        }
    }
}

/// 雪玉の輪郭（横から見た形）と色。中心からの距離を、角度ごとの「基準の半径に対する倍率」で持つ。
/// 色は雪玉ぜんたいで1色。
struct SnowShape: Equatable, Hashable {
    var seed: UInt32
    /// 角度ごとの半径の倍率（1 が元の円の大きさ）
    var radii: [Float]
    /// 雪玉の色（RGB。255,255,255 が白）
    var tint: [UInt8]

    static let pointCount = 180
    static let minRadius: Float = 0.05
    static let maxRadius: Float = 2.5
    /// 刃は、中心からこれより近くには入れない（雪玉が消えてしまわないように）
    static let minCutDepth: Float = 0.2

    /// 角度ごとの向き（x が右、y が上。0 番は右向きで、反時計回り）
    static let directions: [SIMD2<Float>] = (0..<pointCount).map { k -> SIMD2<Float> in
        let a = Float(k) / Float(pointCount) * 2 * Float.pi
        return SIMD2<Float>(cos(a), sin(a))
    }

    /// 手を加える前の、すこしでこぼこした白い雪玉
    static func pristine(seed: UInt32) -> SnowShape {
        let p1 = Float(seed % 97) * 0.37
        let p2 = Float((seed / 97) % 89) * 0.41
        let p3 = Float((seed / 8_633) % 83) * 0.53
        var radii = [Float](repeating: 1, count: pointCount)
        for k in 0..<pointCount {
            let a = Float(k) / Float(pointCount) * 2 * Float.pi
            radii[k] = 1 + 0.035 * sin(3 * a + p1) + 0.02 * sin(5 * a + p2) + 0.012 * sin(9 * a + p3)
        }
        return SnowShape(seed: seed, radii: radii, tint: [255, 255, 255])
    }

    /// 手を加えたか（色か形が元と違うか）
    var isModified: Bool { self != SnowShape.pristine(seed: seed) }

    /// いちばん遠い所までの半径（基準の半径に対する倍率）
    var maxExtent: Float { radii.max() ?? 1 }

    /// 雪玉の色
    var tintRGB: SIMD3<Float> {
        guard tint.count == 3 else { return SIMD3<Float>(repeating: 1) }
        return SIMD3<Float>(Float(tint[0]), Float(tint[1]), Float(tint[2])) / 255
    }

    mutating func setTint(_ rgb: SIMD3<Float>) {
        tint = [0, 1, 2].map { UInt8(max(0, min(255, (rgb[$0] * 255).rounded()))) }
    }

    /// 雪玉を `angle`（ラジアン。反時計回り）だけ回したときの、角度ごとの向き
    static func rotated(_ k: Int, by angle: Float) -> SIMD2<Float> {
        let d = directions[k]
        let c = cos(angle), s = sin(angle)
        return SIMD2<Float>(d.x * c - d.y * s, d.x * s + d.y * c)
    }

    // MARK: 刃で削る

    /// 刃で削る。刃は縦の板で、画面の横方向（x）の `planeX` にあり、高さは `bandLow`〜`bandHigh`。
    /// 雪玉は `angle` だけ回っている。刃が通った側（刃より左）の雪が、刃の面ぴったりまで取り除かれる。
    /// 刃は x<0（左側）から入る。中心を含む側が残るので、半径の倍率だけで形を表せる。
    /// - Returns: 形が変わったか
    @discardableResult
    mutating func cutBlade(angle: Float, planeX: Float, bandLow y0: Float, bandHigh y1: Float) -> Bool {
        guard y1 > y0 else { return false }
        let a = max(SnowShape.minCutDepth, abs(planeX))
        let s: Float = planeX < 0 ? -1 : 1
        var changed = false
        for k in 0..<radii.count {
            let dw = SnowShape.rotated(k, by: angle)
            let dx = s * dw.x
            guard dx > 1e-4 else { continue }
            let r = radii[k]
            let rx = a / dx
            guard r > rx else { continue }
            // 今の輪郭の点が、刃の高さの範囲に入っているか
            let py = r * dw.y
            guard py >= y0, py <= y1 else { continue }
            // その向きの線が、刃の高さの範囲に入る所までの距離（上面・下面で平らに切れる）
            var lower: Float = 0
            if abs(dw.y) > 1e-5 {
                lower = max(0, min(y0 / dw.y, y1 / dw.y))
            }
            let newR = max(SnowShape.minRadius, max(rx, lower))
            if newR < r - 1e-6 {
                radii[k] = newR
                changed = true
            }
        }
        return changed
    }

    // MARK: 成長

    /// 雪が積もって一回り大きくなる。今の形のまま、どこも同じ厚さで外側に増える。
    /// 形は「基準の半径に対する倍率」なので、実際の長さに直して厚みを足し、新しい基準で割り直す。
    mutating func grow(fromRadius old: Float, toRadius new: Float) {
        guard new > old, old > 0 else { return }
        let thickness = new - old
        for k in 0..<radii.count {
            radii[k] = min(SnowShape.maxRadius, (old * radii[k] + thickness) / new)
        }
    }
}

extension SnowShape: Codable {
    private enum CodingKeys: String, CodingKey { case seed, radii, tint }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let seed = try c.decode(UInt32.self, forKey: .seed)
        let rData = try c.decode(Data.self, forKey: .radii)
        var radii = [Float](repeating: 1, count: rData.count / MemoryLayout<Float>.size)
        radii.withUnsafeMutableBytes { _ = rData.copyBytes(to: $0) }
        var tint = [UInt8](repeating: 255, count: 3)
        if let tData = try c.decodeIfPresent(Data.self, forKey: .tint), tData.count == 3 { tint = [UInt8](tData) }
        if radii.count == SnowShape.pointCount {
            self.init(seed: seed, radii: radii, tint: tint)
        } else {
            // 以前の形式（3D）のデータは、まっさらな玉にする
            self = SnowShape.pristine(seed: seed)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seed, forKey: .seed)
        try c.encode(radii.withUnsafeBufferPointer { Data(buffer: $0) }, forKey: .radii)
        try c.encode(Data(tint), forKey: .tint)
    }
}

/// 雪玉を成形する操作の状態（画面とは独立していて、単体テストできる）。
/// 刃は雪玉の左側に浮いていて、指で上下左右に動かす。刃が雪玉に当たると、通った側が自動で削れる。
final class SculptModel: ObservableObject {
    @Published var shape: SnowShape
    /// 雪玉の向き（ラジアン。反時計回り）
    @Published var angle: Float = 0
    @Published var bladeSize: BladeSize = .medium
    @Published private(set) var bladeX: Float = -1.6
    @Published private(set) var bladeY: Float = 0
    @Published private(set) var bladeActive = false
    @Published private(set) var undoCount = 0
    /// 回転ボタン: -1 = 右回り、0 = 止まっている、1 = 左回り
    @Published var spin: Int = 0

    let baseRadius: Float
    private let original: SnowShape
    private var undoStack: [SnowShape] = []
    private var strokeStartBlade = SIMD2<Float>(0, 0)
    private var strokeUndoPushed = false
    private var lastTick: Date?

    static let bladeXRange: ClosedRange<Float> = -2.0 ... -0.2
    static let bladeYRange: ClosedRange<Float> = -1.8 ... 1.8
    static let spinSpeed: Float = 1.6

    init(shape: SnowShape, baseRadius: Float) {
        self.shape = shape
        self.baseRadius = baseRadius
        original = shape
    }

    var hasChanges: Bool { shape != original }

    /// 雪玉の直径（メートル）。削った形の最大幅で測る。
    var diameter: Double { 2 * Double(baseRadius) * Double(shape.maxExtent) }

    // MARK: 刃

    func beginBlade() {
        bladeActive = true
        strokeStartBlade = SIMD2<Float>(bladeX, bladeY)
        strokeUndoPushed = false
    }

    /// 指の動き（雪玉の半径を 1 とした長さ。右と上が正）で、刃を動かす
    func dragBlade(translation t: SIMD2<Float>) {
        guard bladeActive else { return }
        let x = strokeStartBlade.x + t.x
        let y = strokeStartBlade.y + t.y
        bladeX = min(Self.bladeXRange.upperBound, max(Self.bladeXRange.lowerBound, x))
        bladeY = min(Self.bladeYRange.upperBound, max(Self.bladeYRange.lowerBound, y))
        applyCut()
    }

    func endBlade() { bladeActive = false }

    /// 刃が当たっている所を削る
    func applyCut() {
        guard bladeActive else { return }
        var next = shape
        let half = bladeSize.height / 2
        guard next.cutBlade(angle: angle, planeX: bladeX, bandLow: bladeY - half, bandHigh: bladeY + half) else { return }
        if !strokeUndoPushed {
            pushUndo()
            strokeUndoPushed = true
        }
        shape = next
    }

    // MARK: 回転

    /// 一定の間隔で呼ぶ。回転ボタンを押している間、雪玉を回す（刃を押さえていれば、回りながらも削れる）。
    func tick(now: Date = Date()) {
        defer { lastTick = now }
        guard spin != 0, let last = lastTick else { return }
        let dt = Float(min(0.05, now.timeIntervalSince(last)))
        angle += Float(spin) * Self.spinSpeed * dt
        applyCut()
    }

    // MARK: 色・やり直し

    func setTint(_ rgb: SIMD3<Float>) {
        pushUndo()
        shape.setTint(rgb)
    }

    private func pushUndo() {
        undoStack.append(shape)
        if undoStack.count > 25 { undoStack.removeFirst() }
        undoCount = undoStack.count
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        shape = last
        undoCount = undoStack.count
    }

    func reset() {
        pushUndo()
        shape = SnowShape.pristine(seed: shape.seed)
    }
}
