import 'bache_model.dart';

class DashboardReport {
  const DashboardReport({
    required this.bache,
    required this.hasLocation,
  });

  final Bache bache;
  final bool hasLocation;

  factory DashboardReport.fromMap(Map<String, dynamic> map) {
    final rawLatitude = _nullableDouble(map['latitud']);
    final rawLongitude = _nullableDouble(map['longitud']);
    final hasLocation = rawLatitude != null &&
        rawLongitude != null &&
        rawLatitude.isFinite &&
        rawLongitude.isFinite &&
        rawLatitude >= -90 &&
        rawLatitude <= 90 &&
        rawLongitude >= -180 &&
        rawLongitude <= 180;

    return DashboardReport(
      bache: Bache.fromMap(map, map['id']?.toString() ?? ''),
      hasLocation: hasLocation,
    );
  }

  static double? _nullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class DashboardOverview {
  const DashboardOverview({
    required this.email,
    required this.displayName,
    required this.totalReports,
    required this.reportsWithMetricMeasurement,
    required this.recentReports,
  });

  final String email;
  final String? displayName;
  final int totalReports;
  final int reportsWithMetricMeasurement;
  final List<DashboardReport> recentReports;

  DashboardReport? get latestReport =>
      recentReports.isEmpty ? null : recentReports.first;

  String get greeting => displayName == null ? 'Hola' : 'Hola, $displayName';
}

String? dashboardDisplayName(Map<String, dynamic>? metadata) {
  if (metadata == null) return null;
  for (final key in const [
    'full_name',
    'name',
    'display_name',
    'first_name',
  ]) {
    final value = metadata[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}
