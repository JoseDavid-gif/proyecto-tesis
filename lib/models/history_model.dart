import 'dashboard_model.dart';

enum HistorySeverityFilter {
  all(label: 'Todos'),
  mild(label: 'Leve', databaseValue: 'Leve'),
  moderate(label: 'Moderado', databaseValue: 'Moderado'),
  severe(label: 'Severo', databaseValue: 'Severo'),
  undetermined(
    label: 'No determinada',
    databaseValue: 'No determinada',
  );

  const HistorySeverityFilter({
    required this.label,
    this.databaseValue,
  });

  final String label;
  final String? databaseValue;
}

class HistoryPage {
  const HistoryPage({
    required this.reports,
    required this.hasMore,
  });

  final List<DashboardReport> reports;
  final bool hasMore;
}

String historyThumbnailUrl(String source, {int width = 360}) {
  final trimmed = source.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.host.endsWith('cloudinary.com') ||
      !uri.path.contains('/upload/') ||
      width < 1) {
    return trimmed;
  }

  return trimmed.replaceFirst(
    '/upload/',
    '/upload/f_auto,q_auto,w_$width,c_limit/',
  );
}
