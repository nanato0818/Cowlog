import Foundation
import CoreLocation

struct Dashboard: Decodable {
    let generatedAt: Date
    let cows: [Cow]
}

struct Cow: Decodable, Identifiable {
    let id: String
    let name: String
    let deviceId: String
    let status: CowStatus
    let reason: String
    let latestMeasuredAt: Date?
    let batteryPercent: Int?
    let activityRatio: Double?
    let latestPosition: CowPosition?
}

enum CowStatus: String, Decodable {
    case check, disconnected, insufficient, noData = "no_data", learning, normal

    var label: String {
        switch self {
        case .check: return "要確認"
        case .disconnected: return "通信途絶"
        case .insufficient, .noData: return "データ不足"
        case .learning: return "判定準備中"
        case .normal: return "通常"
        }
    }

    var isDataProblem: Bool {
        self == .disconnected || self == .insufficient || self == .noData
    }
}

struct CowPosition: Decodable {
    let latitude: Double
    let longitude: Double
    let measuredAt: Date
    let accuracyM: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct CowHistory: Decodable {
    let cowId: String
    let date: String
    let measurements: [Measurement]
}

struct Measurement: Decodable {
    let measuredAt: Date
    let latitude: Double?
    let longitude: Double?
    let gpsAccuracyM: Double?
    let activitySeconds: Int
    let coverageSeconds: Int
    let intervalSeconds: Int

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        if let gpsAccuracyM, gpsAccuracyM > 100 { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum JSONCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
