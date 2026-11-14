import Foundation
import simd

/// 歩いて作った「ゆきだま」。削ったり色を塗ったりして形を変えられる。
struct SnowPiece: Codable, Equatable, Identifiable {
    var id = UUID()
    /// 転がした歩数（大きさが決まる）
    var steps: Int
    var madeAt: Date
    var shape: SnowShape

    /// 作品の中での半径（場面の単位）
    var radius: Float { Float(BallScale.radius(steps: steps)) }

    /// 直径（メートル）。削った形の最大幅で測る。
    var diameter: Double { BallScale.diameter(steps: steps, extent: shape.maxExtent) }
}

/// 作品の中に置いたゆきだま
struct Placement: Codable, Equatable, Identifiable {
    var piece: SnowPiece
    /// ゆきだまの中心の位置
    var position: SIMD3<Float>
    /// 向き（クォータニオン x, y, z, w）。削った面をどちらへ向けるか。
    var rotation: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1)

    /// ゆきだまは1つの場所にしか置けないので、ゆきだまの ID をそのまま使う
    var id: UUID { piece.id }

    var orientation: simd_quatf {
        get { simd_quatf(ix: rotation.x, iy: rotation.y, iz: rotation.z, r: rotation.w) }
        set { rotation = SIMD4<Float>(newValue.imag.x, newValue.imag.y, newValue.imag.z, newValue.real) }
    }
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
    static func settleHeight(x: Float, z: Float, radius: Float, among others: [Placement], excluding: UUID? = nil) -> Float {
        var y = radius
        for o in others where o.id != excluding {
            let dx = x - o.position.x
            let dz = z - o.position.z
            let reach = (radius + o.piece.radius) * contactFactor
            let d2 = dx * dx + dz * dz
            if d2 < reach * reach {
                y = max(y, o.position.y + (reach * reach - d2).squareRoot())
            }
        }
        return y
    }
}
