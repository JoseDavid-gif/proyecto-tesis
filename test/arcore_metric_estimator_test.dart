import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spothole_app/services/arcore_depth_frame.dart';
import 'package:spothole_app/services/arcore_metric_estimator.dart';
import 'package:spothole_app/services/marker_metric_service.dart';

void main() {
  const box = MetricBoundingBox(
    centerX: 320,
    centerY: 240,
    width: 160,
    height: 100,
  );

  test('transformación CPU a Depth respeta textura normalizada', () {
    final frame = syntheticFrame();
    final texture = ArCoreMetricEstimator.sourceToTexture(
      frame,
      const MetricPoint(160, 120),
    );

    expect(texture, isNotNull);
    expect(texture!.x, closeTo(0.25, 1e-9));
    expect(texture.y, closeTo(0.25, 1e-9));
  });

  test('rotación YOLO 90 grados vuelve a coordenadas CPU', () {
    final frame = syntheticFrame(rotationDegrees: 90);
    final source = ArCoreMetricEstimator.orientedToSource(
      frame,
      const MetricPoint(100, 200),
    );

    expect(source.x, 200);
    expect(source.y, 379);
  });

  test('plano sintético reconstruye ancho y alto métricos', () {
    final result = const ArCoreMetricEstimator().estimate(
      frame: syntheticFrame(),
      orientedBoundingBox: box,
    );

    expect(result.rejectionReason, isNull);
    expect(result.measurement, isNotNull);
    expect(result.measurement!.widthCm, closeTo(32, 0.7));
    expect(result.measurement!.heightCm, closeTo(20, 0.7));
    expect(result.measurement!.boundingBoxAreaCm2, closeTo(640, 30));
    expect(result.measurement!.planeInliers, greaterThanOrEqualTo(30));
  });

  test('RANSAC rechaza outliers sin alterar el plano dominante', () {
    final result = const ArCoreMetricEstimator().estimate(
      frame: syntheticFrame(withOutliers: true),
      orientedBoundingBox: box,
    );

    expect(result.measurement, isNotNull);
    expect(result.measurement!.widthCm, closeTo(32, 1));
    expect(
      result.measurement!.planeInliers,
      lessThan(result.measurement!.validSamples),
    );
  });

  test('Depth cero no produce centímetros', () {
    final result = const ArCoreMetricEstimator().estimate(
      frame: syntheticFrame(depthMillimeters: 0),
      orientedBoundingBox: box,
    );

    expect(result.measurement, isNull);
    expect(result.rejectionReason, 'insufficient_depth_samples');
  });

  test('intrínsecos inválidos rechazan la medición', () {
    final source = syntheticFrame();
    final frame = ArCoreDepthFrame(
      width: source.width,
      height: source.height,
      timestampNs: source.timestampNs,
      rotationDegrees: source.rotationDegrees,
      yBytes: source.yBytes,
      uBytes: source.uBytes,
      vBytes: source.vBytes,
      yRowStride: source.yRowStride,
      uRowStride: source.uRowStride,
      vRowStride: source.vRowStride,
      uPixelStride: source.uPixelStride,
      vPixelStride: source.vPixelStride,
      fx: 0,
      fy: source.fy,
      cx: source.cx,
      cy: source.cy,
      imageToTexture: source.imageToTexture,
      cameraPose: source.cameraPose,
      depth: source.depth,
      confidence: source.confidence,
      rawDepth: source.rawDepth,
    );

    final result = const ArCoreMetricEstimator().estimate(
      frame: frame,
      orientedBoundingBox: box,
    );

    expect(result.measurement, isNull);
    expect(result.rejectionReason, 'invalid_geometry');
  });

  test('confianza Raw Depth insuficiente rechaza captura', () {
    final result = const ArCoreMetricEstimator().estimate(
      frame: syntheticFrame(confidence: 30),
      orientedBoundingBox: box,
    );

    expect(result.measurement, isNull);
    expect(result.rejectionReason, 'insufficient_depth_samples');
  });

  test('Depth completo funciona como fallback sin mapa de confianza', () {
    final result = const ArCoreMetricEstimator().estimate(
      frame: syntheticFrame(rawDepth: false),
      orientedBoundingBox: box,
    );

    expect(result.measurement, isNotNull);
    expect(result.measurement!.usedRawDepth, isFalse);
  });

  test('Raw Depth disperso utiliza Full Depth del mismo frame', () {
    final result = const ArCoreMetricEstimator().estimate(
      frame: syntheticFrame(
        depthMillimeters: 0,
        fallbackDepthMillimeters: 1000,
      ),
      orientedBoundingBox: box,
    );

    expect(result.measurement, isNotNull);
    expect(result.measurement!.usedRawDepth, isFalse);
    expect(result.measurement!.widthCm, closeTo(32, 0.7));
  });
}

ArCoreDepthFrame syntheticFrame({
  int rotationDegrees = 0,
  int depthMillimeters = 1000,
  int confidence = 255,
  bool rawDepth = true,
  bool withOutliers = false,
  int? fallbackDepthMillimeters,
}) {
  const width = 640;
  const height = 480;
  final depthBytes = Uint8List(width * height * 2);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = withOutliers && (x + y) % 11 == 0
          ? depthMillimeters * 2
          : depthMillimeters;
      final offset = (y * width + x) * 2;
      depthBytes[offset] = value & 0xff;
      depthBytes[offset + 1] = (value >> 8) & 0xff;
    }
  }
  final confidenceBytes = Uint8List(width * height)
    ..fillRange(0, width * height, confidence);
  final depth = ArCoreDepthImage(
    width: width,
    height: height,
    timestampNs: 20,
    bytes: depthBytes,
    rowStride: width * 2,
    pixelStride: 2,
  );
  ArCoreDepthImage? fallbackDepth;
  if (fallbackDepthMillimeters != null) {
    final fallbackBytes = Uint8List(width * height * 2);
    for (var offset = 0; offset < fallbackBytes.length; offset += 2) {
      fallbackBytes[offset] = fallbackDepthMillimeters & 0xff;
      fallbackBytes[offset + 1] = (fallbackDepthMillimeters >> 8) & 0xff;
    }
    fallbackDepth = ArCoreDepthImage(
      width: width,
      height: height,
      timestampNs: 20,
      bytes: fallbackBytes,
      rowStride: width * 2,
      pixelStride: 2,
    );
  }
  return ArCoreDepthFrame(
    width: width,
    height: height,
    timestampNs: 20,
    rotationDegrees: rotationDegrees,
    yBytes: Uint8List(width * height),
    uBytes: Uint8List(width * height ~/ 4),
    vBytes: Uint8List(width * height ~/ 4),
    yRowStride: width,
    uRowStride: width ~/ 2,
    vRowStride: width ~/ 2,
    uPixelStride: 1,
    vPixelStride: 1,
    fx: 500,
    fy: 500,
    cx: 320,
    cy: 240,
    imageToTexture: const [0, 0, 1, 0, 0, 1],
    cameraPose: const [
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      0,
      1,
    ],
    depth: depth,
    confidence: rawDepth
        ? ArCoreDepthImage(
            width: width,
            height: height,
            timestampNs: 20,
            bytes: confidenceBytes,
            rowStride: width,
            pixelStride: 1,
          )
        : null,
    fallbackDepth: fallbackDepth,
    rawDepth: rawDepth,
  );
}
