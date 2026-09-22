import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spothole_app/models/bache_model.dart';
import 'package:spothole_app/screens/login_screen.dart';
import 'package:spothole_app/screens/main_screen.dart';
import 'package:spothole_app/screens/register_success_screen.dart';

void main() {
  Widget section(String name) => Scaffold(
        body: Center(
          child: Text(name, key: ValueKey('section_$name')),
        ),
      );

  MainScreen shell({
    int initialIndex = 0,
    MainHomeBuilder? homeBuilder,
    MainReportBuilder? reportBuilder,
    MainSectionBuilder? mapBuilder,
    MainSectionBuilder? historyBuilder,
    MainSectionBuilder? profileBuilder,
  }) {
    return MainScreen(
      initialIndex: initialIndex,
      homeBuilder: homeBuilder ?? (_) => section('Inicio'),
      reportBuilder: reportBuilder ??
          (_, __, released) => _TestReport(onResourcesReleased: released),
      mapBuilder: mapBuilder ?? () => section('Mapa'),
      historyBuilder: historyBuilder ?? () => section('Historial'),
      profileBuilder: profileBuilder ?? () => section('Perfil'),
    );
  }

  Future<void> pumpShell(WidgetTester tester, MainScreen mainScreen) async {
    await tester.pumpWidget(MaterialApp(home: mainScreen));
    await tester.pump();
  }

  testWidgets('Inicio es la sección inicial y la barra conserva el orden',
      (tester) async {
    await pumpShell(tester, shell());

    expect(find.byKey(const ValueKey('section_Inicio')), findsOneWidget);
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.selectedIndex, 0);
    expect(
      navigation.destinations
          .cast<NavigationDestination>()
          .map((item) => item.label),
      ['Inicio', 'Reportar', 'Mapa', 'Historial', 'Perfil'],
    );
  });

  testWidgets('Dashboard puede seleccionar las cuatro secciones principales',
      (tester) async {
    await pumpShell(
      tester,
      shell(
        homeBuilder: (select) => Scaffold(
          body: Column(
            children: [
              for (var index = 1; index < 5; index++)
                TextButton(
                  key: ValueKey('home_to_$index'),
                  onPressed: () => select(index),
                  child: Text('$index'),
                ),
            ],
          ),
        ),
      ),
    );

    for (var index = 1; index < 5; index++) {
      await tester.tap(find.byKey(ValueKey('home_to_$index')));
      await tester.pump();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        index,
      );
      await tester.tap(find.text('Inicio'));
      await tester.pump();
    }
  });

  testWidgets('la barra abre las cinco secciones sin mantenerlas montadas',
      (tester) async {
    await pumpShell(tester, shell());

    for (final name in ['Reportar', 'Mapa', 'Historial', 'Perfil', 'Inicio']) {
      await tester.tap(find.text(name));
      await tester.pump();
      expect(find.byKey(ValueKey('section_$name')), findsOneWidget);
    }
  });

  testWidgets('espera liberar una cámara antes de crear otra sesión',
      (tester) async {
    final tracker = _ReportTracker();
    await pumpShell(
      tester,
      shell(
        reportBuilder: (_, __, released) => _DelayedReport(
          tracker: tracker,
          onResourcesReleased: released,
        ),
      ),
    );

    await tester.tap(find.text('Reportar'));
    await tester.pump();
    expect(tracker.active, 1);
    expect(tracker.created, 1);

    await tester.tap(find.text('Mapa'));
    await tester.pump();
    await tester.tap(find.text('Reportar'));
    await tester.pump();
    expect(tracker.created, 1);
    expect(tracker.maximumActive, 1);

    await tester.pump(const Duration(milliseconds: 30));
    expect(tracker.active, 1);
    expect(tracker.created, 2);
    expect(tracker.maximumActive, 1);

    await tester.tap(find.text('Mapa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(tracker.active, 0);
  });

  testWidgets('Atrás desde cada sección secundaria vuelve a Inicio',
      (tester) async {
    await pumpShell(tester, shell());

    for (final name in ['Reportar', 'Mapa', 'Historial', 'Perfil']) {
      await tester.tap(find.text(name));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const ValueKey('section_Inicio')), findsOneWidget);
    }
  });

  testWidgets('Atrás desde Inicio mantiene el pop estándar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => shell()),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
  });

  testWidgets('volver a Inicio e Historial recrea datos para refrescarlos',
      (tester) async {
    var homeBuilds = 0;
    var historyBuilds = 0;
    await pumpShell(
      tester,
      shell(
        homeBuilder: (_) => section('Inicio ${++homeBuilds}'),
        historyBuilder: () => section('Historial ${++historyBuilds}'),
      ),
    );

    await tester.tap(find.text('Historial'));
    await tester.pump();
    await tester.tap(find.text('Inicio'));
    await tester.pump();
    await tester.tap(find.text('Historial'));
    await tester.pump();

    expect(homeBuilds, 2);
    expect(historyBuilds, 2);
  });

  testWidgets(
      'registro exitoso libera Reportar y controla Inicio/Nuevo reporte',
      (tester) async {
    await pumpShell(
      tester,
      shell(
        reportBuilder: (_, success, released) => _TestReport(
          onResourcesReleased: released,
          onSuccess: () => unawaited(success(_savedBache())),
        ),
      ),
    );
    await tester.tap(find.text('Reportar'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('fake_save')));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterSuccessScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('section_Reportar')), findsNothing);

    await tester.tap(find.byTooltip('Ir a Inicio'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('section_Inicio')), findsOneWidget);

    await tester.tap(find.text('Reportar'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('fake_save')));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const Key('success_new_report')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.tap(find.byKey(const Key('success_new_report')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('section_Reportar')), findsOneWidget);
    expect(find.byType(RegisterSuccessScreen), findsNothing);
  });

  testWidgets('Login autenticado abre el contenedor principal', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          loginAttempt: (_, __) async => true,
          authenticatedBuilder: (_) => shell(),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'user@example.com');
    await tester.enterText(find.byType(TextField).last, 'password');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.byType(MainScreen), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
  });

  testWidgets('Logout elimina toda la pila autenticada', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (rootContext) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                rootContext,
                MaterialPageRoute(
                  builder: (_) => shell(
                    profileBuilder: () => Scaffold(
                      body: Builder(
                        builder: (profileContext) => TextButton(
                          onPressed: () => Navigator.pushAndRemoveUntil(
                            profileContext,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                            (_) => false,
                          ),
                          child: const Text('Cerrar sesión'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('Entrar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfil'));
    await tester.pump();
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Entrar'), findsNothing);
  });
}

Bache _savedBache() => Bache(
      id: 'saved-id',
      latitud: -3.9931,
      longitud: -79.2042,
      fotoUrl: '',
      forma: 'Rectangular',
      anchoPx: 100,
      altoPx: 80,
      severidad: 'Moderado',
      fecha: DateTime.utc(2026, 9, 5),
      usuarioEmail: 'user@example.com',
      confianza: 0.9,
    );

class _TestReport extends StatefulWidget {
  const _TestReport({
    required this.onResourcesReleased,
    this.onSuccess,
  });

  final VoidCallback onResourcesReleased;
  final VoidCallback? onSuccess;

  @override
  State<_TestReport> createState() => _TestReportState();
}

class _TestReportState extends State<_TestReport> {
  @override
  void dispose() {
    widget.onResourcesReleased();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('fake_save'),
            onPressed: widget.onSuccess,
            child: const Text(
              'Reportar',
              key: ValueKey('section_Reportar'),
            ),
          ),
        ),
      );
}

class _ReportTracker {
  int active = 0;
  int created = 0;
  int maximumActive = 0;
}

class _DelayedReport extends StatefulWidget {
  const _DelayedReport({
    required this.tracker,
    required this.onResourcesReleased,
  });

  final _ReportTracker tracker;
  final VoidCallback onResourcesReleased;

  @override
  State<_DelayedReport> createState() => _DelayedReportState();
}

class _DelayedReportState extends State<_DelayedReport> {
  @override
  void initState() {
    super.initState();
    widget.tracker.active++;
    widget.tracker.created++;
    widget.tracker.maximumActive =
        widget.tracker.maximumActive < widget.tracker.active
            ? widget.tracker.active
            : widget.tracker.maximumActive;
  }

  @override
  void dispose() {
    Future<void>.delayed(const Duration(milliseconds: 20), () {
      widget.tracker.active--;
      widget.onResourcesReleased();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Text('Reportar', key: ValueKey('section_Reportar')),
      );
}
