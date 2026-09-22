import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bache_model.dart';
import '../models/dashboard_model.dart';
import '../models/history_model.dart';

abstract interface class DashboardRepository {
  Future<DashboardOverview> cargarDashboard({int recentLimit = 5});
}

abstract interface class HistoryRepository {
  Future<HistoryPage> cargarHistorial({
    HistorySeverityFilter filter = HistorySeverityFilter.all,
    int offset = 0,
    int pageSize = 20,
  });
}

class SupabaseService implements DashboardRepository, HistoryRepository {
  SupabaseService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  static const Duration _operationTimeout = Duration(seconds: 20);

  final SupabaseClient _db;

  static const String _bacheColumns =
      'id, usuario_email, latitud, longitud, forma, ancho_px, alto_px, '
      'ancho_cm, alto_cm, area_cm2, altura_captura, severidad, foto_url, '
      'confianza, fecha, metodo_medicion';

  Future<Bache> guardarBache(Bache bache) async {
    final row = await _db
        .from('baches')
        .insert(bache.toMap())
        .select()
        .single()
        .timeout(_operationTimeout);

    final rawId = row['id'];
    if (rawId == null || rawId.toString().trim().isEmpty) {
      throw const SupabaseInsertException(
        'Supabase confirmó una fila sin devolver su identificador.',
      );
    }

    return Bache.fromMap(row, rawId.toString());
  }

  Stream<List<Bache>> obtenerBaches() {
    return _db
        .from('baches')
        .stream(primaryKey: ['id'])
        .order('fecha', ascending: false)
        .map(
          (data) => data
              .map((row) => Bache.fromMap(row, row['id'].toString()))
              .toList(),
        );
  }

  @override
  Future<DashboardOverview> cargarDashboard({int recentLimit = 5}) async {
    if (_db.auth.currentSession == null) {
      throw const DashboardSessionException();
    }

    late final UserResponse response;
    try {
      response = await _db.auth.getUser().timeout(_operationTimeout);
    } on AuthSessionMissingException {
      throw const DashboardSessionException();
    } on AuthApiException catch (error) {
      if (error.statusCode == '401' || error.statusCode == '403') {
        throw const DashboardSessionException();
      }
      rethrow;
    }
    final user = response.user;
    final email = user?.email?.trim();
    if (user == null || email == null || email.isEmpty) {
      throw const DashboardSessionException();
    }

    return cargarDashboardUsuario(
      email: email,
      displayName: dashboardDisplayName(user.userMetadata),
      recentLimit: recentLimit,
    );
  }

  Future<DashboardOverview> cargarDashboardUsuario({
    required String email,
    String? displayName,
    int recentLimit = 5,
  }) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      throw const DashboardSessionException();
    }
    if (recentLimit < 1 || recentLimit > 20) {
      throw ArgumentError.value(recentLimit, 'recentLimit');
    }

    final results = await Future.wait<dynamic>([
      _db
          .from('baches')
          .count(CountOption.exact)
          .eq('usuario_email', normalizedEmail)
          .timeout(_operationTimeout),
      _db
          .from('baches')
          .count(CountOption.exact)
          .eq('usuario_email', normalizedEmail)
          .inFilter('metodo_medicion', [
        Bache.metodoAruco,
        Bache.metodoArCoreDepth,
      ]).timeout(_operationTimeout),
      _db
          .from('baches')
          .select(_bacheColumns)
          .eq('usuario_email', normalizedEmail)
          .order('fecha', ascending: false)
          .limit(recentLimit)
          .timeout(_operationTimeout),
    ]);

    final rows = (results[2] as List)
        .map(
          (row) => DashboardReport.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

    return DashboardOverview(
      email: normalizedEmail,
      displayName: displayName,
      totalReports: results[0] as int,
      reportsWithMetricMeasurement: results[1] as int,
      recentReports: rows,
    );
  }

  @override
  Future<HistoryPage> cargarHistorial({
    HistorySeverityFilter filter = HistorySeverityFilter.all,
    int offset = 0,
    int pageSize = 20,
  }) async {
    if (_db.auth.currentSession == null) {
      throw const DashboardSessionException();
    }

    late final UserResponse response;
    try {
      response = await _db.auth.getUser().timeout(_operationTimeout);
    } on AuthSessionMissingException {
      throw const DashboardSessionException();
    } on AuthApiException catch (error) {
      if (error.statusCode == '401' || error.statusCode == '403') {
        throw const DashboardSessionException();
      }
      rethrow;
    }

    final email = response.user?.email?.trim();
    if (email == null || email.isEmpty) {
      throw const DashboardSessionException();
    }

    return cargarHistorialUsuario(
      email: email,
      filter: filter,
      offset: offset,
      pageSize: pageSize,
    );
  }

  Future<HistoryPage> cargarHistorialUsuario({
    required String email,
    HistorySeverityFilter filter = HistorySeverityFilter.all,
    int offset = 0,
    int pageSize = 20,
  }) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      throw const DashboardSessionException();
    }
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    if (pageSize < 1 || pageSize > 50) {
      throw ArgumentError.value(pageSize, 'pageSize');
    }

    var query = _db
        .from('baches')
        .select(_bacheColumns)
        .eq('usuario_email', normalizedEmail);
    final severity = filter.databaseValue;
    if (severity != null) {
      query = query.eq('severidad', severity);
    }

    final response = await query
        .order('fecha', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + pageSize)
        .timeout(_operationTimeout);
    final rows = response as List;
    final hasMore = rows.length > pageSize;
    final reports = rows
        .take(pageSize)
        .map(
          (row) => DashboardReport.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

    return HistoryPage(reports: reports, hasMore: hasMore);
  }
}

class DashboardSessionException implements Exception {
  const DashboardSessionException();

  @override
  String toString() => 'No existe una sesión autenticada válida.';
}

class SupabaseInsertException implements Exception {
  const SupabaseInsertException(this.message);

  final String message;

  @override
  String toString() => message;
}
