class GpsData {
  final int t;
  final double speed;
  final double calculatedSpeed;
  final double smoothedCalculated;
  final double smoothed;
  final double lat;
  final double lon;
  final double distance;
  final double spm;
  final double spm2;
  final bool outlier;

  GpsData({
    required this.t,
    required this.speed,
    required this.calculatedSpeed,
    required this.smoothedCalculated,
    required this.smoothed,
    required this.lat,
    required this.lon,
    required this.distance,
    required this.spm,
    required this.spm2,
    required this.outlier,
  });

  factory GpsData.fromJson(Map<String, dynamic> json) {
    return GpsData(
      t: json['t'],
      speed: json['speed'] ?? 0.0,
      calculatedSpeed: json['calculatedSpeed'] ?? 0.0,
      smoothedCalculated: json['smoothedCalculated'] ?? 0.0,
      smoothed: json['smoothed'] ?? 0.0,
      lat: json['lat'],
      lon: json['lon'],
      distance: json['distance'] ?? 0.0,
      spm: json['spm'] ?? 0.0,
      spm2: json['spm2'] ?? 0.0,
      outlier: json['outlier'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      't': t,
      'speed': speed,
      'calculatedSpeed': calculatedSpeed,
      'smoothedCalculated': smoothedCalculated,
      'smoothed': smoothed,
      'lat': lat,
      'lon': lon,
      'distance': distance,
      'spm': spm,
      'spm2': spm2,
      'outlier': outlier,
    };
  }

  /// Returns field names (headers)
  static List<String> csvHeaders({bool includeLogId = true}) {
    return [
      if (includeLogId) 'logId',
      't',
      'speed',
      'calculatedSpeed',
      'smoothedCalculated',
      'smoothed',
      'lat',
      'lon',
      'distance',
      'spm',
      'spm2',
      'outlier',
    ];
  }

  /// Returns field values as a list of strings (for CSV row)
  List<String> toCsvRow(String logId) {
    return [
      logId,
      t.toString(),
      speed.toString(),
      calculatedSpeed.toString(),
      smoothedCalculated.toString(),
      smoothed.toString(),
      lat.toString(),
      lon.toString(),
      distance.toString(),
      spm.toString(),
      spm2.toString(),
      outlier.toString(),
    ];
  }
}
