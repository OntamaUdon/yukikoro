import Foundation
import CoreLocation
import Observation

/// いまの位置（ふつうの位置と、試験用に指定した位置）
struct LocationSnapshot: Equatable {
    var point: GeoPoint
    var accuracy: Double?
    var speed: Double?
    var simulated: Bool
    var accessory: Bool
    /// 試験用に指定した位置（ごまかしの確認をしない）
    var isTest: Bool

    func issue(config: TowerConfig) -> LocationIssue? {
        if isTest { return nil }
        return TowerRules.locationIssue(horizontalAccuracy: accuracy, speed: speed, simulated: simulated,
                                        accessory: accessory, config: config)
    }
}

/// 位置情報。アプリを使っている間だけ取る（バックグラウンドでは取らない）。
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var current: CLLocation?
    private(set) var status: CLAuthorizationStatus = .notDetermined
    /// 試験用に、いることにする位置
    var testPoint: GeoPoint?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        status = manager.authorizationStatus
    }

    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    var isDenied: Bool { status == .denied || status == .restricted }

    func start() {
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        if isAuthorized { manager.startUpdatingLocation() }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// いま使う位置
    var snapshot: LocationSnapshot? {
        if let testPoint {
            return LocationSnapshot(point: testPoint, accuracy: 5, speed: 0, simulated: false, accessory: false, isTest: true)
        }
        guard let location = current else { return nil }
        let source = location.sourceInformation
        return LocationSnapshot(
            point: GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude),
            accuracy: location.horizontalAccuracy,
            speed: location.speed,
            simulated: source?.isSimulatedBySoftware ?? false,
            accessory: source?.isProducedByAccessory ?? false,
            isTest: false
        )
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.current = last
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in
            self.status = newStatus
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 位置が取れないときは、そのまま（画面で「位置が取れません」と出す）
    }
}

/// 位置から、都道府県を調べる（逆ジオコーディング。おくときだけ使う）
enum PrefectureResolver {
    struct Result {
        var code: Int?
        var isJapan: Bool
    }

    static func resolve(_ point: GeoPoint) async -> Result? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: point.lat, longitude: point.lon))
            guard let first = placemarks.first else { return nil }
            let isJapan = first.isoCountryCode == "JP"
            return Result(code: Prefecture.code(fromAdministrativeArea: first.administrativeArea), isJapan: isJapan)
        } catch {
            return nil
        }
    }
}
