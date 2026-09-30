enum CowStatus { check, disconnected, insufficient, noData, learning, normal }

extension CowStatusLabel on CowStatus {
  String get label => switch (this) {
    CowStatus.check => '要確認',
    CowStatus.disconnected => '通信途絶',
    CowStatus.insufficient || CowStatus.noData => 'データ不足',
    CowStatus.learning => '判定準備中',
    CowStatus.normal => '通常',
  };

  bool get isDataProblem =>
      this == CowStatus.disconnected ||
      this == CowStatus.insufficient ||
      this == CowStatus.noData;

  static CowStatus fromWire(String value) => switch (value) {
    'check' => CowStatus.check,
    'disconnected' => CowStatus.disconnected,
    'insufficient' => CowStatus.insufficient,
    'no_data' => CowStatus.noData,
    'learning' => CowStatus.learning,
    _ => CowStatus.normal,
  };
}

DateTime _date(dynamic value) => DateTime.parse(value as String).toLocal();
double? _double(dynamic value) =>
    value == null ? null : (value as num).toDouble();
int? _int(dynamic value) => value == null ? null : value as int;

class Dashboard {
  const Dashboard({required this.generatedAt, required this.cows});
  final DateTime generatedAt;
  final List<Cow> cows;

  factory Dashboard.fromJson(Map<String, dynamic> json) => Dashboard(
    generatedAt: _date(json['generated_at']),
    cows: (json['cows'] as List<dynamic>)
        .map((item) => Cow.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class Cow {
  const Cow({
    required this.id,
    required this.name,
    required this.deviceId,
    required this.status,
    required this.reason,
    this.latestMeasuredAt,
    this.batteryPercent,
    this.activityRatio,
    this.latestPosition,
  });
  final String id;
  final String name;
  final String deviceId;
  final CowStatus status;
  final String reason;
  final DateTime? latestMeasuredAt;
  final int? batteryPercent;
  final double? activityRatio;
  final CowPosition? latestPosition;

  factory Cow.fromJson(Map<String, dynamic> json) => Cow(
    id: json['id'] as String,
    name: json['name'] as String,
    deviceId: json['device_id'] as String,
    status: CowStatusLabel.fromWire(json['status'] as String),
    reason: json['reason'] as String,
    latestMeasuredAt: json['latest_measured_at'] == null
        ? null
        : _date(json['latest_measured_at']),
    batteryPercent: _int(json['battery_percent']),
    activityRatio: _double(json['activity_ratio']),
    latestPosition: json['latest_position'] == null
        ? null
        : CowPosition.fromJson(json['latest_position'] as Map<String, dynamic>),
  );
}

class CowPosition {
  const CowPosition({
    required this.latitude,
    required this.longitude,
    required this.measuredAt,
    this.accuracyM,
  });
  final double latitude;
  final double longitude;
  final DateTime measuredAt;
  final double? accuracyM;

  factory CowPosition.fromJson(Map<String, dynamic> json) => CowPosition(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    measuredAt: _date(json['measured_at']),
    accuracyM: _double(json['accuracy_m']),
  );
}

class CowHistory {
  const CowHistory({
    required this.cowId,
    required this.date,
    required this.measurements,
  });
  final String cowId;
  final String date;
  final List<Measurement> measurements;

  factory CowHistory.fromJson(Map<String, dynamic> json) => CowHistory(
    cowId: json['cow_id'] as String,
    date: json['date'] as String,
    measurements: (json['measurements'] as List<dynamic>)
        .map((item) => Measurement.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class Measurement {
  const Measurement({
    required this.measuredAt,
    this.latitude,
    this.longitude,
    this.gpsAccuracyM,
    required this.activitySeconds,
    required this.coverageSeconds,
    required this.intervalSeconds,
  });
  final DateTime measuredAt;
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracyM;
  final int activitySeconds;
  final int coverageSeconds;
  final int intervalSeconds;

  bool get hasUsableCoordinate =>
      latitude != null &&
      longitude != null &&
      (gpsAccuracyM == null || gpsAccuracyM! <= 100);
  double get activityRatio =>
      coverageSeconds == 0 ? 0 : activitySeconds / coverageSeconds;

  factory Measurement.fromJson(Map<String, dynamic> json) => Measurement(
    measuredAt: _date(json['measured_at']),
    latitude: _double(json['latitude']),
    longitude: _double(json['longitude']),
    gpsAccuracyM: _double(json['gps_accuracy_m']),
    activitySeconds: json['activity_seconds'] as int,
    coverageSeconds: json['coverage_seconds'] as int,
    intervalSeconds: json['interval_seconds'] as int,
  );
}

class FarmDate {
  static String format(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
