import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bache_model.dart';

List<String> mapMeasurementLines(Bache bache) {
  final lines = <String>[
    'Bounding box: ${bache.anchoPx.toStringAsFixed(0)} × '
        '${bache.altoPx.toStringAsFixed(0)} px',
    'Método: ${bache.etiquetaMetodoMedicion}',
  ];
  if (bache.tieneMedicionMetrica) {
    lines.addAll([
      'Ancho aproximado: ${bache.anchoCm!.toStringAsFixed(2)} cm',
      'Alto aproximado: ${bache.altoCm!.toStringAsFixed(2)} cm',
      'Área aproximada del rectángulo envolvente: '
          '${bache.areaCm2!.toStringAsFixed(1)} cm²',
    ]);
  } else {
    lines.add(bache.etiquetaMetodoMedicion);
  }
  return lines;
}

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.initialBache,
  });

  final Bache? initialBache;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _db = Supabase.instance.client;
  List<Bache> _baches = [];
  bool _cargando = true;
  final MapController _mapController = MapController();

  // Centro del mapa — Loja, Ecuador
  static const LatLng _centroInicial = LatLng(-3.9931, -79.2042);

  LatLng get _mapInitialCenter {
    final bache = widget.initialBache;
    if (bache == null) return _centroInicial;
    return LatLng(bache.latitud, bache.longitud);
  }

  double get _mapInitialZoom => widget.initialBache == null ? 13 : 17;

  @override
  void initState() {
    super.initState();
    final initialBache = widget.initialBache;
    if (initialBache != null) {
      _baches = [initialBache];
    }
    _cargarBaches();
  }

  Future<void> _cargarBaches() async {
    setState(() => _cargando = true);
    try {
      final response =
          await _db.from('baches').select().order('fecha', ascending: false);

      if (!mounted) return;
      final loadedBaches = (response as List)
          .map((row) => Bache.fromMap(row, row['id'].toString()))
          .toList();
      final initialBache = widget.initialBache;
      if (initialBache != null &&
          !loadedBaches.any((bache) => bache.id == initialBache.id)) {
        loadedBaches.add(initialBache);
      }

      setState(() {
        _baches = loadedBaches;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar baches: $e')),
      );
    }
  }

  Color _colorSeveridad(String severidad) {
    switch (severidad) {
      case 'Leve':
        return Colors.green;
      case 'Moderado':
        return Colors.orange;
      case 'Severo':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _iconoSeveridad(String severidad) {
    switch (severidad) {
      case 'Leve':
        return Icons.warning_amber;
      case 'Moderado':
        return Icons.warning;
      case 'Severo':
        return Icons.dangerous;
      default:
        return Icons.help_outline;
    }
  }

  Widget _detalle({
    required IconData icon,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  void _mostrarDetalleBache(Bache bache) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.circle,
                      color: _colorSeveridad(bache.severidad), size: 14),
                  const SizedBox(width: 8),
                  Text(
                    'Bache ${bache.severidad}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Divider(height: 20),
              if (bache.fotoUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    bache.fotoUrl,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.circle_outlined,
                    color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Text('Forma: ${bache.forma}'),
              ]),
              ...mapMeasurementLines(bache).map(
                (line) => _detalle(icon: Icons.straighten, text: line),
              ),
              _detalle(
                icon: Icons.analytics_outlined,
                text: bache.confianza == null
                    ? 'Confianza IA: No disponible'
                    : 'Confianza IA: '
                        '${(bache.confianza! * 100).toStringAsFixed(1)} %',
              ),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.location_on, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Text(
                    '${bache.latitud.toStringAsFixed(5)}, ${bache.longitud.toStringAsFixed(5)}'),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.person, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Text(bache.usuarioEmail),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.calendar_today,
                    color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Text(
                    '${bache.fecha.day}/${bache.fecha.month}/${bache.fecha.year}'),
              ]),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _cargando ? 'Cargando mapa...' : 'Mapa — ${_baches.length} baches'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarBaches,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _mapInitialCenter,
              initialZoom: _mapInitialZoom,
            ),
            children: [
              // Capa base OpenStreetMap
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.spotholeApp',
              ),
              // Marcadores de baches
              MarkerLayer(
                markers: _baches.map((bache) {
                  return Marker(
                    point: LatLng(bache.latitud, bache.longitud),
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => _mostrarDetalleBache(bache),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _colorSeveridad(bache.severidad),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          _iconoSeveridad(bache.severidad),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // Leyenda
          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Severidad',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.circle, color: Colors.green, size: 14),
                    SizedBox(width: 6),
                    Text('Leve'),
                  ]),
                  SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.circle, color: Colors.orange, size: 14),
                    SizedBox(width: 6),
                    Text('Moderado'),
                  ]),
                  SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.circle, color: Colors.red, size: 14),
                    SizedBox(width: 6),
                    Text('Severo'),
                  ]),
                ],
              ),
            ),
          ),

          // Loading overlay
          if (_cargando)
            const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            ),
        ],
      ),

      // Botón para centrar en ubicación inicial
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        onPressed: () {
          _mapController.move(_mapInitialCenter, _mapInitialZoom);
        },
        child: const Icon(Icons.my_location),
      ),
    );
  }
}
