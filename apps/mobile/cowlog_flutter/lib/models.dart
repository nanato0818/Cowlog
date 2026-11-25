bool validCoordinate(double latitude, double longitude) =>
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180;

/// Display appearance only, not a breed/health classification.
enum CowStyle {
  unknown,
  holstein,
  brown;

  String get label => switch (this) {
    CowStyle.unknown => '未設定',
    CowStyle.holstein => '白黒',
    CowStyle.brown => '茶色',
  };
  static CowStyle fromWire(dynamic value) => switch (value) {
    'holstein' => holstein,
    'brown' => brown,
    _ => unknown,
  };
}

enum CowStatus {
  check,
  unknown,
  disconnected,
  insufficient,
  noData,
  learning,
  normal,
}

extension CowStatusLabel on CowStatus {
  String get label => switch (this) {
    CowStatus.check => '要確認',
    CowStatus.unknown => '不明',
    CowStatus.disconnected => '通信途絶',
    CowStatus.insufficient => 'データ不足',
    CowStatus.noData => '未受信',
    CowStatus.learning => '判定準備中',
    CowStatus.normal => '通常',
  };

  bool get isDataProblem =>
      this == CowStatus.disconnected ||
      this == CowStatus.insufficient ||
      this == CowStatus.noData;

  static CowStatus fromWire(String value) => switch (value) {
    'check' => CowStatus.check,
    'normal' => CowStatus.normal,
    'disconnected' => CowStatus.disconnected,
    'insufficient' => CowStatus.insufficient,
    'no_data' => CowStatus.noData,
    'learning' => CowStatus.learning,
    _ => CowStatus.unknown,
  };
}

DateTime _date(dynamic value) => DateTime.parse(value as String).toLocal();
double? _double(dynamic value) =>
    value == null ? null : (value as num).toDouble();
int? _int(dynamic value) => value == null ? null : (value as num).round();

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
    this.profile,
    this.number,
    this.style = CowStyle.unknown,
  });
  final CowStyle style;
  final CowProfile? profile;
  final String? number;
  String get displayNumber => number ?? profile?.herdNumber ?? name;
  final String id;
  final String name;
  final String? deviceId;
  final CowStatus status;
  final String reason;
  final DateTime? latestMeasuredAt;
  final int? batteryPercent;
  final double? activityRatio;
  final CowPosition? latestPosition;

  factory Cow.fromJson(Map<String, dynamic> json) => Cow(
    profile: json['profile'] == null
        ? null
        : CowProfile.fromJson(json['profile'] as Map<String, dynamic>),
    number: json['number'] as String?,
    style: CowStyle.fromWire(json['cow_style']),
    id: json['id'] as String,
    name: json['name'] as String,
    deviceId: json['device_id'] as String?,
    status: CowStatusLabel.fromWire(json['status'] as String),
    reason: (json['reason'] as String?) ?? '',
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
    this.hdop,
    this.satellites,
  });
  final double latitude;
  final double longitude;
  final DateTime measuredAt;
  final double? accuracyM;
  final double? hdop;
  final int? satellites;

  bool get isUsable =>
      validCoordinate(latitude, longitude) &&
      (accuracyM == null ||
          (accuracyM!.isFinite && accuracyM! >= 0 && accuracyM! <= 100));
  bool isStaleAt(DateTime now) =>
      now.difference(measuredAt) > const Duration(minutes: 15);

  factory CowPosition.fromJson(Map<String, dynamic> json) => CowPosition(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    measuredAt: _date(json['measured_at']),
    accuracyM: _double(json['accuracy_m']),
    hdop: _double(json['hdop']),
    satellites: _int(json['satellites']),
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
      validCoordinate(latitude!, longitude!) &&
      (gpsAccuracyM == null ||
          (gpsAccuracyM!.isFinite &&
              gpsAccuracyM! >= 0 &&
              gpsAccuracyM! <= 100));
  double get activityRatio =>
      coverageSeconds == 0 ? 0 : activitySeconds / coverageSeconds;

  factory Measurement.fromJson(Map<String, dynamic> json) => Measurement(
    measuredAt: _date(json['measured_at']),
    latitude: _double(json['latitude']),
    longitude: _double(json['longitude']),
    gpsAccuracyM: _double(json['gps_accuracy_m']),
    activitySeconds: (json['activity_seconds'] as num).round(),
    coverageSeconds: (json['coverage_seconds'] as num).round(),
    intervalSeconds: (json['interval_seconds'] as num).round(),
  );
}

class FarmDate {
  static String format(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

class CowProfile {
  const CowProfile({
    required this.herdNumber,
    required this.breed,
    required this.birthDate,
    this.individualNumber,
    this.features,
    this.parity,
    this.lastCalvingDate,
  });
  final String herdNumber;
  final String breed;
  final String birthDate;
  final String? individualNumber;
  final String? features;
  final int? parity;
  final String? lastCalvingDate;
  factory CowProfile.fromJson(Map<String, dynamic> j) => CowProfile(
    herdNumber: j['herd_number'] as String,
    breed: j['breed'] as String,
    birthDate: j['birth_date'] as String,
    individualNumber: j['individual_number'] as String?,
    features: j['features'] as String?,
    parity: _int(j['parity']),
    lastCalvingDate: j['last_calving_date'] as String?,
  );
}

class Collar {
  const Collar({
    required this.deviceId,
    this.number,
    this.lastSeenAt,
    this.style = CowStyle.unknown,
  });
  final CowStyle style;
  final String deviceId;
  final String? number;
  final DateTime? lastSeenAt;
  factory Collar.fromJson(Map<String, dynamic> json) => Collar(
    deviceId: json['device_id'] as String,
    number: json['number'] as String?,
    style: CowStyle.fromWire(json['cow_style']),
    lastSeenAt: json['last_seen_at'] == null
        ? null
        : _date(json['last_seen_at']),
  );
}
