import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:spothole_app/services/location_validation_service.dart';

void main() {
  final now = DateTime.utc(2026, 9, 4, 15);

  Position position({
    DateTime? timestamp,
    double latitude = -0.2,
    double longitude = -78.5,
    double accuracy = 8,
    bool isMocked = false,
  }) =>
      Position(
        latitude: latitude,
        longitude: longitude,
        timestamp: timestamp ?? now,
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
        isMocked: isMocked,
      );

  test('acepta una posición reciente y precisa', () {
    final result = LocationValidationService.validate(
      position(timestamp: now.subtract(const Duration(seconds: 20))),
      now: now,
    );

    expect(result.isValid, isTrue);
    expect(result.failure, isNull);
  });

  test('rechaza una posición antigua', () {
    final result = LocationValidationService.validate(
      position(timestamp: now.subtract(const Duration(seconds: 31))),
      now: now,
    );

    expect(result.failure, LocationValidationFailure.stale);
  });

  test('rechaza precisión insuficiente', () {
    final result = LocationValidationService.validate(
      position(accuracy: 51),
      now: now,
    );

    expect(
      result.failure,
      LocationValidationFailure.insufficientAccuracy,
    );
  });

  test('rechaza coordenadas inválidas y posiciones simuladas', () {
    expect(
      LocationValidationService.validate(
        position(latitude: double.nan),
        now: now,
      ).failure,
      LocationValidationFailure.invalidCoordinates,
    );
    expect(
      LocationValidationService.validate(
        position(isMocked: true),
        now: now,
      ).failure,
      LocationValidationFailure.mocked,
    );
  });
}
