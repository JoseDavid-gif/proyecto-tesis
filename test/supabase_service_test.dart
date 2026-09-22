import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spothole_app/models/bache_model.dart';
import 'package:spothole_app/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Bache buildBache() => Bache(
        latitud: -0.2,
        longitud: -78.5,
        fotoUrl: '',
        forma: 'Circular',
        anchoPx: 100,
        altoPx: 80,
        metodoMedicion: Bache.metodoSinMedicion,
        severidad: 'Leve',
        fecha: DateTime.utc(2026, 9, 4, 15),
        usuarioEmail: 'persona@example.com',
        confianza: 0.9,
      );

  test('guardarBache devuelve el ID real retornado por Supabase', () async {
    late http.Request capturedRequest;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            ...jsonDecode(request.body) as Map<String, dynamic>,
            'id': 'id-generado-por-supabase',
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final service = SupabaseService(client: client);

    final saved = await service.guardarBache(buildBache());

    expect(saved.id, 'id-generado-por-supabase');
    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.url.path, '/rest/v1/baches');
    expect(
        capturedRequest.headers['prefer'], contains('return=representation'));
    final sent = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
    expect(sent['usuario_email'], 'persona@example.com');
    expect(sent['foto_url'], '');
    expect(sent['ancho_cm'], isNull);
    expect(sent['alto_cm'], isNull);
    expect(sent['area_cm2'], isNull);
    expect(sent['altura_captura'], isNull);
    expect(sent['metodo_medicion'], Bache.metodoSinMedicion);
    expect(sent['fecha'], '2026-09-04T15:00:00.000Z');
    await client.dispose();
  });

  test('guardarBache rechaza una respuesta sin ID', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'latitud': -0.2}),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    final service = SupabaseService(client: client);

    await expectLater(
      service.guardarBache(buildBache()),
      throwsA(isA<SupabaseInsertException>()),
    );
    await client.dispose();
  });

  test('guardarBache propaga el rechazo de Supabase', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'code': '42501',
            'message': 'new row violates row-level security policy',
            'details': null,
            'hint': null,
          }),
          403,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    final service = SupabaseService(client: client);

    await expectLater(
      service.guardarBache(buildBache()),
      throwsA(isA<PostgrestException>()),
    );
    await client.dispose();
  });
}
