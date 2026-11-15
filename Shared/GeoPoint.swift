import Foundation

/// 緯度・経度（度）。CoreLocation に頼らない、決まりのテスト用の型。
struct GeoPoint: Codable, Equatable, Hashable {
    var lat: Double
    var lon: Double

    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    /// 2 点のあいだの距離（メートル。球面上）
    func distance(to other: GeoPoint) -> Double {
        let earth = 6_371_000.0
        let p1 = lat * .pi / 180
        let p2 = other.lat * .pi / 180
        let dp = (other.lat - lat) * .pi / 180
        let dl = (other.lon - lon) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earth * asin(min(1, a.squareRoot()))
    }
}

/// 位置を、約 50 m 四方の格子に切る。サーバーに載せるのは、いる場所の「格子の中のランダムな点」だけ。
enum GeoGrid {
    static let metersPerDegreeLatitude = 111_320.0

    /// 緯度方向の 1 マスの大きさ（度）
    static func latitudeStep(size: Double) -> Double { size / metersPerDegreeLatitude }

    /// 緯度の行 `row` での、経度方向の 1 マスの大きさ（度）。高い緯度ほど、同じ距離でも経度の幅が広い。
    static func longitudeStep(row: Int, size: Double) -> Double {
        let centerLatitude = (Double(row) + 0.5) * latitudeStep(size: size)
        return size / (metersPerDegreeLatitude * max(0.01, cos(centerLatitude * .pi / 180)))
    }

    /// その点が入っている格子の番号（行、列）
    static func cell(of point: GeoPoint, size: Double = 50) -> (row: Int, column: Int) {
        let row = Int(floor(point.lat / latitudeStep(size: size)))
        let column = Int(floor(point.lon / longitudeStep(row: row, size: size)))
        return (row, column)
    }

    /// その点が入っている格子の中の、ランダムな点（一様に）。
    static func randomPoint<G: RandomNumberGenerator>(inCellOf point: GeoPoint, size: Double = 50, using generator: inout G) -> GeoPoint {
        let (row, column) = cell(of: point, size: size)
        let latStep = latitudeStep(size: size)
        let lonStep = longitudeStep(row: row, size: size)
        let u = Double.random(in: 0..<1, using: &generator)
        let v = Double.random(in: 0..<1, using: &generator)
        return GeoPoint(lat: (Double(row) + u) * latStep, lon: (Double(column) + v) * lonStep)
    }

    static func randomPoint(inCellOf point: GeoPoint, size: Double = 50) -> GeoPoint {
        var generator = SystemRandomNumberGenerator()
        return randomPoint(inCellOf: point, size: size, using: &generator)
    }
}
