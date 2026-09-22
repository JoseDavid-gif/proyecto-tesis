import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spothole_app/models/bache_model.dart';
import 'package:spothole_app/services/arcore_depth_frame.dart';
import 'package:spothole_app/services/arcore_metric_estimator.dart';
import 'package:spothole_app/services/ia_service.dart';
import 'package:spothole_app/services/marker_metric_service.dart';

class _AcceptedEstimator extends ArCoreMetricEstimator {
  const _AcceptedEstimator();

  @override
  ArCoreMetricResult estimate({
    required ArCoreDepthFrame frame,
    required MetricBoundingBox orientedBoundingBox,
  }) {
    return const ArCoreMetricResult.accepted(
      ArCoreMetricMeasurement(
        widthCm: 35.55,
        heightCm: 55.33,
        validSamples: 80,
        planeInliers: 70,
        usedRawDepth: true,
      ),
    );
  }
}

void main() {
  test('resultado ARCore aceptado conserva centímetros, método y severidad',
      () {
    final service =
        IAService(arCoreMetricEstimator: const _AcceptedEstimator());
    final bytes = Uint8List(4);
    final depth = ArCoreDepthImage(
      width: 1,
      height: 1,
      timestampNs: 1,
      bytes: bytes,
      rowStride: 2,
      pixelStride: 2,
    );
    final frame = ArCoreDepthFrame(
      width: 2,
      height: 2,
      timestampNs: 1,
      rotationDegrees: 0,
      yBytes: bytes,
      uBytes: bytes,
      vBytes: bytes,
      yRowStride: 2,
      uRowStride: 1,
      vRowStride: 1,
      uPixelStride: 1,
      vPixelStride: 1,
      fx: 1,
      fy: 1,
      cx: 1,
      cy: 1,
      imageToTexture: const [1, 0, 0, 0, 1, 0],
      cameraPose: const [
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
      ],
      depth: depth,
      rawDepth: true,
    );

    final result = service.medirResultadoConDepth(frame, {
      'centroXPx': 100.0,
      'centroYPx': 100.0,
      'anchoPx': 102.9,
      'altoPx': 113.9,
      'anchoCm': null,
      'altoCm': null,
      'areaCm2': null,
      'severidad': 'No determinada',
      'metodoMedicion': Bache.metodoSinMedicion,
    });

    expect(result['anchoCm'], 35.55);
    expect(result['altoCm'], 55.33);
    expect(result['areaCm2'], 1966.98);
    expect(result['metodoMedicion'], Bache.metodoArCoreDepth);
    expect(result['severidad'], 'Severo');
    service.dispose();
  });
}
