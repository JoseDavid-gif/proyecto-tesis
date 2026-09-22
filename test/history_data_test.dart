import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spothole_app/models/history_model.dart';
import 'package:spothole_app/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Map<String, dynamic> report(int index, {String severity = 'Leve'}) => {
        'id': 'id-$index',
        'usuario_email': 'persona@example.com',
        'latitud': index == 0 ? null : -3.99,
        'longitud': index == 0 ? null : -79.20,
        'forma': 'Circular',
        'ancho_px': 100 + index,
        'alto_px': 80,
        'ancho_cm': index == 0 ? null : 20,
        'alto_cm': index == 0 ? null : 10,
        'area_cm2': index == 0 ? null : 200,
        'altura_captura': null,
        'severidad': severity,
        'foto_url': index == 0 ? null : 'https://example.com/$index.jpg',
        'confianza': index == 0 ? null : 0.9,
        'fecha': DateTime.utc(2026, 9, 5)
            .subtract(Duration(minutes: index))
            .toIso8601String(),
      };

  test('genera miniatura Cloudinary sin modificar otros proveedores', () {
    expect(
      historyThumbnailUrl(
        'https://res.cloudinary.com/demo/image/upload/v1/photo.jpg',
        width: 240,
      ),
      'https://res.cloudinary.com/demo/image/upload/'
      'f_auto,q_auto,w_240,c_limit/v1/photo.jpg',
    );
    expect(
      historyThumbnailUrl('https://example.com/photo.jpg'),
      'https://example.com/photo.jpg',
    );
  });

  test('rechaza historial sin sesión antes de consultar baches', () async {
    var requestCount = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient((_) async {
        requestCount++;
        return http.Response('', 500);
      }),
    );
    final service = SupabaseService(client: client);

    await expectLater(
      service.cargarHistorial(),
      throwsA(isA<DashboardSessionException>()),
    );
    expect(requestCount, 0);
    await client.dispose();
  });

  test('consulta por usuario con orden DESC y primera página de 20', () async {
    late http.Request captured;
    final rows = List.generate(21, report);
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(rows),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final service = SupabaseService(client: client);

    final page = await service.cargarHistorialUsuario(
      email: 'persona@example.com',
    );

    expect(page.reports, hasLength(20));
    expect(page.hasMore, isTrue);
    expect(page.reports.first.bache.id, 'id-0');
    expect(page.reports.last.bache.id, 'id-19');
    expect(page.reports.first.hasLocation, isFalse);
    expect(page.reports.first.bache.areaCm2, isNull);
    expect(page.reports.first.bache.confianza, isNull);
    expect(page.reports.first.bache.fotoUrl, isEmpty);
    expect(
        captured.url.query, contains('usuario_email=eq.persona%40example.com'));
    expect(
      captured.url.query,
      contains('order=fecha.desc.nullslast%2Cid.desc.nullslast'),
    );
    expect(captured.url.query, contains('offset=0'));
    expect(captured.url.query, contains('limit=21'));
    await client.dispose();
  });

  for (final filter in HistorySeverityFilter.values.where(
    (value) => value != HistorySeverityFilter.all,
  )) {
    test('aplica filtro ${filter.label} en Supabase', () async {
      late http.Request captured;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final service = SupabaseService(client: client);

      final page = await service.cargarHistorialUsuario(
        email: 'persona@example.com',
        filter: filter,
      );

      expect(page.reports, isEmpty);
      expect(page.hasMore, isFalse);
      expect(
        captured.url.query,
        contains(
            'severidad=eq.${Uri.encodeQueryComponent(filter.databaseValue!)}'),
      );
      await client.dispose();
    });
  }

  test('segunda página usa el rango correcto y detecta el final', () async {
    late http.Request captured;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode([report(20), report(21)]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final service = SupabaseService(client: client);

    final page = await service.cargarHistorialUsuario(
      email: 'persona@example.com',
      offset: 20,
    );

    expect(page.reports, hasLength(2));
    expect(page.hasMore, isFalse);
    expect(captured.url.query, contains('offset=20'));
    expect(captured.url.query, contains('limit=21'));
    await client.dispose();
  });

  test('propaga errores de carga', () async {
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
      service.cargarHistorialUsuario(email: 'persona@example.com'),
      throwsA(isA<PostgrestException>()),
    );
    await client.dispose();
  });
}
