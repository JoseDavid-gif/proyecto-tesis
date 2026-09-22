import 'package:flutter/foundation.dart';

enum YoloCoordinateSpace { modelPixels, normalized }

class YoloDetectionPixels {
  const YoloDetectionPixels({
    required this.candidateIndex,
    required this.confidence,
    required this.modelCenterX,
    required this.modelCenterY,
    required this.modelWidth,
    required this.modelHeight,
    required this.centerXPx,
    required this.centerYPx,
    required this.widthPx,
    required this.heightPx,
  });

  final int candidateIndex;
  final double confidence;
  final double modelCenterX;
  final double modelCenterY;
  final double modelWidth;
  final double modelHeight;
  final double centerXPx;
  final double centerYPx;
  final double widthPx;
  final double heightPx;
}

class YoloOutputParser {
  const YoloOutputParser._();

  static YoloDetectionPixels? parsePlanarXywhConfidence({
    required Float32List output,
    required int candidateCount,
    required int imageWidth,
    required int imageHeight,
    required int modelInputWidth,
    required int modelInputHeight,
    double confidenceThreshold = 0.5,
    YoloCoordinateSpace coordinateSpace = YoloCoordinateSpace.modelPixels,
    double minimumModelDimension = 2,
  }) {
    if (candidateCount <= 0 || output.length != candidateCount * 5) {
      throw ArgumentError('La salida debe tener forma plana [1,5,N].');
    }
    if (imageWidth <= 0 ||
        imageHeight <= 0 ||
        modelInputWidth <= 0 ||
        modelInputHeight <= 0) {
      throw ArgumentError('Las dimensiones deben ser positivas.');
    }

    var bestIndex = -1;
    var bestConfidence = confidenceThreshold;
    var bestRawX = 0.0;
    var bestRawY = 0.0;
    var bestRawWidth = 0.0;
    var bestRawHeight = 0.0;

    for (var index = 0; index < candidateCount; index++) {
      final confidence = output[4 * candidateCount + index];
      final x = output[index];
      final y = output[candidateCount + index];
      final width = output[2 * candidateCount + index];
      final height = output[3 * candidateCount + index];
      final validGeometry = x.isFinite &&
          y.isFinite &&
          width.isFinite &&
          height.isFinite &&
          width > 0 &&
          height > 0;
      if (!confidence.isFinite ||
          confidence < bestConfidence ||
          !validGeometry) {
        continue;
      }
      bestIndex = index;
      bestConfidence = confidence;
      bestRawX = x;
      bestRawY = y;
      bestRawWidth = width;
      bestRawHeight = height;
    }

    if (bestIndex < 0) return null;

    final normalized = coordinateSpace == YoloCoordinateSpace.normalized;
    final bestX = normalized ? bestRawX * modelInputWidth : bestRawX;
    final bestY = normalized ? bestRawY * modelInputHeight : bestRawY;
    final bestWidth =
        normalized ? bestRawWidth * modelInputWidth : bestRawWidth;
    final bestHeight =
        normalized ? bestRawHeight * modelInputHeight : bestRawHeight;
    if (bestWidth < minimumModelDimension ||
        bestHeight < minimumModelDimension ||
        bestX < 0 ||
        bestY < 0 ||
        bestX > modelInputWidth ||
        bestY > modelInputHeight) {
      return null;
    }

    final widthPx = scaleModelDimension(
      modelValue: bestWidth,
      originalDimension: imageWidth,
      modelInputDimension: modelInputWidth,
    );
    final heightPx = scaleModelDimension(
      modelValue: bestHeight,
      originalDimension: imageHeight,
      modelInputDimension: modelInputHeight,
    );
    final centerXPx = scaleModelDimension(
      modelValue: bestX,
      originalDimension: imageWidth,
      modelInputDimension: modelInputWidth,
    );
    final centerYPx = scaleModelDimension(
      modelValue: bestY,
      originalDimension: imageHeight,
      modelInputDimension: modelInputHeight,
    );
    if (!widthPx.isFinite ||
        !heightPx.isFinite ||
        widthPx <= 0 ||
        heightPx <= 0) {
      return null;
    }

    if (kDebugMode) {
      debugPrint(
        'YOLO_POSITIVE outputShape=[1,5,$candidateCount] N=$candidateCount '
        'layout=channel-major coordinates=${coordinateSpace.name} '
        'index=$bestIndex '
        'confidence=${bestConfidence.toStringAsFixed(4)} '
        'rawX=${bestRawX.toStringAsFixed(3)} '
        'rawY=${bestRawY.toStringAsFixed(3)} '
        'rawW=${bestRawWidth.toStringAsFixed(3)} '
        'rawH=${bestRawHeight.toStringAsFixed(3)} '
        'modelX=${bestX.toStringAsFixed(3)} '
        'modelY=${bestY.toStringAsFixed(3)} '
        'modelW=${bestWidth.toStringAsFixed(3)} '
        'modelH=${bestHeight.toStringAsFixed(3)} '
        'image=${imageWidth}x$imageHeight '
        'widthPx=${widthPx.toStringAsFixed(3)} '
        'heightPx=${heightPx.toStringAsFixed(3)}',
      );
    }

    return YoloDetectionPixels(
      candidateIndex: bestIndex,
      confidence: bestConfidence,
      modelCenterX: bestX,
      modelCenterY: bestY,
      modelWidth: bestWidth,
      modelHeight: bestHeight,
      centerXPx: centerXPx,
      centerYPx: centerYPx,
      widthPx: widthPx,
      heightPx: heightPx,
    );
  }

  static double scaleModelDimension({
    required double modelValue,
    required int originalDimension,
    required int modelInputDimension,
  }) {
    if (modelInputDimension <= 0) {
      throw ArgumentError.value(
        modelInputDimension,
        'modelInputDimension',
        'Debe ser mayor que cero',
      );
    }
    return modelValue * originalDimension / modelInputDimension;
  }
}
