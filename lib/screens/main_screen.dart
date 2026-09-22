import 'dart:async';

import 'package:flutter/material.dart';

import '../models/bache_model.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'register_success_screen.dart';
import 'report_screen.dart';

typedef MainHomeBuilder = Widget Function(ValueChanged<int> onSelectSection);
typedef MainReportBuilder = Widget Function(
  ReportScreenController controller,
  Future<void> Function(Bache bache) onRegistrationSuccess,
  VoidCallback onResourcesReleased,
);
typedef MainSectionBuilder = Widget Function();

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    this.initialIndex = 0,
    this.homeBuilder,
    this.reportBuilder,
    this.mapBuilder,
    this.historyBuilder,
    this.profileBuilder,
  }) : assert(initialIndex >= 0 && initialIndex < 5);

  final int initialIndex;
  final MainHomeBuilder? homeBuilder;
  final MainReportBuilder? reportBuilder;
  final MainSectionBuilder? mapBuilder;
  final MainSectionBuilder? historyBuilder;
  final MainSectionBuilder? profileBuilder;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _selectedIndex;
  final ReportScreenController _reportController = ReportScreenController();
  Completer<void>? _reportRelease;
  bool _reportResourcesReleased = true;
  bool _reportSelectionPending = false;
  int _sectionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    if (_selectedIndex == 1) _reportResourcesReleased = false;
  }

  Future<void> _selectSection(int index) async {
    if (!mounted || index < 0 || index > 4 || index == _selectedIndex) return;

    if (_selectedIndex == 1) {
      final canLeave = await _reportController.confirmLeave();
      if (!mounted || !canLeave) return;
      _beginReportRelease();
    }

    if (index == 1 && !_reportResourcesReleased) {
      _reportSelectionPending = true;
      await _reportRelease?.future;
      if (!mounted || !_reportSelectionPending) return;
    }

    setState(() {
      _reportSelectionPending = false;
      _selectedIndex = index;
      _sectionGeneration++;
      if (index == 1) _reportResourcesReleased = false;
    });
  }

  void _beginReportRelease() {
    if (_reportResourcesReleased || _reportRelease != null) return;
    _reportRelease = Completer<void>();
  }

  void _handleReportResourcesReleased() {
    _reportResourcesReleased = true;
    final release = _reportRelease;
    _reportRelease = null;
    if (release != null && !release.isCompleted) release.complete();
  }

  Future<void> _handleRegistrationSuccess(Bache bache) async {
    if (!mounted || _selectedIndex != 1) return;
    _beginReportRelease();
    setState(() {
      _selectedIndex = 0;
      _sectionGeneration++;
    });
    await _reportRelease?.future;
    if (!mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RegisterSuccessScreen(
          bache: bache,
          onHome: () => _finishSuccessAt(0),
          onNewReport: () => _finishSuccessAt(1),
        ),
      ),
    );
  }

  void _finishSuccessAt(int index) {
    Navigator.pop(context);
    unawaited(_selectSection(index));
  }

  Widget _buildSection() {
    final key = ValueKey('main_${_selectedIndex}_$_sectionGeneration');
    switch (_selectedIndex) {
      case 0:
        return KeyedSubtree(
          key: key,
          child: widget.homeBuilder?.call(_selectSection) ??
              HomeScreen(onSelectSection: _selectSection),
        );
      case 1:
        return KeyedSubtree(
          key: key,
          child: widget.reportBuilder?.call(
                _reportController,
                _handleRegistrationSuccess,
                _handleReportResourcesReleased,
              ) ??
              ReportScreen(
                controller: _reportController,
                onRegistrationSuccess: _handleRegistrationSuccess,
                onResourcesReleased: _handleReportResourcesReleased,
              ),
        );
      case 2:
        return KeyedSubtree(
          key: key,
          child: widget.mapBuilder?.call() ?? const MapScreen(),
        );
      case 3:
        return KeyedSubtree(
          key: key,
          child: widget.historyBuilder?.call() ??
              HistoryScreen(onReportRequested: () => _selectSection(1)),
        );
      case 4:
        return KeyedSubtree(
          key: key,
          child: widget.profileBuilder?.call() ?? const ProfileScreen(),
        );
    }
    throw StateError('Índice de navegación inválido: $_selectedIndex');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedIndex != 0) unawaited(_selectSection(0));
      },
      child: Scaffold(
        body: _buildSection(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) => unawaited(_selectSection(index)),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Inicio',
            ),
            NavigationDestination(
              icon: Icon(Icons.add_a_photo_outlined),
              selectedIcon: Icon(Icons.add_a_photo),
              label: 'Reportar',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Mapa',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'Historial',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}
