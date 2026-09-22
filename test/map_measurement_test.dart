import 'package:flutter_test/flutter_test.dart';
import 'package:spothole_app/models/bache_model.dart';
import 'package:spothole_app/screens/map_screen.dart';

void main() {
  Bache report(String method, {bool measured = true}) => Bache(
        id: 'id',
        latitud: -3.99,
        longitud: -79.2,
        fotoUrl: '',
        forma: 'Circular',
        anchoPx: 137,
        altoPx: 134,
        anchoCm: measured ? 35.55 : null,
        altoCm: measured ? 55.33 : null,
        areaCm2: measured ? 1966.8 : null,
        metodoMedicion: method,
        severidad: measured ? 'Severo' : 'No determinada',
        fecha: DateTime.utc(2026, 9, 6),
        usuarioEmail: 'persona@example.com',
        confianza: 0.852,
      );

  test('mapa presenta píxeles y centímetros de ARCore', () {
    final lines = mapMeasurementLines(report(Bache.metodoArCoreDepth));

    expect(lines, contains('Bounding box: 137 × 134 px'));
    expect(
      lines,
      contains(
        'Método: Medición automática estimada mediante ARCore Depth',
      ),
    );
    expect(lines, contains('Ancho aproximado: 35.55 cm'));
    expect(lines, contains('Alto aproximado: 55.33 cm'));
    expect(
      lines,
      contains('Área aproximada del rectángulo envolvente: 1966.8 cm²'),
    );
  });

  test('mapa no inventa centímetros sin medición', () {
    final lines = mapMeasurementLines(
      report(Bache.metodoSinMedicion, measured: false),
    );

    expect(lines, contains('Medición métrica no disponible'));
    expect(lines.any((line) => line.contains('cm')), isFalse);
  });
}
