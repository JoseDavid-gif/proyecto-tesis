import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spothole_app/models/bache_model.dart';
import 'package:spothole_app/screens/register_success_screen.dart';

void main() {
  Bache bache({
    String? id = 'supabase-real-id',
    String photoUrl = '',
    String severity = 'Leve',
    double latitude = -3.9931,
    double longitude = -79.2042,
    bool withMetric = false,
    double? confidence = 0.874,
  }) =>
      Bache(
        id: id,
        latitud: latitude,
        longitud: longitude,
        fotoUrl: photoUrl,
        forma: 'Circular',
        anchoPx: 120,
        altoPx: 90,
        anchoCm: withMetric ? 24 : null,
        altoCm: withMetric ? 18 : null,
        areaCm2: withMetric ? 432 : null,
        alturaCaptura: null,
        metodoMedicion:
            withMetric ? Bache.metodoArCoreDepth : Bache.metodoSinMedicion,
        severidad: severity,
        fecha: DateTime(2026, 9, 5, 14, 7),
        usuarioEmail: 'persona@example.com',
        confianza: confidence,
      );

  Future<void> pumpSuccess(
    WidgetTester tester,
    Bache value, {
    SuccessMapBuilder? mapBuilder,
    NewReportBuilder? newReportBuilder,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RegisterSuccessScreen(
          bache: value,
          mapBuilder: mapBuilder,
          newReportBuilder: newReportBuilder,
        ),
      ),
    );
  }

  testWidgets('muestra el ID real y confirmación sin fotografía',
      (tester) async {
    await pumpSuccess(tester, bache());

    expect(find.text('Bache registrado correctamente'), findsOneWidget);
    expect(find.text('supabase-real-id'), findsOneWidget);
    expect(find.text('Reporte registrado sin fotografía'), findsOneWidget);
    expect(find.text('05/09/2026 · 14:07'), findsOneWidget);
  });

  testWidgets('muestra una vista previa cuando existe fotografía',
      (tester) async {
    await pumpSuccess(
      tester,
      bache(
        photoUrl: 'https://res.cloudinary.com/demo/image/upload/v1/photo.jpg',
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Reporte registrado sin fotografía'), findsNothing);
  });

  testWidgets('muestra medidas métricas y etiqueta correcta del área',
      (tester) async {
    await pumpSuccess(tester, bache(withMetric: true));

    expect(find.text('24.0 cm'), findsOneWidget);
    expect(find.text('18.0 cm'), findsOneWidget);
    expect(
      find.text('Área estimada del rectángulo envolvente'),
      findsOneWidget,
    );
    expect(find.text('432.0 cm²'), findsOneWidget);
    expect(
      find.text('Medición automática estimada mediante ARCore Depth'),
      findsOneWidget,
    );
  });

  testWidgets('muestra nulos y severidad sin inventar valores', (tester) async {
    await pumpSuccess(
      tester,
      bache(severity: 'No determinada', confidence: null),
    );

    expect(find.text('No determinada'), findsOneWidget);
    expect(find.text('Confianza no disponible'), findsOneWidget);
    expect(
      find.text('Medición automática no disponible para esta captura'),
      findsOneWidget,
    );
    expect(find.textContaining('0 cm'), findsNothing);
  });

  test('rechaza construir una confirmación sin ID real', () {
    expect(
      () => RegisterSuccessScreen(bache: bache(id: null)),
      throwsArgumentError,
    );
  });

  testWidgets('abre el mapa para coordenadas válidas', (tester) async {
    await pumpSuccess(
      tester,
      bache(),
      mapBuilder: (_) => const Scaffold(body: Text('Mapa seleccionado')),
    );
    await tester.dragUntilVisible(
      find.byKey(const Key('success_view_map')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.tap(find.byKey(const Key('success_view_map')));
    await tester.pumpAndSettle();

    expect(find.text('Mapa seleccionado'), findsOneWidget);
  });

  testWidgets('deshabilita mapa para coordenadas inválidas', (tester) async {
    await pumpSuccess(tester, bache(latitude: double.nan));
    await tester.dragUntilVisible(
      find.byKey(const Key('success_view_map')),
      find.byType(ListView),
      const Offset(0, -300),
    );

    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('success_view_map')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Ubicación no disponible'), findsOneWidget);
  });

  testWidgets('Nuevo reporte reemplaza Success por una pantalla limpia',
      (tester) async {
    var builds = 0;
    await pumpSuccess(
      tester,
      bache(),
      newReportBuilder: () {
        builds++;
        return const Scaffold(body: Text('Nueva detección limpia'));
      },
    );
    await tester.dragUntilVisible(
      find.byKey(const Key('success_new_report')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.tap(find.byKey(const Key('success_new_report')));
    await tester.pumpAndSettle();

    expect(builds, 1);
    expect(find.text('Nueva detección limpia'), findsOneWidget);
    expect(find.byType(RegisterSuccessScreen), findsNothing);
  });

  testWidgets('una fotografía remota rota muestra placeholder', (tester) async {
    await pumpSuccess(
      tester,
      bache(photoUrl: 'https://example.invalid/missing.jpg'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fotografía no disponible'), findsOneWidget);
  });

  testWidgets('Atrás vuelve al origen y no al ReportScreen reemplazado',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RegisterSuccessScreen(bache: bache()),
                ),
              ),
              child: const Text('Abrir confirmación'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir confirmación'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Abrir confirmación'), findsOneWidget);
    expect(find.byType(RegisterSuccessScreen), findsNothing);
  });
}
