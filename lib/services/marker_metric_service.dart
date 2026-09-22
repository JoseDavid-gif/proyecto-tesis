import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Punto bidimensional expresado en píxeles o centímetros según el contexto.
class MetricPoint {
  const MetricPoint(this.x, this.y);

  final double x;
  final double y;

  bool get isFinite => x.isFinite && y.isFinite;
}

class MarkerMetricConfig {
  const MarkerMetricConfig({
    this.markerId = 0,
    this.widthCm = 20,
    this.heightCm = 20,
    this.minimumSidePx = 20,
    this.minimumAreaPx2 = 400,
    this.maximumSideRatio = 4,
  });

  /// El marcador impreso debe medir exactamente estas dimensiones exteriores.
  final int markerId;
  final double widthCm;
  final double heightCm;
  final double minimumSidePx;
  final double minimumAreaPx2;
  final double maximumSideRatio;
}

class MetricBoundingBox {
  const MetricBoundingBox({
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
  });

  final double centerX;
  final double centerY;
  final double width;
  final double height;

  List<MetricPoint> get corners {
    final halfWidth = width / 2;
    final halfHeight = height / 2;
    return [
      MetricPoint(centerX - halfWidth, centerY - halfHeight),
      MetricPoint(centerX + halfWidth, centerY - halfHeight),
      MetricPoint(centerX + halfWidth, centerY + halfHeight),
      MetricPoint(centerX - halfWidth, centerY + halfHeight),
    ];
  }
}

class MarkerMetricMeasurement {
  const MarkerMetricMeasurement({
    required this.widthCm,
    required this.heightCm,
    required this.boundingBoxAreaCm2,
    required this.markerId,
    required this.projectedCorners,
  });

  final double widthCm;
  final double heightCm;

  /// Área del rectángulo envolvente, no del contorno irregular del bache.
  final double boundingBoxAreaCm2;
  final int markerId;
  final List<MetricPoint> projectedCorners;
}

class MarkerMetricProfile {
  int grayscalePreparationUs = 0;
  int arucoDetectionUs = 0;
  int homographyUs = 0;
  int metricCalculationUs = 0;
  bool markerFound = false;
  bool markerValid = false;

  int get arucoTotalUs => grayscalePreparationUs + arucoDetectionUs;
}

/// Detecta una referencia ArUco y rectifica el bounding box al plano métrico.
///
/// La medición solo es válida si el marcador y el bache están sobre el mismo
/// plano físico. Esa condición debe garantizarse durante la captura controlada.
class MarkerMetricService {
  MarkerMetricService({this.config = const MarkerMetricConfig()});

  final MarkerMetricConfig config;

  cv.ArucoDictionary? _dictionary;
  cv.ArucoDetectorParameters? _parameters;
  cv.ArucoDetector? _detector;
  cv.Mat? _grayscaleMat;

  MarkerMetricMeasurement? detectAndMeasure({
    required img.Image image,
    required MetricBoundingBox boundingBox,
    MarkerMetricProfile? profile,
  }) {
    try {
      _ensureDetector();
      final grayscaleWatch = Stopwatch()..start();
      final grayscale = _toGrayscaleMat(image);
      grayscaleWatch.stop();
      profile?.grayscalePreparationUs = grayscaleWatch.elapsedMicroseconds;
      final detectionWatch = Stopwatch()..start();
      final (corners, ids, rejected) = _detector!.detectMarkers(grayscale);
      detectionWatch.stop();
      profile?.arucoDetectionUs = detectionWatch.elapsedMicroseconds;
      try {
        for (var index = 0; index < ids.length; index++) {
          if (ids[index] != config.markerId) continue;
          profile?.markerFound = true;

          final detectedCorners = corners[index];
          if (detectedCorners.length != 4) return null;

          final points = List.generate(
            4,
            (cornerIndex) => MetricPoint(
              detectedCorners[cornerIndex].x,
              detectedCorners[cornerIndex].y,
            ),
          );
          return measureWithCorners(
            markerCorners: points,
            boundingBox: boundingBox,
            imageWidth: image.width,
            imageHeight: image.height,
            profile: profile,
          );
        }
      } finally {
        corners.dispose();
        ids.dispose();
        rejected.dispose();
      }
    } catch (error) {
      debugPrint('Referencia métrica descartada: $error');
    }
    return null;
  }

