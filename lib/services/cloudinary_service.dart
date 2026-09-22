import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

enum CloudinaryUploadFailure {
  missingFile,
  timeout,
  network,
  rejected,
  invalidResponse,
}

class CloudinaryUploadException implements Exception {
  const CloudinaryUploadException(
    this.failure, {
    this.statusCode,
    this.cause,
  });

  final CloudinaryUploadFailure failure;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => 'CloudinaryUploadException('
      'failure: $failure, statusCode: $statusCode, cause: $cause)';
}

class CloudinaryUploadResult {
  const CloudinaryUploadResult({
    required this.secureUrl,
    this.publicId,
  });

  final String secureUrl;
  final String? publicId;
}

class CloudinaryService {
  CloudinaryService({
    http.Client? client,
    this.uploadTimeout = const Duration(seconds: 25),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const String cloudName = 'dhtrachwq';
  static const String uploadPreset = 'spothole_uploads';

  final http.Client _client;
  final bool _ownsClient;
  final Duration uploadTimeout;

  Future<CloudinaryUploadResult> subirFoto(File imagen) async {
    if (!await imagen.exists()) {
      throw const CloudinaryUploadException(
        CloudinaryUploadFailure.missingFile,
      );
    }

    try {
      final url = Uri.https(
        'api.cloudinary.com',
        '/v1_1/$cloudName/image/upload',
      );
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', imagen.path));

      final streamedResponse =
          await _client.send(request).timeout(uploadTimeout);
      final responseData =
          await streamedResponse.stream.toBytes().timeout(uploadTimeout);

      if (streamedResponse.statusCode < 200 ||
          streamedResponse.statusCode >= 300) {
        throw CloudinaryUploadException(
          CloudinaryUploadFailure.rejected,
          statusCode: streamedResponse.statusCode,
        );
      }

      final decoded = jsonDecode(utf8.decode(responseData));
      if (decoded is! Map<String, dynamic>) {
        throw const CloudinaryUploadException(
          CloudinaryUploadFailure.invalidResponse,
        );
      }

      final secureUrl = decoded['secure_url']?.toString().trim();
      final parsedUrl = secureUrl == null ? null : Uri.tryParse(secureUrl);
      if (secureUrl == null ||
          secureUrl.isEmpty ||
          parsedUrl == null ||
          parsedUrl.scheme != 'https' ||
          parsedUrl.host.isEmpty) {
        throw const CloudinaryUploadException(
          CloudinaryUploadFailure.invalidResponse,
        );
      }

      final rawPublicId = decoded['public_id']?.toString().trim();
      return CloudinaryUploadResult(
        secureUrl: secureUrl,
        publicId:
            rawPublicId == null || rawPublicId.isEmpty ? null : rawPublicId,
      );
    } on CloudinaryUploadException {
      rethrow;
    } on TimeoutException catch (error) {
      throw CloudinaryUploadException(
        CloudinaryUploadFailure.timeout,
        cause: error,
      );
    } on SocketException catch (error) {
      throw CloudinaryUploadException(
        CloudinaryUploadFailure.network,
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw CloudinaryUploadException(
        CloudinaryUploadFailure.network,
        cause: error,
      );
    } on FormatException catch (error) {
      throw CloudinaryUploadException(
        CloudinaryUploadFailure.invalidResponse,
        cause: error,
      );
    } catch (error) {
      throw CloudinaryUploadException(
        CloudinaryUploadFailure.network,
        cause: error,
      );
    }
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
