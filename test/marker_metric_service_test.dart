import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:spothole_app/services/marker_metric_service.dart';

void main() {
  late MarkerMetricService service;

  setUp(() {
    service = MarkerMetricService(
      config: const MarkerMetricConfig(
        widthCm: 100,
        heightCm: 100,
        minimumSidePx: 10,
        minimumAreaPx2: 100,
      ),
    );
  });

  tearDown(() => service.dispose());

  test('homografía identidad conserva los puntos', () {
    const points = [MetricPoint(12, 34), MetricPoint(56, 78)];
    final projected = MarkerMetricService.projectPointsWithMatrix(
      points,
      const [1, 0, 0, 0, 1, 0, 0, 0, 1],
    );

    expect(projected, isNotNull);
    expect(projected![0].x, closeTo(12, 1e-9));
    expect(projected[0].y, closeTo(34, 1e-9));
    expect(projected[1].x, closeTo(56, 1e-9));
    expect(projected[1].y, closeTo(78, 1e-9));
  });

  test('escalado conocido convierte píxeles a centímetros', () {
    final measurement = service.measureWithCorners(
      markerCorners: _square(100, 100, 200),
      boundingBox: const MetricBoundingBox(
        centerX: 200,
        centerY: 200,
        width: 100,
        height: 50,
      ),
      imageWidth: 400,
      imageHeight: 400,
    );

    expect(measurement, isNotNull);
    expect(measurement!.widthCm, closeTo(50, 1e-4));
    expect(measurement.heightCm, closeTo(25, 1e-4));
  });

  test('perspectiva simulada se rectifica al plano del marcador', () {
    const marker = [
      MetricPoint(100, 100),
      MetricPoint(300, 100),
      MetricPoint(200, 200),
      MetricPoint(66.6666667, 200),
    ];
    const box = MetricBoundingBox(
      centerX: 150,
      centerY: 140,
      width: 40,
      height: 40,
    );
    final expectedCorners = box.corners.map(_inversePerspective).toList();
    final expectedWidth =
        (MarkerMetricService.distance(expectedCorners[0], expectedCorners[1]) +
                MarkerMetricService.distance(
                  expectedCorners[3],
                  expectedCorners[2],
                )) /
            2;
    final expectedHeight =
        (MarkerMetricService.distance(expectedCorners[0], expectedCorners[3]) +
                MarkerMetricService.distance(
                  expectedCorners[1],
                  expectedCorners[2],
                )) /
            2;

    final measurement = service.measureWithCorners(
      markerCorners: marker,
      boundingBox: box,
      imageWidth: 400,
      imageHeight: 400,
    );

    expect(measurement, isNotNull);
    expect(measurement!.widthCm, closeTo(expectedWidth, 1e-3));
    expect(measurement.heightCm, closeTo(expectedHeight, 1e-3));
  });

  test('convierte puntos de imagen con una matriz proyectiva conocida', () {
    final projected = MarkerMetricService.projectPointsWithMatrix(
      const [MetricPoint(10, 20)],
      const [2, 0, 5, 0, 3, 7, 0, 0, 1],
    );

    expect(projected, isNotNull);
    expect(projected!.single.x, closeTo(25, 1e-9));
    expect(projected.single.y, closeTo(67, 1e-9));
  });

  test('calcula distancia euclidiana entre puntos', () {
    expect(
      MarkerMetricService.distance(
        const MetricPoint(0, 0),
        const MetricPoint(3, 4),
      ),
      5,
    );
  });

  test('calcula ancho, alto y área del rectángulo envolvente', () {
    final measurement = service.measureWithCorners(
      markerCorners: _square(50, 50, 100),
      boundingBox: const MetricBoundingBox(
        centerX: 100,
        centerY: 100,
        width: 20,
        height: 40,
      ),
      imageWidth: 200,
      imageHeight: 200,
    );

    expect(measurement, isNotNull);
    expect(measurement!.widthCm, closeTo(20, 1e-4));
    expect(measurement.heightCm, closeTo(40, 1e-4));
    expect(measurement.boundingBoxAreaCm2, closeTo(800, 1e-3));
  });

  test('rechaza un marcador demasiado pequeño o deformado', () {
    final tooSmall = service.measureWithCorners(
      markerCorners: _square(100, 100, 5),
      boundingBox: const MetricBoundingBox(
        centerX: 150,
        centerY: 150,
        width: 20,
        height: 20,
      ),
      imageWidth: 300,
      imageHeight: 300,
    );
    final deformed = service.measureWithCorners(
      markerCorners: const [
        MetricPoint(50, 50),
        MetricPoint(250, 50),
        MetricPoint(70, 60),
        MetricPoint(60, 60),
      ],
      boundingBox: const MetricBoundingBox(
        centerX: 150,
        centerY: 150,
        width: 20,
        height: 20,
      ),
      imageWidth: 300,
      imageHeight: 300,
    );

    expect(tooSmall, isNull);
    expect(deformed, isNull);
  });

  test('rechaza datos incompletos sin cuatro esquinas', () {
    final measurement = service.measureWithCorners(
      markerCorners: const [
        MetricPoint(50, 50),
        MetricPoint(150, 50),
        MetricPoint(150, 150),
      ],
      boundingBox: const MetricBoundingBox(
        centerX: 100,
        centerY: 100,
        width: 20,
        height: 20,
      ),
      imageWidth: 200,
      imageHeight: 200,
    );

    expect(measurement, isNull);
  });

  test('sin marcador aplica fallback sin medición métrica', () {
    final measurement = service.measureWithCorners(
      markerCorners: const [],
      boundingBox: const MetricBoundingBox(
        centerX: 100,
        centerY: 100,
        width: 20,
        height: 20,
      ),
      imageWidth: 200,
      imageHeight: 200,
    );

    expect(measurement, isNull);
  });

  test('detecta las cuatro esquinas de un marcador ArUco sintético', () {
    final marker = cv.arucoGenerateImageMarker(
      cv.PredefinedDictionaryType.DICT_6X6_250,
      0,
      200,
      1,
    );
    addTearDown(marker.dispose);
    final image = img.Image(width: 400, height: 400);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final markerBytes = marker.data;
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 200; x++) {
        final value = markerBytes[y * 200 + x];
        image.setPixelRgb(x + 100, y + 100, value, value, value);
      }
    }

    final measurement = service.detectAndMeasure(
      image: image,
      boundingBox: const MetricBoundingBox(
        centerX: 200,
        centerY: 200,
        width: 100,
        height: 100,
      ),
    );

    expect(measurement, isNotNull);
    expect(measurement!.markerId, 0);
    expect(measurement.widthCm, closeTo(50, 1));
    expect(measurement.heightCm, closeTo(50, 1));
  });

  test('perfil diagnóstico de preparación y detección ArUco', () {
    final marker = cv.arucoGenerateImageMarker(
      cv.PredefinedDictionaryType.DICT_6X6_250,
      0,
      200,
      1,
    );
    addTearDown(marker.dispose);
    final image = img.Image(width: 1280, height: 720);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final markerBytes = marker.data;
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 200; x++) {
        final value = markerBytes[y * 200 + x];
        image.setPixelRgb(x + 540, y + 260, value, value, value);
      }
    }

    final grayscaleSamples = <int>[];
    final detectionSamples = <int>[];
    for (var iteration = 0; iteration < 7; iteration++) {
      final profile = MarkerMetricProfile();
      final measurement = service.detectAndMeasure(
        image: image,
        boundingBox: const MetricBoundingBox(
          centerX: 640,
          centerY: 360,
          width: 100,
          height: 100,
        ),
        profile: profile,
      );
      expect(measurement, isNotNull);
      grayscaleSamples.add(profile.grayscalePreparationUs);
      detectionSamples.add(profile.arucoDetectionUs);
    }
    grayscaleSamples.sort();
    detectionSamples.sort();

    // ignore: avoid_print
    print(
      'ARUCO_BASELINE desktop=windows source=1280x720 iterations=7 '
      'grayscaleMedianUs=${grayscaleSamples[3]} '
      'detectionMedianUs=${detectionSamples[3]}',
    );
  });
}

List<MetricPoint> _square(double left, double top, double side) {
  return [
    MetricPoint(left, top),
    MetricPoint(left + side, top),
    MetricPoint(left + side, top + side),
    MetricPoint(left, top + side),
  ];
}

MetricPoint _inversePerspective(MetricPoint imagePoint) {
  final y = (100 - imagePoint.y) / (0.005 * imagePoint.y - 2);
  final x = (imagePoint.x * (0.005 * y + 1) - 100) / 2;
  return MetricPoint(x, y);
}
