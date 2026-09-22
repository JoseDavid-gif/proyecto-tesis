class Bache {
  static const String metodoAruco = 'aruco';
  static const String metodoArCoreDepth = 'arcore_depth';
  static const String metodoSinMedicion = 'sin_medicion';
  static const String metodoHistorico = 'historico';

  final String? id;
  final double latitud;
  final double longitud;
  final String fotoUrl;
  final String forma;
  final double anchoPx;
  final double altoPx;
  final double? anchoCm;
  final double? altoCm;
  final double? areaCm2;
  final double? alturaCaptura;
  final String? metodoMedicion;
  final String severidad;
  final DateTime fecha;
  final String usuarioEmail;
  final double? confianza;

  Bache({
    this.id,
    required this.latitud,
    required this.longitud,
    required this.fotoUrl,
    required this.forma,
    required this.anchoPx,
    required this.altoPx,
    this.anchoCm,
    this.altoCm,
    this.areaCm2,
    this.alturaCaptura,
    this.metodoMedicion,
    required this.severidad,
    required this.fecha,
    required this.usuarioEmail,
    this.confianza,
  });

  static String calcularForma(double ancho, double alto) {
    final ratio = ancho / alto;
    if (ratio >= 0.8 && ratio <= 1.2) return 'Circular';
    if (ratio > 1.2) return 'Alargado horizontal';
    return 'Alargado vertical';
  }

  static String calcularSeveridad(double areaCm2) {
    if (areaCm2 < 200) return 'Leve';
    if (areaCm2 < 900) return 'Moderado';
    return 'Severo';
  }

  Map<String, dynamic> toMap() {
    return {
      'usuario_email': usuarioEmail,
      'latitud': latitud,
      'longitud': longitud,
      'forma': forma,
      'ancho_px': anchoPx,
      'alto_px': altoPx,
      'ancho_cm': anchoCm,
      'alto_cm': altoCm,
      'area_cm2': areaCm2,
      'altura_captura': alturaCaptura,
      'metodo_medicion': metodoMedicion,
      'severidad': severidad,
      'foto_url': fotoUrl,
      'confianza': confianza,
      'fecha': fecha.toUtc().toIso8601String(),
      // NO incluir 'id' ni 'ubicacion' — Supabase los genera solos
    };
  }

  static double _toDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double? _toNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is DateTime) return value.toUtc();
    return (DateTime.tryParse(value?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
        .toUtc();
  }

  factory Bache.fromMap(Map<String, dynamic> map, String id) {
    return Bache(
      id: id,
      latitud: _toDouble(map['latitud']),
      longitud: _toDouble(map['longitud']),
      fotoUrl: map['foto_url']?.toString() ?? '',
      forma: map['forma']?.toString() ?? '',
      anchoPx: _toDouble(map['ancho_px']),
      altoPx: _toDouble(map['alto_px']),
      anchoCm: _toNullableDouble(map['ancho_cm']),
      altoCm: _toNullableDouble(map['alto_cm']),
      areaCm2: _toNullableDouble(map['area_cm2']),
      alturaCaptura: _toNullableDouble(map['altura_captura']),
      metodoMedicion: map['metodo_medicion']?.toString(),
      severidad: map['severidad']?.toString() ?? '',
      fecha: _toDateTime(map['fecha']),
      usuarioEmail: map['usuario_email']?.toString() ?? '',
      confianza: _toNullableDouble(map['confianza']),
    );
  }

  String get metodoMedicionEfectivo => metodoMedicion ?? metodoHistorico;

  bool get tieneMedicionMetrica {
    final metodo = metodoMedicionEfectivo;
    return (metodo == metodoAruco || metodo == metodoArCoreDepth) &&
        anchoCm != null &&
        anchoCm!.isFinite &&
        anchoCm! > 0 &&
        altoCm != null &&
        altoCm!.isFinite &&
        altoCm! > 0 &&
        areaCm2 != null &&
        areaCm2!.isFinite &&
        areaCm2! > 0;
  }

  String get etiquetaMetodoMedicion {
    return switch (metodoMedicionEfectivo) {
      metodoAruco => 'Medición con referencia métrica',
      metodoArCoreDepth => 'Medición automática estimada mediante ARCore Depth',
      metodoSinMedicion => 'Medición métrica no disponible',
      _ => 'Medición histórica (método no registrado)',
    };
  }
}
