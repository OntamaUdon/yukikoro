import Foundation
import CoreGraphics
import simd

/// 歩いて作った「ゆきだま」。削って形を整え、色を付けて、作品に使える。
struct SnowPiece: Codable, Equatable, Identifiable {
    var id = UUID()
    /// 転がした歩数（大きさが決まる）
    var steps: Int
    var madeAt: Date
    var shape: SnowShape

    /// 作品の中での半径（メートル）
    var radius: Float { Float(BallScale.radius(steps: steps)) }

    /// 直径（メートル）。削った形の最大幅で測る。
    var diameter: Double { BallScale.diameter(steps: steps, extent: shape.maxExtent) }
}

/// 作品の中に置いたゆきだま（横から見た2Dの絵）
struct Placement: Codable, Equatable, Identifiable {
    var piece: SnowPiece
    /// 中心の位置（メートル）。x が右、y が地面からの高さ。
    var position: SIMD2<Float>
    /// 向き（ラジアン。反時計回り）。削った面をどちらへ向けるか。
    var angle: Float = 0

    /// ゆきだまは1つの場所にしか置けないので、ゆきだまの ID をそのまま使う
    var id: UUID { piece.id }

    /// 輪郭がいちばん遠くまで届く半径（メートル）
    var reach: Float { piece.radius * piece.shape.maxExtent }
}

/// 複数のゆきだまを組み合わせた作品（雪の彫刻）
struct Artwork: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var placements: [Placement] = []

    /// 球どうしが少しめり込むくらいで積む（雪がくっつく感じ）
    static let contactFactor: Float = 0.95

    /// 地面（y=0）か、すでにあるゆきだまの上に、ぴったり乗る中心の高さ。
    static func settleHeight(x: Float, radius: Float, among others: [Placement], excluding: UUID? = nil) -> Float {
        var y = radius
        for o in others where o.id != excluding {
            let dx = x - o.position.x
            let reach = (radius + o.piece.radius) * contactFactor
            if abs(dx) < reach {
                y = max(y, o.position.y + (reach * reach - dx * dx).squareRoot())
            }
        }
        return y
    }
}

/// 作品の画面のカメラ（メートル ⇔ 画面の点）。
struct ArtworkCamera {
    /// 1メートルあたりの点の数
    var scale: CGFloat
    /// 画面の中央に来る x（メートル）
    var centerX: Float
    /// 地面の画面上の y
    var groundY: CGFloat
    var width: CGFloat

    func point(_ world: SIMD2<Float>) -> CGPoint {
        CGPoint(x: width / 2 + CGFloat(world.x - centerX) * scale, y: groundY - CGFloat(world.y) * scale)
    }

    func world(_ p: CGPoint) -> SIMD2<Float> {
        SIMD2<Float>(centerX + Float((p.x - width / 2) / scale), Float((groundY - p.y) / scale))
    }

    /// 置いたゆきだま全体が画面に収まるカメラ
    /// - Parameter bottomInset: 下に重なる操作パネルの高さ（点）。その分を避けて収める。
    static func fitting(_ placements: [Placement], size: CGSize, bottomInset: CGFloat = 0) -> ArtworkCamera {
        let usable = size.height - bottomInset
        let groundY = usable * 0.72
        guard !placements.isEmpty else {
            return ArtworkCamera(scale: 180, centerX: 0, groundY: groundY, width: size.width)
        }
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude, top: Float = 0
        for p in placements {
            minX = min(minX, p.position.x - p.reach)
            maxX = max(maxX, p.position.x + p.reach)
            top = max(top, p.position.y + p.reach)
        }
        let spanX = max(0.2, maxX - minX)
        let availH = groundY - usable * 0.14
        let sx = size.width * 0.86 / CGFloat(spanX)
        let sy = availH / CGFloat(max(0.2, top))
        let scale = min(260, max(15, min(sx, sy)))
        return ArtworkCamera(scale: scale, centerX: (minX + maxX) / 2, groundY: groundY, width: size.width)
    }
}