  @visibleForTesting
  MarkerMetricMeasurement? measureWithCorners({
    required List<MetricPoint> markerCorners,
    required MetricBoundingBox boundingBox,
    required int imageWidth,
    required int imageHeight,
    MarkerMetricProfile? profile,
  }) {
    final metricWatch = Stopwatch()..start();
    if (!_hasValidConfiguration() ||
        !_isValidMarkerGeometry(markerCorners, imageWidth, imageHeight) ||
        !_isBoundingBoxVisible(boundingBox, imageWidth, imageHeight)) {
      metricWatch.stop();
      profile?.metricCalculationUs = metricWatch.elapsedMicroseconds;
      return null;
    }

    final source = cv.Mat.from3DList(
      markerCorners.map((point) => [
            <double>[point.x, point.y]
          ]),
      cv.MatType.CV_32FC2,
    );
    final metricCorners = [
      const MetricPoint(0, 0),
      MetricPoint(config.widthCm, 0),
      MetricPoint(config.widthCm, config.heightCm),
      MetricPoint(0, config.heightCm),
    ];
    final destination = cv.Mat.from3DList(
      metricCorners.map((point) => [
            <double>[point.x, point.y]
          ]),
      cv.MatType.CV_32FC2,
    );

    cv.Mat? homography;
    try {
      final homographyWatch = Stopwatch()..start();
      homography = cv.findHomography(source, destination);
      final validHomography = _isValidHomography(homography);
      homographyWatch.stop();
      profile?.homographyUs = homographyWatch.elapsedMicroseconds;
      if (!validHomography) return null;

      final projectedMarker = _projectPoints(markerCorners, homography);
      if (projectedMarker == null ||
          !_hasLowReprojectionError(projectedMarker)) {
        return null;
      }

      final projectedBox = _projectPoints(boundingBox.corners, homography);
      if (projectedBox == null || projectedBox.length != 4) return null;

      final width = (distance(projectedBox[0], projectedBox[1]) +
              distance(projectedBox[3], projectedBox[2])) /
          2;
      final height = (distance(projectedBox[0], projectedBox[3]) +
              distance(projectedBox[1], projectedBox[2])) /
          2;

      if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
        return null;
      }

      final area = width * height;
      if (!area.isFinite || area <= 0) return null;

      final measurement = MarkerMetricMeasurement(
        widthCm: width,
        heightCm: height,
        boundingBoxAreaCm2: area,
        markerId: config.markerId,
        projectedCorners: projectedBox,
      );
      profile?.markerValid = true;
      return measurement;
    } catch (error) {
      debugPrint('Homografía descartada: $error');
      return null;
    } finally {
      metricWatch.stop();
      if (profile != null) {
        profile.metricCalculationUs =
            metricWatch.elapsedMicroseconds - profile.homographyUs;
      }
      homography?.dispose();
      source.dispose();
      destination.dispose();
    }
  }

  @visibleForTesting
  static double distance(MetricPoint first, MetricPoint second) {
    return math.sqrt(
      math.pow(second.x - first.x, 2) + math.pow(second.y - first.y, 2),
    );
  }

  bool _hasValidConfiguration() {
    return config.markerId >= 0 &&
        config.widthCm.isFinite &&
        config.heightCm.isFinite &&
        config.widthCm > 0 &&
        config.heightCm > 0;
  }

  bool _isValidMarkerGeometry(
    List<MetricPoint> corners,
    int imageWidth,
    int imageHeight,
  ) {
    if (corners.length != 4 || imageWidth <= 0 || imageHeight <= 0) {
      return false;
    }

    final borderMargin =
        math.max(2.0, math.min(imageWidth, imageHeight) * 0.005);
    if (corners.any(
      (point) =>
          !point.isFinite ||
          point.x <= borderMargin ||
          point.y <= borderMargin ||
          point.x >= imageWidth - borderMargin ||
          point.y >= imageHeight - borderMargin,
    )) {
      return false;
    }

    final sides = List.generate(
      4,
      (index) => distance(corners[index], corners[(index + 1) % 4]),
    );
    final minimumSide = sides.reduce(math.min);
    final maximumSide = sides.reduce(math.max);
    if (minimumSide < config.minimumSidePx ||
        maximumSide / minimumSide > config.maximumSideRatio) {
      return false;
    }

    final signedCrossProducts = List.generate(4, (index) {
      final current = corners[index];
      final next = corners[(index + 1) % 4];
      final following = corners[(index + 2) % 4];
      return (next.x - current.x) * (following.y - next.y) -
          (next.y - current.y) * (following.x - next.x);
    });
    final allPositive = signedCrossProducts.every((value) => value > 1e-6);
    final allNegative = signedCrossProducts.every((value) => value < -1e-6);
    if (!allPositive && !allNegative) return false;

    final area = _polygonArea(corners);
    if (area < config.minimumAreaPx2) return false;

    final xs = corners.map((point) => point.x);
    final ys = corners.map((point) => point.y);
    final boundingArea = (xs.reduce(math.max) - xs.reduce(math.min)) *
        (ys.reduce(math.max) - ys.reduce(math.min));
    return boundingArea > 0 && area / boundingArea >= 0.25;
  }

  bool _isBoundingBoxVisible(
    MetricBoundingBox box,
    int imageWidth,
    int imageHeight,
  ) {
    if (!box.centerX.isFinite ||
        !box.centerY.isFinite ||
        !box.width.isFinite ||
        !box.height.isFinite ||
        box.width <= 0 ||
        box.height <= 0) {
      return false;
    }
    return box.corners.every(
      (point) =>
          point.x >= 0 &&
          point.y >= 0 &&
          point.x <= imageWidth &&
          point.y <= imageHeight,
    );
  }

  bool _isValidHomography(cv.Mat homography) {
    if (homography.isEmpty || homography.rows != 3 || homography.cols != 3) {
      return false;
    }
    final values = List.generate(
      3,
      (row) => List.generate(
        3,
        (column) => homography.at<double>(row, column),
      ),
    );
    if (values.expand((row) => row).any((value) => !value.isFinite)) {
      return false;
    }
    final determinant = values[0][0] *
            (values[1][1] * values[2][2] - values[1][2] * values[2][1]) -
        values[0][1] *
            (values[1][0] * values[2][2] - values[1][2] * values[2][0]) +
        values[0][2] *
            (values[1][0] * values[2][1] - values[1][1] * values[2][0]);
    return determinant.isFinite && determinant.abs() > 1e-12;
  }

  List<MetricPoint>? _projectPoints(
    List<MetricPoint> points,
    cv.Mat homography,
  ) {
    final values = List.generate(
      9,
      (index) => homography.at<double>(index ~/ 3, index % 3),
    );
    return projectPointsWithMatrix(points, values);
  }

  @visibleForTesting
  static List<MetricPoint>? projectPointsWithMatrix(
    List<MetricPoint> points,
    List<double> homography,
  ) {
    if (homography.length != 9 || homography.any((value) => !value.isFinite)) {
      return null;
    }

    final projected = <MetricPoint>[];
    for (final point in points) {
      final denominator =
          homography[6] * point.x + homography[7] * point.y + homography[8];
      if (!denominator.isFinite || denominator.abs() < 1e-9) return null;
      final result = MetricPoint(
        (homography[0] * point.x + homography[1] * point.y + homography[2]) /
            denominator,
        (homography[3] * point.x + homography[4] * point.y + homography[5]) /
            denominator,
      );
      if (!result.isFinite) return null;
      projected.add(result);
    }
    return projected;
  }

  bool _hasLowReprojectionError(List<MetricPoint> projectedMarker) {
    final expected = [
      const MetricPoint(0, 0),
      MetricPoint(config.widthCm, 0),
      MetricPoint(config.widthCm, config.heightCm),
      MetricPoint(0, config.heightCm),
    ];
    for (var index = 0; index < expected.length; index++) {
      if (distance(projectedMarker[index], expected[index]) > 0.05) {
        return false;
      }
    }
    return true;
  }

  double _polygonArea(List<MetricPoint> points) {
    var twiceArea = 0.0;
    for (var index = 0; index < points.length; index++) {
      final current = points[index];
      final next = points[(index + 1) % points.length];
      twiceArea += current.x * next.y - next.x * current.y;
    }
    return twiceArea.abs() / 2;
  }

  cv.Mat _toGrayscaleMat(img.Image image) {
    if (_grayscaleMat == null ||
        _grayscaleMat!.cols != image.width ||
        _grayscaleMat!.rows != image.height) {
      _grayscaleMat?.dispose();
      _grayscaleMat = cv.Mat.zeros(
        image.height,
        image.width,
        cv.MatType.CV_8UC1,
      );
    }
    final pixels = _grayscaleMat!.data;
    var index = 0;
    for (final pixel in image) {
      pixels[index++] =
          (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
    }
    return _grayscaleMat!;
  }

  void _ensureDetector() {
    if (_detector != null) return;
    _dictionary = cv.ArucoDictionary.predefined(
      cv.PredefinedDictionaryType.DICT_6X6_250,
    );
    _parameters = cv.ArucoDetectorParameters.empty()
      ..cornerRefinementMethod = 1
      ..minDistanceToBorder = 3;
    _detector = cv.ArucoDetector.create(_dictionary!, _parameters!);
  }

  void dispose() {
    _grayscaleMat?.dispose();
    _detector?.dispose();
    _parameters?.dispose();
    _dictionary?.dispose();
    _detector = null;
    _parameters = null;
    _dictionary = null;
    _grayscaleMat = null;
  }
}
