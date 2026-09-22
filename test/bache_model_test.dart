import 'package:flutter_test/flutter_test.dart';
import 'package:spothole_app/models/bache_model.dart';

void main() {
  group('Bache', () {
    test('conserva métricas y confianza nulas al serializar', () {
      final bache = Bache(
        latitud: -0.2,
        longitud: -78.5,
        fotoUrl: '',
        forma: 'Circular',
        anchoPx: 120,
        altoPx: 80,
        severidad: 'Leve',
        fecha: DateTime.parse('2026-09-04T10:00:00-05:00'),
        usuarioEmail: 'persona@example.com',
      );

      final map = bache.toMap();

      expect(map['ancho_cm'], isNull);
      expect(map['alto_cm'], isNull);
      expect(map['area_cm2'], isNull);
      expect(map['altura_captura'], isNull);
      expect(map['metodo_medicion'], isNull);
      expect(map['confianza'], isNull);
      expect(map['fecha'], '2026-09-04T15:00:00.000Z');
    });

    test('tolera registros antiguos, nulos y números como texto', () {
      final bache = Bache.fromMap({
        'latitud': '-0.201',
        'longitud': -78,
        'ancho_px': 123,
        'alto_px': '45.5',
        'ancho_cm': null,
        'alto_cm': '12.25',
        'area_cm2': null,
        'altura_captura': null,
        'confianza': '0.87',
        'fecha': '2026-09-04T15:00:00Z',
      }, 'registro-real');

      expect(bache.id, 'registro-real');
      expect(bache.latitud, -0.201);
      expect(bache.longitud, -78.0);
      expect(bache.anchoPx, 123.0);
      expect(bache.altoPx, 45.5);
      expect(bache.anchoCm, isNull);
      expect(bache.altoCm, 12.25);
      expect(bache.areaCm2, isNull);
      expect(bache.alturaCaptura, isNull);
      expect(bache.metodoMedicion, isNull);
      expect(bache.metodoMedicionEfectivo, 'historico');
      expect(bache.confianza, 0.87);
      expect(bache.fecha.isUtc, isTrue);
      expect(bache.fotoUrl, '');
      expect(bache.usuarioEmail, '');
    });

    for (final metodo in const [
      'aruco',
      'arcore_depth',
      'sin_medicion',
    ]) {
      test('serializa y recupera metodo_medicion=$metodo', () {
        final original = Bache(
          latitud: -0.2,
          longitud: -78.5,
          fotoUrl: '',
          forma: 'Circular',
          anchoPx: 120,
          altoPx: 80,
          anchoCm: metodo == 'sin_medicion' ? null : 24,
          altoCm: metodo == 'sin_medicion' ? null : 18,
          areaCm2: metodo == 'sin_medicion' ? null : 432,
          metodoMedicion: metodo,
          severidad: metodo == 'sin_medicion' ? 'No determinada' : 'Moderado',
          fecha: DateTime.utc(2026, 9, 6),
          usuarioEmail: 'persona@example.com',
        );

        final map = original.toMap();
        final restored = Bache.fromMap(map, 'id');

        expect(map['metodo_medicion'], metodo);
        expect(restored.metodoMedicion, metodo);
        expect(restored.metodoMedicionEfectivo, metodo);
      });
    }

    test('calcula severidad en los límites métricos existentes', () {
      expect(Bache.calcularSeveridad(0), 'Leve');
      expect(Bache.calcularSeveridad(199.99), 'Leve');
      expect(Bache.calcularSeveridad(200), 'Moderado');
      expect(Bache.calcularSeveridad(899.99), 'Moderado');
      expect(Bache.calcularSeveridad(900), 'Severo');
      expect(Bache.calcularSeveridad(1966.8), 'Severo');
    });

    test('solo reconoce métricas de métodos actuales con valores válidos', () {
      Bache measured(String? method, {double? area = 432}) => Bache(
            latitud: -0.2,
            longitud: -78.5,
            fotoUrl: '',
            forma: 'Circular',
            anchoPx: 120,
            altoPx: 80,
            anchoCm: 24,
            altoCm: 18,
            areaCm2: area,
            metodoMedicion: method,
            severidad: 'Moderado',
            fecha: DateTime.utc(2026, 9, 6),
            usuarioEmail: 'persona@example.com',
          );

      expect(measured(Bache.metodoAruco).tieneMedicionMetrica, isTrue);
      expect(measured(Bache.metodoArCoreDepth).tieneMedicionMetrica, isTrue);
      expect(measured(Bache.metodoSinMedicion).tieneMedicionMetrica, isFalse);
      expect(measured(null).tieneMedicionMetrica, isFalse);
      expect(
        measured(Bache.metodoArCoreDepth, area: null).tieneMedicionMetrica,
        isFalse,
      );
    });
  });
}
