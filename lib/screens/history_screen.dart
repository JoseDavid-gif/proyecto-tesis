import 'dart:async';

import 'package:flutter/material.dart';

import '../models/dashboard_model.dart';
import '../models/history_model.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'map_screen.dart';
import 'report_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    this.historyRepository,
    this.onReportRequested,
  });

  final HistoryRepository? historyRepository;
  final VoidCallback? onReportRequested;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const int _pageSize = 20;

  late final HistoryRepository _historyRepository;
  final ScrollController _scrollController = ScrollController();

  final List<DashboardReport> _reports = [];
  HistorySeverityFilter _filter = HistorySeverityFilter.all;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _sessionExpired = false;
  bool _hasError = false;
  int _requestGeneration = 0;
  int _nextOffset = 0;

  @override
  void initState() {
    super.initState();
    _historyRepository = widget.historyRepository ?? SupabaseService();
    _scrollController.addListener(_onScroll);
    unawaited(_reload());
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 300) {
      unawaited(_loadMore());
    }
  }

  Future<void> _reload() async {
    final generation = ++_requestGeneration;
    setState(() {
      _loadingInitial = true;
      _loadingMore = false;
      _hasError = false;
      _sessionExpired = false;
      _hasMore = false;
      _nextOffset = 0;
      _reports.clear();
    });

    try {
      final page = await _historyRepository.cargarHistorial(
        filter: _filter,
        pageSize: _pageSize,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _reports.addAll(page.reports);
        _hasMore = page.hasMore;
        _nextOffset = page.reports.length;
        _loadingInitial = false;
      });
    } on DashboardSessionException catch (error) {
      debugPrint('Historial sin sesión válida: $error');
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loadingInitial = false;
        _sessionExpired = true;
      });
    } catch (error) {
      debugPrint('Error cargando historial: $error');
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loadingInitial = false;
        _hasError = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingInitial || _loadingMore || !_hasMore || _hasError) return;
    final generation = _requestGeneration;
    setState(() => _loadingMore = true);

    try {
      final page = await _historyRepository.cargarHistorial(
        filter: _filter,
        offset: _nextOffset,
        pageSize: _pageSize,
      );
      if (!mounted || generation != _requestGeneration) return;

      final knownIds = _reports
          .map((report) => report.bache.id)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      final newReports = page.reports.where((report) {
        final id = report.bache.id;
        return id == null || id.isEmpty || knownIds.add(id);
      });

      setState(() {
        _reports.addAll(newReports);
        _hasMore = page.hasMore;
        _nextOffset += page.reports.length;
        _loadingMore = false;
      });
    } on DashboardSessionException catch (error) {
      debugPrint('Sesión expirada cargando más historial: $error');
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loadingMore = false;
        _sessionExpired = true;
        _reports.clear();
      });
    } catch (error) {
      debugPrint('Error cargando más historial: $error');
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudieron cargar más reportes. Reintenta.'),
        ),
      );
    }
  }

  void _changeFilter(HistorySeverityFilter filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    unawaited(_reload());
  }

  Future<void> _openReport() async {
    final onReportRequested = widget.onReportRequested;
    if (onReportRequested != null) {
      onReportRequested();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportScreen()),
    );
    if (mounted) await _reload();
  }

  void _goToLogin() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} · '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  String _location(DashboardReport report) {
    if (!report.hasLocation) return 'Ubicación no disponible';
    return '${report.bache.latitud.toStringAsFixed(5)}, '
        '${report.bache.longitud.toStringAsFixed(5)}';
  }

  bool _hasMetricMeasurement(DashboardReport report) {
    return report.bache.tieneMedicionMetrica;
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'Leve':
        return Colors.green.shade700;
      case 'Moderado':
        return Colors.orange.shade800;
      case 'Severo':
        return Colors.red.shade700;
      default:
        return Colors.blueGrey.shade700;
    }
  }

  String _severityLabel(String severity) =>
      severity.trim().isEmpty ? 'No disponible' : severity;

  Widget _photoThumbnail(DashboardReport report) {
    final url = report.bache.fotoUrl.trim();
    if (url.isEmpty) {
      return Container(
        key: const Key('history_no_photo'),
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported_outlined, color: Colors.grey),
            SizedBox(height: 4),
            Text('Sin foto', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Image.network(
        historyThumbnailUrl(url, width: 240),
        width: 92,
        height: 92,
        fit: BoxFit.cover,
        cacheWidth: 240,
        errorBuilder: (_, __, ___) => Container(
          width: 92,
          height: 92,
          color: Colors.grey.shade100,
          alignment: Alignment.center,
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image_outlined, color: Colors.grey),
              SizedBox(height: 4),
              Text('Foto no disponible',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reportCard(DashboardReport report) {
    final bache = report.bache;
    final hasMetric = _hasMetricMeasurement(report);
    final severityColor = _severityColor(bache.severidad);

    return Card(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: severityColor.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        key: ValueKey('history_report_${bache.id}'),
        borderRadius: BorderRadius.circular(17),
        onTap: () => _showDetails(report),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _photoThumbnail(report),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: severityColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _severityLabel(bache.severidad),
                            style: TextStyle(
                              color: severityColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatDate(bache.fecha),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _location(report),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 22),
              Text(
                'Bounding box: ${bache.anchoPx.toStringAsFixed(0)} × '
                '${bache.altoPx.toStringAsFixed(0)} px',
              ),
              const SizedBox(height: 5),
              Text('Método: ${bache.etiquetaMetodoMedicion}'),
              const SizedBox(height: 5),
              Text(
                hasMetric
                    ? 'Ancho/alto estimados: '
                        '${bache.anchoCm!.toStringAsFixed(1)} × '
                        '${bache.altoCm!.toStringAsFixed(1)} cm\n'
                        'Área estimada del rectángulo envolvente: '
                        '${bache.areaCm2!.toStringAsFixed(1)} cm²'
                    : 'Medición no disponible',
                style: TextStyle(
                  color: hasMetric ? Colors.black87 : Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                bache.confianza == null
                    ? 'Confianza IA: No disponible'
                    : 'Confianza IA: '
                        '${(bache.confianza! * 100).toStringAsFixed(1)}%',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(DashboardReport report) {
    final bache = report.bache;
    final hasMetric = _hasMetricMeasurement(report);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.9,
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Detalle del reporte',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                if (bache.fotoUrl.trim().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      historyThumbnailUrl(bache.fotoUrl, width: 720),
                      width: double.infinity,
                      height: 210,
                      fit: BoxFit.cover,
                      cacheWidth: 720,
                      errorBuilder: (_, __, ___) => Container(
                        height: 120,
                        color: Colors.grey.shade100,
                        alignment: Alignment.center,
                        child: const Text('Foto no disponible'),
                      ),
                    ),
                  )
                else
                  const _DetailLine(label: 'Fotografía', value: 'Sin foto'),
                const SizedBox(height: 14),
                _DetailLine(
                  label: 'ID',
                  value: bache.id?.trim().isNotEmpty == true
                      ? bache.id!
                      : 'No disponible',
                ),
                _DetailLine(
                    label: 'Fecha y hora', value: _formatDate(bache.fecha)),
                _DetailLine(
                  label: 'Severidad',
                  value: _severityLabel(bache.severidad),
                ),
                _DetailLine(label: 'Ubicación', value: _location(report)),
                _DetailLine(
                  label: 'Confianza IA',
                  value: bache.confianza == null
                      ? 'No disponible'
                      : '${(bache.confianza! * 100).toStringAsFixed(1)}%',
                ),
                _DetailLine(
                  label: 'Método de medición',
                  value: bache.etiquetaMetodoMedicion,
                ),
                _DetailLine(
                  label: 'Ancho en imagen',
                  value: '${bache.anchoPx.toStringAsFixed(1)} px',
                ),
                _DetailLine(
                  label: 'Alto en imagen',
                  value: '${bache.altoPx.toStringAsFixed(1)} px',
                ),
                if (hasMetric) ...[
                  _DetailLine(
                    label: 'Ancho estimado',
                    value: '${bache.anchoCm!.toStringAsFixed(1)} cm',
                  ),
                  _DetailLine(
                    label: 'Alto estimado',
                    value: '${bache.altoCm!.toStringAsFixed(1)} cm',
                  ),
                  _DetailLine(
                    label: 'Área estimada del rectángulo envolvente',
                    value: '${bache.areaCm2!.toStringAsFixed(1)} cm²',
                  ),
                  const _DetailLine(
                    label: 'Estado de medición',
                    value:
                        'Dimensiones estimadas del bounding box proyectado mediante referencia métrica. No representa la superficie irregular real del bache.',
                  ),
                ] else
                  const _DetailLine(
                    label: 'Estado de medición',
                    value: 'Medición no disponible',
                  ),
                if (report.hasLocation) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        unawaited(
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MapScreen(initialBache: bache),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Ver en mapa'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    final filtered = _filter != HistorySeverityFilter.all;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 90),
        Icon(
          filtered ? Icons.filter_alt_off_outlined : Icons.inbox_outlined,
          color: Colors.orange,
          size: 58,
        ),
        const SizedBox(height: 16),
        Text(
          filtered
              ? 'No hay reportes con este filtro'
              : 'No tienes reportes registrados todavía',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          filtered
              ? 'Prueba con otra severidad o muestra todos los reportes.'
              : 'Inicia una detección para registrar tu primer bache.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: filtered
              ? () => _changeFilter(HistorySeverityFilter.all)
              : () => unawaited(_openReport()),
          icon: Icon(filtered ? Icons.filter_alt_off : Icons.camera_alt),
          label: Text(filtered ? 'Mostrar todos' : 'Reportar bache'),
        ),
      ],
    );
  }

  Widget _stateMessage({
    required IconData icon,
    required String title,
    required String message,
    required String action,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.orange, size: 58),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onPressed, child: Text(action)),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_loadingInitial) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.orange),
      );
    }
    if (_sessionExpired) {
      return _stateMessage(
        icon: Icons.lock_outline,
        title: 'Sesión expirada',
        message: 'Inicia sesión nuevamente para consultar tu historial.',
        action: 'Ir al inicio de sesión',
        onPressed: _goToLogin,
      );
    }
    if (_hasError) {
      return _stateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo cargar el historial',
        message: 'Comprueba tu conexión y vuelve a intentarlo.',
        action: 'Reintentar',
        onPressed: () => unawaited(_reload()),
      );
    }
    if (_reports.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        color: Colors.orange,
        child: _emptyState(),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      color: Colors.orange,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        itemCount: _reports.length + 1,
        itemBuilder: (context, index) {
          if (index < _reports.length) return _reportCard(_reports[index]);
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: CircularProgressIndicator(color: Colors.orange),
              ),
            );
          }
          if (_hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: OutlinedButton(
                key: const Key('history_load_more'),
                onPressed: () => unawaited(_loadMore()),
                child: const Text('Cargar más'),
              ),
            );
          }
          return const Padding(
            padding: EdgeInsets.all(18),
            child: Center(
              child: Text(
                'No hay más reportes',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _requestGeneration++;
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Historial'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar historial',
            onPressed: _loadingInitial ? null : () => unawaited(_reload()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: HistorySeverityFilter.values
                    .map(
                      (filter) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          key: ValueKey('history_filter_${filter.name}'),
                          selected: _filter == filter,
                          label: Text(filter.label),
                          selectedColor: Colors.orange.shade100,
                          checkmarkColor: Colors.orange.shade900,
                          onSelected: (_) => _changeFilter(filter),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
          Expanded(child: _content()),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}
