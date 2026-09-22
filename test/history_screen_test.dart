import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spothole_app/models/bache_model.dart';
import 'package:spothole_app/models/dashboard_model.dart';
import 'package:spothole_app/models/history_model.dart';
import 'package:spothole_app/screens/history_screen.dart';
import 'package:spothole_app/services/supabase_service.dart';

void main() {
  DashboardReport report(
    int index, {
    String severity = 'Leve',
    bool withMetric = false,
    bool withLocation = true,
  }) =>
      DashboardReport(
        hasLocation: withLocation,
        bache: Bache(
          id: 'id-$index',
          latitud: withLocation ? -3.99 : 0,
          longitud: withLocation ? -79.20 : 0,
          fotoUrl: '',
          forma: 'Circular',
          anchoPx: 120 + index.toDouble(),
          altoPx: 90,
          anchoCm: withMetric ? 24 : null,
          altoCm: withMetric ? 18 : null,
          areaCm2: withMetric ? 432 : null,
          metodoMedicion:
              withMetric ? Bache.metodoArCoreDepth : Bache.metodoSinMedicion,
          severidad: severity,
          fecha:
              DateTime.utc(2026, 9, 5, 15).subtract(Duration(minutes: index)),
          usuarioEmail: 'persona@example.com',
          confianza: withMetric ? 0.91 : null,
        ),
      );

  Future<void> pumpHistory(
    WidgetTester tester,
    HistoryRepository repository,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(historyRepository: repository),
      ),
    );
    await tester.pump();
  }

  testWidgets('muestra estado útil cuando no existen reportes', (tester) async {
    await pumpHistory(
      tester,
      _FakeHistoryRepository(
        (_) => const HistoryPage(reports: [], hasMore: false),
      ),
    );

    expect(
      find.text('No tienes reportes registrados todavía'),
      findsOneWidget,
    );
    expect(find.text('Reportar bache'), findsOneWidget);
  });

  testWidgets('muestra medidas válidas y abre el detalle completo',
      (tester) async {
    final metricReport = report(1, severity: 'Moderado', withMetric: true);
    await pumpHistory(
      tester,
      _FakeHistoryRepository(
        (_) => HistoryPage(reports: [metricReport], hasMore: false),
      ),
    );

    expect(find.text('Moderado'), findsWidgets);
    expect(find.textContaining('Ancho/alto estimados'), findsOneWidget);
    expect(
      find.textContaining('Área estimada del rectángulo envolvente'),
      findsOneWidget,
    );
    expect(find.text('Confianza IA: 91.0%'), findsOneWidget);
    expect(find.text('Sin foto'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('history_report_id-1')));
    await tester.pumpAndSettle();

    expect(find.text('Detalle del reporte'), findsOneWidget);
    expect(find.text('id-1'), findsOneWidget);
    expect(find.text('Ver en mapa'), findsOneWidget);
    expect(
      find.textContaining('No representa la superficie irregular real'),
      findsOneWidget,
    );
  });

  testWidgets('tolera registro antiguo con campos null', (tester) async {
    await pumpHistory(
      tester,
      _FakeHistoryRepository(
        (_) => HistoryPage(
          reports: [
            report(
              0,
              severity: 'No determinada',
              withLocation: false,
            ),
          ],
          hasMore: false,
        ),
      ),
    );

    expect(find.text('Medición no disponible'), findsOneWidget);
    expect(find.text('Confianza IA: No disponible'), findsOneWidget);
    expect(find.text('Ubicación no disponible'), findsOneWidget);
    expect(find.text('Sin foto'), findsOneWidget);
    expect(find.textContaining('0 cm'), findsNothing);
  });

  testWidgets('aplica filtro y muestra estado sin coincidencias',
      (tester) async {
    final repository = _FakeHistoryRepository((call) {
      if (call.filter == HistorySeverityFilter.severe) {
        return const HistoryPage(reports: [], hasMore: false);
      }
      return HistoryPage(reports: [report(1)], hasMore: false);
    });
    await pumpHistory(tester, repository);

    await tester.tap(
      find.byKey(const ValueKey('history_filter_severe')),
    );
    await tester.pump();

    expect(repository.calls.last.filter, HistorySeverityFilter.severe);
    expect(find.text('No hay reportes con este filtro'), findsOneWidget);
    expect(find.text('Mostrar todos'), findsOneWidget);
  });

  testWidgets('carga una segunda página de forma incremental', (tester) async {
    final repository = _FakeHistoryRepository((call) {
      if (call.offset == 0) {
        return HistoryPage(
          reports: List.generate(20, report),
          hasMore: true,
        );
      }
      return HistoryPage(reports: [report(20)], hasMore: false);
    });
    await pumpHistory(tester, repository);

    await tester.drag(
      find.byType(ListView),
      const Offset(0, -6000),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repository.calls.any((call) => call.offset == 20), isTrue);
    expect(find.byKey(const ValueKey('history_report_id-20')), findsOneWidget);
    expect(find.text('No hay más reportes'), findsOneWidget);
  });

  testWidgets('muestra error de carga recuperable', (tester) async {
    await pumpHistory(
      tester,
      _ThrowingHistoryRepository(Exception('network unavailable')),
    );

    expect(find.text('No se pudo cargar el historial'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('muestra sesión expirada sin consultar datos visibles',
      (tester) async {
    await pumpHistory(
      tester,
      _ThrowingHistoryRepository(const DashboardSessionException()),
    );

    expect(find.text('Sesión expirada'), findsOneWidget);
    expect(find.text('Ir al inicio de sesión'), findsOneWidget);
  });
}

class _HistoryCall {
  const _HistoryCall({
    required this.filter,
    required this.offset,
    required this.pageSize,
  });

  final HistorySeverityFilter filter;
  final int offset;
  final int pageSize;
}

class _FakeHistoryRepository implements HistoryRepository {
  _FakeHistoryRepository(this.handler);

  final HistoryPage Function(_HistoryCall call) handler;
  final List<_HistoryCall> calls = [];

  @override
  Future<HistoryPage> cargarHistorial({
    HistorySeverityFilter filter = HistorySeverityFilter.all,
    int offset = 0,
    int pageSize = 20,
  }) async {
    final call = _HistoryCall(
      filter: filter,
      offset: offset,
      pageSize: pageSize,
    );
    calls.add(call);
    return handler(call);
  }
}

class _ThrowingHistoryRepository implements HistoryRepository {
  _ThrowingHistoryRepository(this.error);

  final Object error;

  @override
  Future<HistoryPage> cargarHistorial({
    HistorySeverityFilter filter = HistorySeverityFilter.all,
    int offset = 0,
    int pageSize = 20,
  }) async {
    throw error;
  }
}