/// 作品を組み立てる操作の状態（画面とは独立していて、単体テストできる）
final class ComposeModel: ObservableObject {
    @Published var artwork: Artwork
    @Published private(set) var selectedID: UUID?
    var onChange: ((Artwork) -> Void)?

    private var dragOffset = SIMD2<Float>(0, 0)
    private var dragID: UUID?

    init(artwork: Artwork) { self.artwork = artwork }

    var selected: Placement? {
        guard let id = selectedID else { return nil }
        return artwork.placements.first { $0.id == id }
    }

    private func index(of id: UUID) -> Int? { artwork.placements.firstIndex { $0.id == id } }

    // MARK: 選ぶ・動かす

    /// その位置にあるゆきだま（手前にあるものを優先）
    func hit(at world: SIMD2<Float>) -> UUID? {
        for p in artwork.placements.reversed() {
            if simd_distance(world, p.position) <= p.reach * 0.95 { return p.id }
        }
        return nil
    }

    func select(_ id: UUID?) { selectedID = id }

    /// ドラッグの開始。ゆきだまの上なら選んで動かし始める。
    @discardableResult
    func beginDrag(at world: SIMD2<Float>) -> Bool {
        guard let id = hit(at: world), let i = index(of: id) else {
            dragID = nil
            return false
        }
        selectedID = id
        // 手前に出す
        let placement = artwork.placements.remove(at: i)
        artwork.placements.append(placement)
        dragID = id
        dragOffset = placement.position - world
        return true
    }

    func drag(to world: SIMD2<Float>) {
        guard let id = dragID, let i = index(of: id) else { return }
        var pos = world + dragOffset
        let r = artwork.placements[i].piece.radius
        pos.y = max(r * 0.6, pos.y)
        artwork.placements[i].position = pos
    }

    /// ドラッグの終わり。地面や下のゆきだまの近くなら、ぴたっと乗せる。
    func endDrag() {
        guard let id = dragID, let i = index(of: id) else { return }
        dragID = nil
        let p = artwork.placements[i]
        let ground = Artwork.settleHeight(x: p.position.x, radius: p.piece.radius, among: artwork.placements, excluding: id)
        if abs(p.position.y - ground) < 0.35 * p.piece.radius {
            artwork.placements[i].position.y = ground
        }
        commit()
    }

    // MARK: 編集

    func commit() {
        artwork.updatedAt = Date()
        onChange?(artwork)
    }

    func add(_ piece: SnowPiece) {
        let r = piece.radius * piece.shape.maxExtent
        var x: Float = 0
        if let edge = artwork.placements.map({ $0.position.x + $0.reach }).max() {
            x = edge + r + 0.1
        }
        let y = Artwork.settleHeight(x: x, radius: piece.radius, among: artwork.placements)
        artwork.placements.append(Placement(piece: piece, position: SIMD2<Float>(x, y)))
        selectedID = piece.id
        commit()
    }

    /// 選んだゆきだまを作品から外す（呼び出し側でストックに戻す）
    func removeSelected() -> SnowPiece? {
        guard let id = selectedID, let i = index(of: id) else { return nil }
        let piece = artwork.placements.remove(at: i).piece
        selectedID = nil
        commit()
        return piece
    }

    func rotateSelected(by angle: Float) {
        guard let id = selectedID, let i = index(of: id) else { return }
        artwork.placements[i].angle += angle
        commit()
    }

    func settleSelected() {
        guard let id = selectedID, let i = index(of: id) else { return }
        let p = artwork.placements[i]
        artwork.placements[i].position.y = Artwork.settleHeight(x: p.position.x, radius: p.piece.radius, among: artwork.placements, excluding: id)
        commit()
    }

    func setAngle(id: UUID, angle: Float) {
        guard let i = index(of: id) else { return }
        artwork.placements[i].angle = angle
        commit()
    }

    func updateShape(id: UUID, shape: SnowShape) {
        guard let i = index(of: id) else { return }
        artwork.placements[i].piece.shape = shape
        commit()
    }
}
