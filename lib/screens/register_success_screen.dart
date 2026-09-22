import 'dart:async';

import 'package:flutter/material.dart';

import '../models/bache_model.dart';
import '../models/history_model.dart';
import 'map_screen.dart';
import 'report_screen.dart';

typedef SuccessMapBuilder = Widget Function(Bache bache);
typedef NewReportBuilder = Widget Function();

class RegisterSuccessScreen extends StatelessWidget {
  RegisterSuccessScreen({
    super.key,
    required this.bache,
    this.mapBuilder,
    this.newReportBuilder,
    this.onHome,
    this.onNewReport,
  }) {
    if (bache.id == null || bache.id!.trim().isEmpty) {
      throw ArgumentError.value(
        bache.id,
        'bache.id',
        'La confirmación requiere el ID real retornado por Supabase.',
      );
    }
  }

  final Bache bache;
  final SuccessMapBuilder? mapBuilder;
  final NewReportBuilder? newReportBuilder;
  final VoidCallback? onHome;
  final VoidCallback? onNewReport;

  bool get _hasValidLocation =>
      bache.latitud.isFinite &&
      bache.longitud.isFinite &&
      bache.latitud >= -90 &&
      bache.latitud <= 90 &&
      bache.longitud >= -180 &&
      bache.longitud <= 180;

  bool get _hasMetricMeasurement => bache.tieneMedicionMetrica;

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} · '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  Color _severityColor() {
    switch (bache.severidad) {
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

  void _openMap(BuildContext context) {
    if (!_hasValidLocation) return;
    final destination =
        mapBuilder?.call(bache) ?? MapScreen(initialBache: bache);
    unawaited(
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => destination),
      ),
    );
  }

  void _startNewReport(BuildContext context) {
    final callback = onNewReport;
    if (callback != null) {
      callback();
      return;
    }
    final destination = newReportBuilder?.call() ?? const ReportScreen();
    unawaited(
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => destination),
      ),
    );
  }

  void _goHome(BuildContext context) {
    final callback = onHome;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  Widget _photo() {
    final photoUrl = bache.fotoUrl.trim();
    if (photoUrl.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(17),
        ),
        child: const Column(
          children: [
            Icon(Icons.image_not_supported_outlined, color: Colors.grey),
            SizedBox(height: 7),
            Text('Reporte registrado sin fotografía'),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: Image.network(
        historyThumbnailUrl(photoUrl, width: 720),
        width: double.infinity,
        height: 210,
        fit: BoxFit.cover,
        cacheWidth: 720,
        errorBuilder: (_, __, ___) => Container(
          width: double.infinity,
          height: 130,
          color: Colors.grey.shade100,
          alignment: Alignment.center,
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image_outlined, color: Colors.grey, size: 32),
              SizedBox(height: 7),
              Text('Fotografía no disponible'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary() {
    final severityColor = _severityColor();
    final severity =
        bache.severidad.trim().isEmpty ? 'No disponible' : bache.severidad;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 5),
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
                  'Resumen del reporte',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  severity,
                  style: TextStyle(
                    color: severityColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SuccessInfoLine(label: 'ID', value: bache.id!),
          _SuccessInfoLine(
            label: 'Ubicación',
            value: _hasValidLocation
                ? '${bache.latitud.toStringAsFixed(6)}, '
                    '${bache.longitud.toStringAsFixed(6)}'
                : 'Ubicación no disponible',
          ),
          _SuccessInfoLine(
              label: 'Fecha y hora', value: _formatDate(bache.fecha)),
          _SuccessInfoLine(
            label: 'Confianza IA',
            value: bache.confianza == null
                ? 'Confianza no disponible'
                : '${(bache.confianza! * 100).toStringAsFixed(1)} %',
          ),
          _SuccessInfoLine(
            label: 'Bounding box',
            value: '${bache.anchoPx.toStringAsFixed(1)} × '
                '${bache.altoPx.toStringAsFixed(1)} px',
          ),
          if (_hasMetricMeasurement) ...[
            _SuccessInfoLine(
              label: 'Método',
              value: bache.etiquetaMetodoMedicion,
            ),
            _SuccessInfoLine(
              label: 'Ancho estimado',
              value: '${bache.anchoCm!.toStringAsFixed(1)} cm',
            ),
            _SuccessInfoLine(
              label: 'Alto estimado',
              value: '${bache.altoCm!.toStringAsFixed(1)} cm',
            ),
            _SuccessInfoLine(
              label: 'Área estimada del rectángulo envolvente',
              value: '${bache.areaCm2!.toStringAsFixed(1)} cm²',
            ),
          ] else
            const _SuccessInfoLine(
              label: 'Medición',
              value: 'Medición automática no disponible para esta captura',
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Registro completado'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Ir a Inicio',
            onPressed: () => _goHome(context),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 30),
          children: [
            CircleAvatar(
              radius: 43,
              backgroundColor: Colors.green.shade50,
              child: Icon(
                Icons.check_circle_rounded,
                color: Colors.green.shade700,
                size: 68,
              ),
            ),
            const SizedBox(height: 17),
            const Text(
              'Bache registrado correctamente',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            const Text(
              'Supabase confirmó el registro.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),
            _photo(),
            const SizedBox(height: 18),
            _summary(),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              key: const Key('success_view_map'),
              onPressed: _hasValidLocation ? () => _openMap(context) : null,
              icon: const Icon(Icons.map_outlined),
              label: const Text('VER EN MAPA'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              key: const Key('success_new_report'),
              onPressed: () => _startNewReport(context),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('NUEVO REPORTE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessInfoLine extends StatelessWidget {
  const _SuccessInfoLine({required this.label, required this.value});

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
