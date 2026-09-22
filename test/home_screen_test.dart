import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spothole_app/models/bache_model.dart';
import 'package:spothole_app/models/dashboard_model.dart';
import 'package:spothole_app/models/history_model.dart';
import 'package:spothole_app/screens/home_screen.dart';
import 'package:spothole_app/screens/history_screen.dart';
import 'package:spothole_app/services/supabase_service.dart';

void main() {
  DashboardOverview overview({
    int total = 0,
    int withMeasurement = 0,
    String? name,
    List<DashboardReport> reports = const [],
  }) =>
      DashboardOverview(
        email: 'persona@example.com',
        displayName: name,
        totalReports: total,
        reportsWithMetricMeasurement: withMeasurement,
        recentReports: reports,
      );

  DashboardReport reportWithNulls() => DashboardReport(
        hasLocation: false,
        bache: Bache(
          id: 'report-1',
          latitud: 0,
          longitud: 0,
          fotoUrl: '',
          forma: 'Circular',
          anchoPx: 120,
          altoPx: 90,
          severidad: 'No determinada',
          fecha: DateTime.utc(2026, 9, 4, 15),
          usuarioEmail: 'persona@example.com',
        ),
      );

  Future<void> pumpDashboard(
    WidgetTester tester,
    DashboardRepository repository,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(dashboardRepository: repository),
      ),
    );
    await tester.pump();
  }

  testWidgets('muestra un estado útil para usuario sin reportes',
      (tester) async {
    await pumpDashboard(tester, _FakeRepository(overview()));

    expect(find.text('Hola'), findsOneWidget);
    expect(find.text('INICIAR DETECCIÓN'), findsOneWidget);
    expect(find.text('Total de reportes'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Aún no tienes reportes'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('Aún no tienes reportes'), findsOneWidget);
  });

  testWidgets('muestra reporte reciente conservando campos null',
      (tester) async {
    await pumpDashboard(
      tester,
      _FakeRepository(
        overview(
          total: 1,
          name: 'José',
          reports: [reportWithNulls()],
        ),
      ),
    );

    expect(find.text('Hola, José'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Último reporte'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('Último reporte'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Actividad reciente'),
      find.byType(ListView),
      const Offset(0, -250),
    );
    expect(find.text('Actividad reciente'), findsOneWidget);
    expect(find.text('Medición no disponible'), findsOneWidget);
    expect(find.text('Confianza no disponible'), findsOneWidget);
    expect(find.text('Sin foto'), findsOneWidget);
    expect(find.text('Ubicación no disponible'), findsNWidgets(2));
  });

  testWidgets('muestra error recuperable de carga', (tester) async {
    await pumpDashboard(
      tester,
      _ThrowingRepository(Exception('network unavailable')),
    );

    expect(find.text('No se pudo cargar el resumen'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('distingue ausencia de sesión', (tester) async {
    await pumpDashboard(
      tester,
      _ThrowingRepository(const DashboardSessionException()),
    );

    expect(find.text('Sesión expirada'), findsOneWidget);
    expect(find.text('Ir al inicio de sesión'), findsOneWidget);
  });

  testWidgets('actualiza los datos desde el botón de recarga', (tester) async {
    final repository = _MutableRepository(overview(total: 1));
    await pumpDashboard(tester, repository);
    expect(find.text('1'), findsOneWidget);

    repository.value = overview(total: 2);
    await tester.tap(find.byTooltip('Actualizar'));
    await tester.pump();

    expect(repository.calls, 2);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('delega Iniciar detección al contenedor principal',
      (tester) async {
    int? selectedIndex;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          dashboardRepository: _FakeRepository(overview()),
          onSelectSection: (index) => selectedIndex = index,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('start_detection_button')));
    await tester.pump();

    expect(selectedIndex, 1);
  });

  testWidgets('abre HistoryScreen desde el acceso del Dashboard',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          dashboardRepository: _FakeRepository(overview()),
          historyRepository: _EmptyHistoryRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Historial'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();

    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.text('No tienes reportes registrados todavía'), findsOneWidget);
  });
}

class _FakeRepository implements DashboardRepository {
  _FakeRepository(this.value);

  final DashboardOverview value;

  @override
  Future<DashboardOverview> cargarDashboard({int recentLimit = 5}) async =>
      value;
}

class _ThrowingRepository implements DashboardRepository {
  _ThrowingRepository(this.error);

  final Object error;

  @override
  Future<DashboardOverview> cargarDashboard({int recentLimit = 5}) async {
    throw error;
  }
}

class _MutableRepository implements DashboardRepository {
  _MutableRepository(this.value);

  DashboardOverview value;
  int calls = 0;

  @override
  Future<DashboardOverview> cargarDashboard({int recentLimit = 5}) async {
    calls++;
    return value;
  }
}

class _EmptyHistoryRepository implements HistoryRepository {
  @override
  Future<HistoryPage> cargarHistorial({
    HistorySeverityFilter filter = HistorySeverityFilter.all,
    int offset = 0,
    int pageSize = 20,
  }) async =>
      const HistoryPage(reports: [], hasMore: false);
}
