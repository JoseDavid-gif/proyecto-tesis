import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spothole_app/services/cloudinary_service.dart';

void main() {
  late Directory tempDirectory;
  late File image;

  setUp(() async {
    tempDirectory =
        await Directory.systemTemp.createTemp('spothole_cloudinary_');
    image = await File('${tempDirectory.path}/evidence.jpg')
        .writeAsBytes([1, 2, 3]);
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('acepta una respuesta HTTPS con URL y public_id', () async {
    final service = CloudinaryService(
      client: MockClient(
        (_) async => http.Response(
          '{"secure_url":"https://res.cloudinary.com/demo/image/upload/a.jpg",'
          '"public_id":"spothole/a"}',
          200,
        ),
      ),
    );

    final result = await service.subirFoto(image);

    expect(
      result.secureUrl,
      'https://res.cloudinary.com/demo/image/upload/a.jpg',
    );
    expect(result.publicId, 'spothole/a');
    service.dispose();
  });

  test('distingue rechazo HTTP', () async {
    final service = CloudinaryService(
      client: MockClient((_) async => http.Response('unauthorized', 401)),
    );

    await expectLater(
      service.subirFoto(image),
      throwsA(
        isA<CloudinaryUploadException>()
            .having(
              (error) => error.failure,
              'failure',
              CloudinaryUploadFailure.rejected,
            )
            .having((error) => error.statusCode, 'statusCode', 401),
      ),
    );
    service.dispose();
  });

  test('rechaza una respuesta sin secure_url válida', () async {
    final service = CloudinaryService(
      client: MockClient((_) async => http.Response('{"public_id":"a"}', 200)),
    );

    await expectLater(
      service.subirFoto(image),
      throwsA(
        isA<CloudinaryUploadException>().having(
          (error) => error.failure,
          'failure',
          CloudinaryUploadFailure.invalidResponse,
        ),
      ),
    );
    service.dispose();
  });

  test('distingue timeout de carga', () async {
    final pending = Completer<http.Response>();
    final service = CloudinaryService(
      client: MockClient((_) => pending.future),
      uploadTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      service.subirFoto(image),
      throwsA(
        isA<CloudinaryUploadException>().having(
          (error) => error.failure,
          'failure',
          CloudinaryUploadFailure.timeout,
        ),
      ),
    );
    service.dispose();
  });

  test('distingue fallo de red', () async {
    final service = CloudinaryService(
      client: MockClient(
        (request) async => throw http.ClientException(
          'network unavailable',
          request.url,
        ),
      ),
    );

    await expectLater(
      service.subirFoto(image),
      throwsA(
        isA<CloudinaryUploadException>().having(
          (error) => error.failure,
          'failure',
          CloudinaryUploadFailure.network,
        ),
      ),
    );
    service.dispose();
  });

  test('rechaza una fotografía temporal ausente', () async {
    await image.delete();
    final service = CloudinaryService(
      client: MockClient((_) async => http.Response('', 200)),
    );

    await expectLater(
      service.subirFoto(image),
      throwsA(
        isA<CloudinaryUploadException>().having(
          (error) => error.failure,
          'failure',
          CloudinaryUploadFailure.missingFile,
        ),
      ),
    );
    service.dispose();
  });
}
