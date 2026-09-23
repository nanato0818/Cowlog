import SwiftUI
import MapKit
import Charts

private func statusColor(_ status: CowStatus) -> Color {
    switch status {
    case .check: return .orange
    case .disconnected, .insufficient, .noData: return .gray
    case .learning: return .blue
    case .normal: return .green
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            List {
                if store.demoMode {
                    Label("サンプルデータを表示中", systemImage: "info.circle")
                        .foregroundStyle(.blue)
                }
                if let error = store.errorMessage {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                }
                if let refreshed = store.dashboard?.generatedAt {
                    Text("データ更新: \(refreshed.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !store.demoMode && Date().timeIntervalSince(refreshed) > 1800 {
                        Label("表示中の情報は30分以上前のものです", systemImage: "clock")
                            .foregroundStyle(.orange)
                    }
                }
                if let cows = store.dashboard?.cows, !cows.isEmpty {
                    ForEach(cows) { cow in
                        NavigationLink {
                            CowDetailView(cowId: cow.id)
                        } label: {
                            CowRow(cow: cow)
                        }
                    }
                } else if !store.isLoading {
                    ContentUnavailableView("表示する牛がいません",
                                           systemImage: "pawprint",
                                           description: Text("接続設定またはデータの登録を確認してください"))
                }
            }
            .navigationTitle("牛の状態")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("更新", systemImage: "arrow.clockwise") {
                        Task { await store.refresh() }
                    }
                }
            }
            .refreshable { await store.refresh() }
        }
        .task {
            await store.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) }
                catch { break }
                await store.refresh()
            }
        }
    }
}

