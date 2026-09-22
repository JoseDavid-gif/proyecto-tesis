import 'dart:async';

import 'package:flutter/material.dart';

import '../models/dashboard_model.dart';
import '../services/supabase_service.dart';
import 'history_screen.dart';
import 'login_screen.dart';
import 'report_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.dashboardRepository,
    this.historyRepository,
    this.onSelectSection,
  });

  final DashboardRepository? dashboardRepository;
  final HistoryRepository? historyRepository;
  final ValueChanged<int>? onSelectSection;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DashboardRepository _dashboardRepository;

  DashboardOverview? _overview;
  bool _loading = true;
  bool _sessionExpired = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _dashboardRepository = widget.dashboardRepository ?? SupabaseService();
    unawaited(_loadDashboard());
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _hasError = false;
        _sessionExpired = false;
      });
    }

    try {
      final overview = await _dashboardRepository.cargarDashboard();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } on DashboardSessionException catch (error) {
      debugPrint('Dashboard sin sesión válida: $error');
      if (!mounted) return;
      setState(() {
        _overview = null;
        _loading = false;
        _sessionExpired = true;
      });
    } catch (error) {
      debugPrint('Error cargando dashboard: $error');
      if (!mounted) return;
      setState(() {
        _overview = null;
        _loading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    if (mounted) {
      await _loadDashboard();
    }
  }

  void _openSection(int index, Widget fallback) {
    final selectSection = widget.onSelectSection;
    if (selectSection != null) {
      selectSection(index);
      return;
    }
    unawaited(_openScreen(fallback));
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
    return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  String _formatLocation(DashboardReport report) {
    if (!report.hasLocation) return 'Ubicación no disponible';
    return '${report.bache.latitud.toStringAsFixed(5)}, '
        '${report.bache.longitud.toStringAsFixed(5)}';
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'Leve':
        return Colors.green;
      case 'Moderado':
        return Colors.orange;
      case 'Severo':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _summaryCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _quickAccess({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.orange, size: 30),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _latestReportCard(DashboardReport report) {
    final bache = report.bache;
    final hasMetricMeasurement = bache.tieneMedicionMetrica;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Último reporte',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color:
                      _severityColor(bache.severidad).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  bache.severidad.isEmpty ? 'Sin severidad' : bache.severidad,
                  style: TextStyle(
                    color: _severityColor(bache.severidad),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (bache.fotoUrl.trim().isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                bache.fotoUrl,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                cacheWidth: 720,
                errorBuilder: (_, __, ___) => Container(
                  height: 90,
                  color: Colors.grey.shade100,
                  alignment: Alignment.center,
                  child: const Text('Foto no disponible'),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else
            const _InfoLine(icon: Icons.hide_image_outlined, text: 'Sin foto'),
          _InfoLine(
            icon: Icons.calendar_today_outlined,
            text: _formatDate(bache.fecha),
          ),
          _InfoLine(
            icon: Icons.location_on_outlined,
            text: _formatLocation(report),
          ),
          _InfoLine(
            icon: Icons.analytics_outlined,
            text: bache.confianza == null
                ? 'Confianza no disponible'
                : 'Confianza: ${(bache.confianza! * 100).toStringAsFixed(1)}%',
          ),
          _InfoLine(
            icon: Icons.straighten,
            text: hasMetricMeasurement
                ? '${bache.anchoCm!.toStringAsFixed(1)} × '
                    '${bache.altoCm!.toStringAsFixed(1)} cm · '
                    'Área bbox ${bache.areaCm2!.toStringAsFixed(1)} cm²'
                : 'Medición no disponible',
          ),
        ],
      ),
    );
  }

  Widget _recentActivity(DashboardReport report) {
    final bache = report.bache;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _severityColor(bache.severidad).withValues(
              alpha: 0.12,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: _severityColor(bache.severidad),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bache.severidad.isEmpty ? 'Sin severidad' : bache.severidad,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDate(bache.fecha),
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                Text(
                  _formatLocation(report),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
          Tooltip(
            message: bache.fotoUrl.trim().isEmpty ? 'Sin foto' : 'Con foto',
            child: Icon(
              bache.fotoUrl.trim().isEmpty
                  ? Icons.image_not_supported_outlined
                  : Icons.image_outlined,
              color: bache.fotoUrl.trim().isEmpty ? Colors.grey : Colors.orange,
            ),
          ),
        ],
      ),
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
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onPressed, child: Text(action)),
          ],
        ),
      ),
    );
  }

  Widget _dashboardBody(DashboardOverview overview) {
    return RefreshIndicator(
      onRefresh: _loadDashboard,
      color: Colors.orange,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
        children: [
          Text(
            overview.greeting,
            key: const Key('dashboard_greeting'),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          const Text(
            'Este es el resumen de tus reportes en Spothole.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _summaryCard(
                icon: Icons.assignment_outlined,
                value: '${overview.totalReports}',
                label: 'Total de reportes',
                color: Colors.orange,
              ),
              const SizedBox(width: 12),
              _summaryCard(
                icon: Icons.straighten,
                value: '${overview.reportsWithMetricMeasurement}',
                label: 'Con medición disponible',
                color: Colors.teal,
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('start_detection_button'),
              onPressed: () => _openSection(1, const ReportScreen()),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('INICIAR DETECCIÓN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 17),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          const SizedBox(height: 25),
          const Text(
            'Accesos rápidos',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.35,
            children: [
              _quickAccess(
                icon: Icons.add_a_photo_outlined,
                label: 'Reportar Bache',
                onTap: () => _openSection(1, const ReportScreen()),
              ),
              _quickAccess(
                icon: Icons.map_outlined,
                label: 'Mapa',
                onTap: () => _openSection(2, const MapScreen()),
              ),
              _quickAccess(
                icon: Icons.history,
                label: 'Historial',
                onTap: () => _openSection(
                  3,
                  HistoryScreen(
                    historyRepository: widget.historyRepository,
                  ),
                ),
              ),
              _quickAccess(
                icon: Icons.person_outline,
                label: 'Perfil',
                onTap: () => _openSection(4, const ProfileScreen()),
              ),
            ],
          ),
          const SizedBox(height: 25),
          if (overview.latestReport != null)
            _latestReportCard(overview.latestReport!),
          if (overview.latestReport == null) ...[
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                children: [
                  Icon(Icons.inbox_outlined, color: Colors.orange, size: 44),
                  SizedBox(height: 10),
                  Text(
                    'Aún no tienes reportes',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Inicia una detección para crear tu primer reporte.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
          if (overview.recentReports.isNotEmpty) ...[
            const SizedBox(height: 25),
            const Text(
              'Actividad reciente',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...overview.recentReports.map(_recentActivity),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Spothole'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : () => unawaited(_loadDashboard()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            )
          : _sessionExpired
              ? _stateMessage(
                  icon: Icons.lock_outline,
                  title: 'Sesión expirada',
                  message: 'Inicia sesión nuevamente para ver tus reportes.',
                  action: 'Ir al inicio de sesión',
                  onPressed: _goToLogin,
                )
              : _hasError || _overview == null
                  ? _stateMessage(
                      icon: Icons.cloud_off_outlined,
                      title: 'No se pudo cargar el resumen',
                      message: 'Comprueba tu conexión y vuelve a intentarlo.',
                      action: 'Reintentar',
                      onPressed: () => unawaited(_loadDashboard()),
                    )
                  : _dashboardBody(_overview!),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.orange, size: 19),
          const SizedBox(width: 9),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
