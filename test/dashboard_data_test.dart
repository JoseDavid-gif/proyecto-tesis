import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spothole_app/models/bache_model.dart';
import 'package:spothole_app/models/dashboard_model.dart';
import 'package:spothole_app/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Map<String, dynamic> report({
    required String id,
    required String date,
    double? area,
    String photo = '',
  }) =>
      {
        'id': id,
        'usuario_email': 'persona@example.com',
        'latitud': -3.99,
        'longitud': -79.20,
        'forma': 'Circular',
        'ancho_px': 100,
        'alto_px': 80,
        'ancho_cm': area == null ? null : 20,
        'alto_cm': area == null ? null : 10,
        'area_cm2': area,
        'altura_captura': null,
        'metodo_medicion':
            area == null ? Bache.metodoSinMedicion : Bache.metodoArCoreDepth,
        'severidad': area == null ? 'No determinada' : 'Leve',
        'foto_url': photo,
        'confianza': null,
        'fecha': date,
      };

  test('extrae únicamente un nombre presente en metadatos', () {
    expect(dashboardDisplayName({'full_name': '  José Pérez  '}), 'José Pérez');
    expect(dashboardDisplayName({'email': 'jose@example.com'}), isNull);
    expect(dashboardDisplayName(null), isNull);
  });

  test('rechaza la carga cuando no existe sesión', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient((_) async => http.Response('', 500)),
    );
    final service = SupabaseService(client: client);

    await expectLater(
      service.cargarDashboard(),
      throwsA(isA<DashboardSessionException>()),
    );
    await client.dispose();
  });

  test('usa conteos de servidor y actividad ordenada con límite', () async {
    final requests = <http.Request>[];
    final rows = [
      report(
        id: 'newest',
        date: '2026-09-04T15:00:00Z',
        area: 200,
        photo: 'https://example.com/photo.jpg',
      ),
      report(id: 'older', date: '2026-09-03T15:00:00Z'),
    ];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD') {
          final isMetricCount = request.url.query.contains('metodo_medicion');
          return http.Response(
            '',
            200,
            headers: {
              'content-range': isMetricCount ? '0-0/1' : '0-6/7',
            },
            request: request,
          );
        }
        return http.Response(
          jsonEncode(rows),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final service = SupabaseService(client: client);

    final overview = await service.cargarDashboardUsuario(
      email: 'persona@example.com',
      displayName: 'José',
      recentLimit: 5,
    );

    expect(overview.greeting, 'Hola, José');
    expect(overview.totalReports, 7);
    expect(overview.reportsWithMetricMeasurement, 1);
    expect(overview.recentReports, hasLength(2));
    expect(overview.latestReport?.bache.id, 'newest');
    expect(overview.recentReports.last.bache.id, 'older');
    expect(overview.recentReports.last.bache.areaCm2, isNull);
    expect(overview.recentReports.last.bache.confianza, isNull);

    final recentRequest = requests.singleWhere((r) => r.method == 'GET');
    expect(recentRequest.url.query,
        contains('usuario_email=eq.persona%40example.com'));
    expect(recentRequest.url.query, contains('order=fecha.desc'));
    expect(recentRequest.url.query, contains('limit=5'));
    final metricRequest = requests.singleWhere(
      (r) => r.method == 'HEAD' && r.url.query.contains('metodo_medicion'),
    );
    expect(metricRequest.url.query, contains('aruco'));
    expect(metricRequest.url.query, contains('arcore_depth'));
    await client.dispose();
  });

  test('representa correctamente al usuario sin reportes', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient((request) async {
        if (request.method == 'HEAD') {
          return http.Response(
            '',
            200,
            headers: {'content-range': '*/0'},
            request: request,
          );
        }
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final service = SupabaseService(client: client);

    final overview = await service.cargarDashboardUsuario(
      email: 'persona@example.com',
    );

    expect(overview.greeting, 'Hola');
    expect(overview.totalReports, 0);
    expect(overview.latestReport, isNull);
    expect(overview.recentReports, isEmpty);
    await client.dispose();
  });

  test('propaga un error de carga sin convertirlo en datos vacíos', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'code': '500', 'message': 'server error'}),
          500,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    final service = SupabaseService(client: client);

    await expectLater(
      service.cargarDashboardUsuario(email: 'persona@example.com'),
      throwsA(isA<PostgrestException>()),
    );
    await client.dispose();
  });
}
