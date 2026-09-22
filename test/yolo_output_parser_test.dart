import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spothole_app/services/yolo_output_parser.dart';

void main() {
  Float32List output({
    double x = 320,
    double y = 320,
    double width = 160,
    double height = 80,
    double confidence = 0.86,
  }) =>
      Float32List.fromList([x, y, width, height, confidence]);

  test('detección positiva con geometría válida nunca devuelve 0 × 0', () {
    final result = YoloOutputParser.parsePlanarXywhConfidence(
      output: output(),
      candidateCount: 1,
      imageWidth: 1280,
      imageHeight: 720,
      modelInputWidth: 640,
      modelInputHeight: 640,
    );

    expect(result, isNotNull);
    expect(result!.confidence, closeTo(0.86, 1e-5));
    expect(result.widthPx, greaterThan(0));
    expect(result.heightPx, greaterThan(0));
    expect(result.widthPx, closeTo(320, 1e-6));
    expect(result.heightPx, closeTo(90, 1e-6));
  });

  test('lee cada atributo del mismo candidato en [1,5,N]', () {
    final planar = Float32List.fromList([
      100,
      300,
      110,
      310,
      20,
      120,
      10,
      60,
      0.55,
      0.91,
    ]);
    final result = YoloOutputParser.parsePlanarXywhConfidence(
      output: planar,
      candidateCount: 2,
      imageWidth: 640,
      imageHeight: 640,
      modelInputWidth: 640,
      modelInputHeight: 640,
    );

    expect(result!.candidateIndex, 1);
    expect(result.modelCenterX, 300);
    expect(result.modelCenterY, 310);
    expect(result.modelWidth, 120);
    expect(result.modelHeight, 60);
  });

  test('salida normalizada se convierte primero al espacio 640 × 640', () {
    final result = YoloOutputParser.parsePlanarXywhConfidence(
      output: output(x: 0.5, y: 0.5, width: 0.25, height: 0.15625),
      candidateCount: 1,
      imageWidth: 1280,
      imageHeight: 720,
      modelInputWidth: 640,
      modelInputHeight: 640,
      coordinateSpace: YoloCoordinateSpace.normalized,
    );

    expect(result, isNotNull);
    expect(result!.modelCenterX, 320);
    expect(result.modelCenterY, 320);
    expect(result.modelWidth, 160);
    expect(result.modelHeight, 100);
    expect(result.widthPx, 320);
    expect(result.heightPx, 112.5);
  });

  test('tensor [1,5,8400] no mezcla canales con indexado i × 5', () {
    const candidates = 8400;
    final planar = Float32List(candidates * 5);
    const selected = 7220;
    planar[selected] = 0.5;
    planar[candidates + selected] = 0.5;
    planar[2 * candidates + selected] = 0.25;
    planar[3 * candidates + selected] = 0.15625;
    planar[4 * candidates + selected] = 0.9;
    const wrongBase = selected * 5;
    planar[wrongBase] = 99;
    planar[wrongBase + 1] = 98;
    planar[wrongBase + 2] = 97;
    planar[wrongBase + 3] = 96;
    planar[wrongBase + 4] = 0.1;

    final result = YoloOutputParser.parsePlanarXywhConfidence(
      output: planar,
      candidateCount: candidates,
      imageWidth: 1280,
      imageHeight: 720,
      modelInputWidth: 640,
      modelInputHeight: 640,
      coordinateSpace: YoloCoordinateSpace.normalized,
    );

    expect(result!.candidateIndex, selected);
    expect(result.modelWidth, 160);
    expect(result.modelHeight, 100);
    expect(result.confidence, closeTo(0.9, 1e-6));
  });

  test('protección geométrica rechaza cajas absurdamente pequeñas', () {
    final result = YoloOutputParser.parsePlanarXywhConfidence(
      output: output(width: 0.001, height: 0.001),
      candidateCount: 1,
      imageWidth: 1280,
      imageHeight: 720,
      modelInputWidth: 640,
      modelInputHeight: 640,
      coordinateSpace: YoloCoordinateSpace.normalized,
    );

    expect(result, isNull);
  });

  test('descarta confianza alta con geometría inválida', () {
    final planar = Float32List.fromList([
      100,
      300,
      110,
      310,
      0,
      120,
      0,
      60,
      0.99,
      0.91,
    ]);
    final result = YoloOutputParser.parsePlanarXywhConfidence(
      output: planar,
      candidateCount: 2,
      imageWidth: 640,
      imageHeight: 640,
      modelInputWidth: 640,
      modelInputHeight: 640,
    );

    expect(result!.candidateIndex, 1);
    expect(result.widthPx, 120);
    expect(result.heightPx, 60);
  });

  for (final rotation in [0, 90, 180, 270]) {
    test('escala con dimensiones orientadas para rotación $rotation°', () {
      final swaps = rotation == 90 || rotation == 270;
      final result = YoloOutputParser.parsePlanarXywhConfidence(
        output: output(width: 64, height: 128),
        candidateCount: 1,
        imageWidth: swaps ? 720 : 1280,
        imageHeight: swaps ? 1280 : 720,
        modelInputWidth: 640,
        modelInputHeight: 640,
      );

      expect(result!.widthPx, closeTo(swaps ? 72 : 128, 1e-6));
      expect(result.heightPx, closeTo(swaps ? 256 : 144, 1e-6));
    });
  }
}
