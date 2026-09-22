import 'package:geolocator/geolocator.dart';

enum LocationValidationFailure {
  invalidCoordinates,
  stale,
  futureTimestamp,
  insufficientAccuracy,
  mocked,
}

class LocationValidationResult {
  const LocationValidationResult.valid()
      : isValid = true,
        failure = null;

  const LocationValidationResult.invalid(this.failure) : isValid = false;

  final bool isValid;
  final LocationValidationFailure? failure;
}

class LocationValidationService {
  const LocationValidationService._();

  static const Duration maximumAge = Duration(seconds: 30);
  static const Duration futureTolerance = Duration(seconds: 5);
  static const double maximumAccuracyMeters = 50;

  static LocationValidationResult validate(
    Position position, {
    required DateTime now,
  }) {
    if (!position.latitude.isFinite ||
        !position.longitude.isFinite ||
        position.latitude < -90 ||
        position.latitude > 90 ||
        position.longitude < -180 ||
        position.longitude > 180) {
      return const LocationValidationResult.invalid(
        LocationValidationFailure.invalidCoordinates,
      );
    }

    if (position.isMocked) {
      return const LocationValidationResult.invalid(
        LocationValidationFailure.mocked,
      );
    }

    final age = now.toUtc().difference(position.timestamp.toUtc());
    if (age > maximumAge) {
      return const LocationValidationResult.invalid(
        LocationValidationFailure.stale,
      );
    }
    if (age < -futureTolerance) {
      return const LocationValidationResult.invalid(
        LocationValidationFailure.futureTimestamp,
      );
    }

    if (!position.accuracy.isFinite ||
        position.accuracy <= 0 ||
        position.accuracy > maximumAccuracyMeters) {
      return const LocationValidationResult.invalid(
        LocationValidationFailure.insufficientAccuracy,
      );
    }

    return const LocationValidationResult.valid();
  }
}