struct CowRow: View {
    let cow: Cow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(cow.name).font(.headline)
                Spacer()
                Text(cow.status.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusColor(cow.status).opacity(0.16), in: Capsule())
                    .foregroundStyle(statusColor(cow.status))
            }
            Text(cow.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let ratio = cow.activityRatio {
                Text("直近2時間の活動率: \(Int((ratio * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let at = cow.latestMeasuredAt {
                    Text("測定 \(at.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text("測定記録なし")
                }
                if let battery = cow.batteryPercent {
                    Text("電池 \(battery)%")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let fix = cow.latestPosition {
                Text("位置: \(fix.measuredAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("位置記録なし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct OverviewMapView: View {
    @EnvironmentObject private var store: AppStore
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Group {
                if let cows = store.dashboard?.cows,
                   cows.contains(where: { $0.latestPosition != nil }) {
                    Map(position: $camera) {
                        ForEach(cows) { cow in
                            if let fix = cow.latestPosition {
                                Marker(cow.name, coordinate: fix.coordinate)
                                    .tint(statusColor(cow.status))
                            }
                        }
                    }
                    .safeAreaInset(edge: .top) {
                        if store.demoMode {
                            Label("サンプルデータ", systemImage: "info.circle")
                                .font(.caption)
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .background(.regularMaterial)
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(cows) { cow in
                                HStack {
                                    Text(cow.name)
                                    Spacer()
                                    if let fix = cow.latestPosition {
                                        Text(fix.measuredAt.formatted(date: .abbreviated,
                                                                      time: .shortened))
                                    } else {
                                        Text("位置なし")
                                    }
                                }
                            }
                            Text("ピンは最後に測位できた場所です。現在地とは限りません。")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                    }
                } else {
                    ContentUnavailableView("位置情報がありません", systemImage: "mappin.slash")
                }
            }
            .navigationTitle("地図")
        }
    }
}

struct CowDetailView: View {
    @EnvironmentObject private var store: AppStore
    let cowId: String
    @State private var selectedDate = Date()
    @State private var history: CowHistory?
    @State private var historyError: String?
    @State private var camera: MapCameraPosition = .automatic

    private var cow: Cow? { store.dashboard?.cows.first { $0.id == cowId } }

    private var validMeasurements: [Measurement] {
        history?.measurements.filter { $0.coverageSeconds > 0 } ?? []
    }

    private var routeSegments: [[CLLocationCoordinate2D]] {
        guard let history else { return [] }
        var segments: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        var previousTime: Date?
        for item in history.measurements {
            guard let coordinate = item.coordinate else {
                if current.count > 1 { segments.append(current) }
                current = []
                previousTime = nil
                continue
            }
            if let previousTime,
               item.measuredAt.timeIntervalSince(previousTime) > 3600 {
                if current.count > 1 { segments.append(current) }
                current = []
            }
            current.append(coordinate)
            previousTime = item.measuredAt
        }
        if current.count > 1 { segments.append(current) }
        return segments
    }

    private var approximateDistanceKm: Double {
        let meters = routeSegments.reduce(0.0) { total, segment in
            total + zip(segment, segment.dropFirst()).reduce(0.0) { subtotal, pair in
                let first = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                let second = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
                return subtotal + first.distance(from: second)
            }
        }
        return meters / 1000
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if store.demoMode {
                    Label("サンプルデータ", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                if let cow {
                    HStack {
                        Text(cow.status.label)
                            .font(.headline)
                            .foregroundStyle(statusColor(cow.status))
                        Spacer()
                        if let battery = cow.batteryPercent { Text("電池 \(battery)%") }
                    }
                    Text(cow.reason).foregroundStyle(.secondary)
                    if let measured = cow.latestMeasuredAt {
                        Text("最後の測定: \(measured.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                    }
                }

                DatePicker("表示する日", selection: $selectedDate, in: ...Date(),
                           displayedComponents: .date)
                if let error = historyError {
                    Text(error).foregroundStyle(.orange)
                }

                Text("移動経路").font(.headline)
                if let history,
                   history.measurements.contains(where: { $0.coordinate != nil }) {
                    Text("参考移動距離: \(approximateDistanceKm, specifier: "%.1f") km")
                        .font(.subheadline)
                    Map(position: $camera) {
                        ForEach(routeSegments.indices, id: \.self) { index in
                            MapPolyline(coordinates: routeSegments[index])
                                .stroke(.blue, lineWidth: 3)
                        }
                        if let fix = cow?.latestPosition,
                           FarmDate.string(fix.measuredAt) == history.date {
                            Marker("最後の位置", coordinate: fix.coordinate)
                        }
                    }
                    .frame(height: 290)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("距離は測位点を結んだ概算です。精度が分かる場合は100m以内の点だけ使い、1時間を超える空白はつなぎません。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("この日の位置記録はありません")
                        .foregroundStyle(.secondary)
                }
                if let fix = cow?.latestPosition {
                    Text("最後の位置測定: \(fix.measuredAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                    Text(fix.accuracyM.map { "測位精度の目安: 約\(Int($0))m" } ?? "測位精度: 不明")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("行動量の推移").font(.headline)
                if !validMeasurements.isEmpty {
                    Chart(validMeasurements, id: \.measuredAt) { item in
                        BarMark(x: .value("時刻", item.measuredAt),
                                y: .value("活動率", Double(item.activitySeconds) /
                                          Double(item.coverageSeconds)))
                    }
                    .chartYScale(domain: 0...1)
                    .frame(height: 190)
                    Text("活動率 = 動きがあった秒数 ÷ 測定できた秒数。測定できなかった時間は除外しています。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("この日の行動量記録はありません")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(cow?.name ?? "牛の詳細")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(FarmDate.string(selectedDate))-\(store.demoMode)-\(store.baseURL)") {
            do {
                let result = try await store.history(cowId: cowId, date: selectedDate)
                guard !Task.isCancelled else { return }
                history = result
                historyError = nil
                camera = .automatic
            } catch {
                guard !Task.isCancelled else { return }
                history = nil
                historyError = error.localizedDescription
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var enteredURL = ""
    @State private var enteredToken = ""
    @State private var saveMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("サンプルデータを使う", isOn: $store.demoMode)
                } footer: {
                    Text("サンプルデータは実際の牛や牧場の位置ではありません。")
                }
                Section("クラウド接続") {
                    TextField("https://example.com/", text: $enteredURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("閲覧用トークン", text: $enteredToken)
                    Button("接続情報を保存") {
                        saveMessage = nil
                        store.baseURL = enteredURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !enteredToken.isEmpty {
                            saveMessage = ReadTokenStore.save(enteredToken) ? nil : "トークンを保存できませんでした"
                            enteredToken = ""
                        }
                        Task { await store.refresh() }
                    }
                    if let saveMessage {
                        Text(saveMessage).foregroundStyle(.orange)
                    }
                } footer: {
                    Text("実データを見るにはサンプルデータをオフにしてください。HTTPSのAPIが必要です。トークンは端末のキーチェーンに保存します。")
                }
            }
            .navigationTitle("接続設定")
            .onAppear { enteredURL = store.baseURL }
            .onChange(of: store.demoMode) { _, _ in
                Task { await store.refresh() }
            }
        }
    }
}
