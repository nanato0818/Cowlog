import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    private var refreshVersion = 0
    @Published var dashboard: Dashboard?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var demoMode: Bool {
        didSet {
            UserDefaults.standard.set(demoMode, forKey: "demoMode")
            dashboard = nil
            errorMessage = nil
        }
    }
    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "baseURL") }
    }

    init() {
        demoMode = (UserDefaults.standard.object(forKey: "demoMode") as? Bool) ?? true
        baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? ""
    }

    func refresh() async {
        refreshVersion += 1
        let version = refreshVersion
        isLoading = true
        defer { if version == refreshVersion { isLoading = false } }
        if demoMode {
            dashboard = DemoData.dashboard()
            errorMessage = nil
            return
        }
        do {
            let result = try await APIClient(baseURL: baseURL,
                                             token: ReadTokenStore.load() ?? "").dashboard()
            guard version == refreshVersion && !demoMode else { return }
            dashboard = result
            errorMessage = nil
        } catch {
            guard version == refreshVersion && !demoMode else { return }
            errorMessage = error.localizedDescription
        }
    }

    func history(cowId: String, date: Date) async throws -> CowHistory {
        if demoMode { return DemoData.history(cowId: cowId, date: date) }
        let dateString = FarmDate.string(date)
        return try await APIClient(baseURL: baseURL,
                                   token: ReadTokenStore.load() ?? "")
            .history(cowId: cowId, date: dateString)
    }
}

enum DemoData {
    static func dashboard() -> Dashboard {
        let now = Date()
        let cows = [
            Cow(id: "demo-1", name: "サンプル牛 1", deviceId: "sample-01",
                status: .check, reason: "普段の同じ時間帯より行動量が低下しています",
                latestMeasuredAt: now.addingTimeInterval(-900), batteryPercent: 76,
                activityRatio: 0.02,
                latestPosition: CowPosition(latitude: 35.0000, longitude: 139.0000,
                                            measuredAt: now.addingTimeInterval(-900), accuracyM: 15)),
            Cow(id: "demo-2", name: "サンプル牛 2", deviceId: "sample-02",
                status: .normal, reason: "行動量に大きな低下はありません",
                latestMeasuredAt: now.addingTimeInterval(-1200), batteryPercent: 64,
                activityRatio: 0.31,
                latestPosition: CowPosition(latitude: 35.0010, longitude: 139.0020,
                                            measuredAt: now.addingTimeInterval(-1200), accuracyM: 18))
        ]
        return Dashboard(generatedAt: now, cows: cows)
    }

    static func history(cowId: String, date: Date) -> CowHistory {
        let start = FarmDate.calendar.startOfDay(for: date)
        let measurements: [Measurement] = (0..<96).compactMap { index in
            let time = start.addingTimeInterval(Double(index + 1) * 900)
            if time > Date() { return nil }
            let low = cowId == "demo-1" && time > Date().addingTimeInterval(-7200)
            return Measurement(
                measuredAt: time,
                latitude: 35.0 + Double(index) * 0.000015 + (cowId == "demo-2" ? 0.001 : 0),
                longitude: 139.0 + Double(index) * 0.000025 + (cowId == "demo-2" ? 0.002 : 0),
                gpsAccuracyM: 15,
                activitySeconds: low ? 20 : (index % 3 == 0 ? 380 : 170),
                coverageSeconds: 900, intervalSeconds: 900
            )
        }
        let dateString = FarmDate.string(date)
        return CowHistory(cowId: cowId, date: dateString, measurements: measurements)
    }
}

enum FarmDate {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
