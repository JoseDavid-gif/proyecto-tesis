import 'dart:io';
import 'dart:developer' as developer;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

import '../models/bache_model.dart';
import 'marker_metric_service.dart';
import 'arcore_depth_frame.dart';
import 'arcore_metric_estimator.dart';
import 'yolo_output_parser.dart';

class IAService {
  IAService({
    MarkerMetricService? markerMetricService,
    ArCoreMetricEstimator? arCoreMetricEstimator,
    this.profilingEnabled = !kReleaseMode,
    this.onProfile,
  })  : _markerMetricService = markerMetricService ?? MarkerMetricService(),
        _arCoreMetricEstimator =
            arCoreMetricEstimator ?? const ArCoreMetricEstimator();

  final MarkerMetricService _markerMetricService;
  final ArCoreMetricEstimator _arCoreMetricEstimator;
  final bool profilingEnabled;
  final ValueChanged<InferenceProfile>? onProfile;
  Interpreter? _interpreter;
  Tensor? _inputTensor;
  Tensor? _outputTensor;
  Float32List? _inputBuffer;
  Uint8List? _inputBytes;
  Int32List? _resizeX;
  Int32List? _resizeY;
  int _resizeSourceWidth = 0;
  int _resizeSourceHeight = 0;
  int _inputWidth = 0;
  int _inputHeight = 0;
  int _outputCandidates = 0;

  Future<void> cargarModelo() async {
    if (_interpreter != null) return;

    final interpreter =
        await Interpreter.fromAsset('assets/model/spothole.tflite');
    try {
      final input = interpreter.getInputTensor(0);
      final output = interpreter.getOutputTensor(0);

      debugPrint(
        'TFLite input: shape=${input.shape}, type=${input.type}, '
        'scale=${input.params.scale}, zeroPoint=${input.params.zeroPoint}',
      );
      debugPrint(
        'TFLite output: shape=${output.shape}, type=${output.type}, '
        'scale=${output.params.scale}, zeroPoint=${output.params.zeroPoint}',
      );

      if (input.type != TensorType.float32 ||
          input.shape.length != 4 ||
          input.shape[0] != 1 ||
          input.shape[3] != 3) {
        throw StateError(
          'Entrada TFLite no compatible: ${input.shape}, ${input.type}',
        );
      }
      if (output.type != TensorType.float32 ||
          output.shape.length != 3 ||
          output.shape[0] != 1 ||
          output.shape[1] != 5) {
        throw StateError(
          'Salida YOLO no compatible: ${output.shape}, ${output.type}',
        );
      }

      _inputHeight = input.shape[1];
      _inputWidth = input.shape[2];
      _outputCandidates = output.shape[2];
      _inputTensor = input;
      _outputTensor = output;
      _inputBuffer = Float32List(input.numElements());
      _inputBytes = _inputBuffer!.buffer.asUint8List();
      _interpreter = interpreter;
    } catch (_) {
      interpreter.close();
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> detectarBache(File imagen) async {
    await cargarModelo();

    final bytes = await imagen.readAsBytes();
    final imgOriginal = img.decodeImage(bytes);
    if (imgOriginal == null) return null;

    return _ejecutarModelo(imgOriginal);
  }

  Future<Map<String, dynamic>?> detectarDesdeFrame(
    CameraImage cameraImage, {
    int rotationDegrees = 0,
    int? frameAcceptedAtUs,
  }) async {
    await cargarModelo();

    final profile = profilingEnabled ? InferenceProfile() : null;
    final totalWatch = profile == null ? null : (Stopwatch()..start());
    profile
      ?..sourceWidth = cameraImage.width
      ..sourceHeight = cameraImage.height
      ..rotationDegrees = rotationDegrees
      ..rssBeforeBytes = ProcessInfo.currentRss;
    if (profile != null && frameAcceptedAtUs != null) {
      profile.frameAdmissionUs = developer.Timeline.now - frameAcceptedAtUs;
    }

    try {
      final rotationWatch = profile == null ? null : (Stopwatch()..start());
      final swapsDimensions = rotationDegrees == 90 || rotationDegrees == 270;
      final orientedWidth =
          swapsDimensions ? cameraImage.height : cameraImage.width;
      final orientedHeight =
          swapsDimensions ? cameraImage.width : cameraImage.height;
      rotationWatch?.stop();
      profile?.rotationUs = rotationWatch?.elapsedMicroseconds ?? 0;

      final resizeWatch = profile == null ? null : (Stopwatch()..start());
      _prepareResizeMaps(orientedWidth, orientedHeight);
      resizeWatch?.stop();
      profile?.resizeUs = resizeWatch?.elapsedMicroseconds ?? 0;

      final conversionWatch = profile == null ? null : (Stopwatch()..start());
      llenarTensorDesdeYuv420(
        destination: _inputBuffer!,
        imageWidth: cameraImage.width,
        imageHeight: cameraImage.height,
        yBytes: cameraImage.planes[0].bytes,
        uBytes: cameraImage.planes[1].bytes,
        vBytes: cameraImage.planes[2].bytes,
        yRowStride: cameraImage.planes[0].bytesPerRow,
        uRowStride: cameraImage.planes[1].bytesPerRow,
        vRowStride: cameraImage.planes[2].bytesPerRow,
        uPixelStride: cameraImage.planes[1].bytesPerPixel ?? 1,
        vPixelStride: cameraImage.planes[2].bytesPerPixel ?? 1,
        rotationDegrees: rotationDegrees,
        scaleX: _resizeX!,
        scaleY: _resizeY!,
      );
      conversionWatch?.stop();
      profile?.yuvToRgbUs = conversionWatch?.elapsedMicroseconds ?? 0;

      return _runPreparedInput(
        imageWidth: orientedWidth,
        imageHeight: orientedHeight,
        markerImageProvider: () {
          var image = _convertirYUV420AImagen(cameraImage);
          if (rotationDegrees != 0) {
            image = img.copyRotate(image, angle: rotationDegrees);
          }
          return image;
        },
        profile: profile,
      );
    } finally {
      totalWatch?.stop();
      if (profile != null) {
        profile.totalUs = totalWatch!.elapsedMicroseconds;
        profile.rssAfterBytes = ProcessInfo.currentRss;
        onProfile?.call(profile);
        debugPrint(profile.toLogLine());
      }
    }
  }

  Future<Map<String, dynamic>?> detectarDesdeArCoreFrame(
    ArCoreDepthFrame frame, {
    int? frameAcceptedAtUs,
  }) async {
    await cargarModelo();

    final profile = profilingEnabled ? InferenceProfile() : null;
    final totalWatch = profile == null ? null : (Stopwatch()..start());
    profile
      ?..sourceWidth = frame.width
      ..sourceHeight = frame.height
      ..rotationDegrees = frame.rotationDegrees
      ..rssBeforeBytes = ProcessInfo.currentRss;
    if (profile != null && frameAcceptedAtUs != null) {
      profile.frameAdmissionUs = developer.Timeline.now - frameAcceptedAtUs;
    }

    try {
      _prepareResizeMaps(frame.orientedWidth, frame.orientedHeight);
      final conversionWatch = profile == null ? null : (Stopwatch()..start());
      llenarTensorDesdeYuv420(
        destination: _inputBuffer!,
        imageWidth: frame.width,
        imageHeight: frame.height,
        yBytes: frame.yBytes,
        uBytes: frame.uBytes,
        vBytes: frame.vBytes,
        yRowStride: frame.yRowStride,
        uRowStride: frame.uRowStride,
        vRowStride: frame.vRowStride,
        uPixelStride: frame.uPixelStride,
        vPixelStride: frame.vPixelStride,
        rotationDegrees: frame.rotationDegrees,
        scaleX: _resizeX!,
        scaleY: _resizeY!,
      );
      conversionWatch?.stop();
      profile?.yuvToRgbUs = conversionWatch?.elapsedMicroseconds ?? 0;

      return _runPreparedInput(
        imageWidth: frame.orientedWidth,
        imageHeight: frame.orientedHeight,
        markerImageProvider: () => IAService.convertirFrameArCoreAImagen(frame),
        depthFrame: frame,
        profile: profile,
      );
    } finally {
      totalWatch?.stop();
      if (profile != null) {
        profile.totalUs = totalWatch!.elapsedMicroseconds;
        profile.rssAfterBytes = ProcessInfo.currentRss;
        onProfile?.call(profile);
        debugPrint(profile.toLogLine());
      }
    }
  }

  static int calcularRotacionFrame({
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
    required CameraLensDirection lensDirection,
  }) {
    final deviceDegrees = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

    if (lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + deviceDegrees) % 360;
    }
    return (sensorOrientation - deviceDegrees + 360) % 360;
  }

  Map<String, dynamic>? _ejecutarModelo(
    img.Image imgOriginal, {
    InferenceProfile? profile,
  }) {
    final resizeWatch = profile == null ? null : (Stopwatch()..start());
    _prepareResizeMaps(imgOriginal.width, imgOriginal.height);
    resizeWatch?.stop();
    profile?.resizeUs = resizeWatch?.elapsedMicroseconds ?? 0;

    final tensorWatch = profile == null ? null : (Stopwatch()..start());
    llenarTensorRgbRedimensionado(
      imgOriginal,
      _inputBuffer!,
      _resizeX!,
      _resizeY!,
    );
    tensorWatch?.stop();
    profile?.tensorConstructionUs = tensorWatch?.elapsedMicroseconds ?? 0;

    return _runPreparedInput(
      imageWidth: imgOriginal.width,
      imageHeight: imgOriginal.height,
      markerImageProvider: () => imgOriginal,
      profile: profile,
    );
  }

  Map<String, dynamic>? _runPreparedInput({
    required int imageWidth,
    required int imageHeight,
    required img.Image Function() markerImageProvider,
    ArCoreDepthFrame? depthFrame,
    InferenceProfile? profile,
  }) {
    final inputCopyWatch = profile == null ? null : (Stopwatch()..start());
    _inputTensor!.data = _inputBytes!;
    inputCopyWatch?.stop();
    profile?.tensorConstructionUs += inputCopyWatch?.elapsedMicroseconds ?? 0;

    final inferenceWatch = profile == null ? null : (Stopwatch()..start());
    _interpreter!.invoke();
    final outputBytes = _outputTensor!.data;
    final output = Float32List.view(
      outputBytes.buffer,
      outputBytes.offsetInBytes,
      _outputTensor!.numElements(),
    );
    inferenceWatch?.stop();
    profile?.tfliteUs = inferenceWatch?.elapsedMicroseconds ?? 0;

    final postprocessWatch = profile == null ? null : (Stopwatch()..start());
    final resultado = _procesarOutput(
      output,
      imageWidth,
      imageHeight,
      _inputWidth,
      _inputHeight,
    );
    postprocessWatch?.stop();
    profile?.postprocessUs = postprocessWatch?.elapsedMicroseconds ?? 0;
    profile?.potholeDetected = resultado != null;
    if (resultado == null) return null;

    profile?.markerAttempted = true;
    final markerProfile = profile == null ? null : MarkerMetricProfile();
    final markerImageWatch = profile == null ? null : (Stopwatch()..start());
    final markerImage = markerImageProvider();
    markerImageWatch?.stop();
    profile?.markerImagePreparationUs =
        markerImageWatch?.elapsedMicroseconds ?? 0;
    final medicion = _markerMetricService.detectAndMeasure(
      image: markerImage,
      boundingBox: MetricBoundingBox(
        centerX: resultado['centroXPx'],
        centerY: resultado['centroYPx'],
        width: resultado['anchoPx'],
        height: resultado['altoPx'],
      ),
      profile: markerProfile,
    );
    if (profile != null && markerProfile != null) {
      profile
        ..grayscalePreparationUs = markerProfile.grayscalePreparationUs
        ..arucoDetectionUs = markerProfile.arucoDetectionUs
        ..homographyUs = markerProfile.homographyUs
        ..metricCalculationUs = markerProfile.metricCalculationUs
        ..markerFound = markerProfile.markerFound
        ..markerValid = markerProfile.markerValid;
    }
    if (medicion == null && depthFrame != null) {
      return medirResultadoConDepth(
        depthFrame,
        resultado,
        profile: profile,
      );
    }
    if (medicion == null) {
      if (kDebugMode) {
        debugPrint('METRIC_ESTIMATION_REJECTED reason=depth_unavailable');
      }
      return resultado;
    }

    resultado['anchoCm'] = double.parse(medicion.widthCm.toStringAsFixed(2));
    resultado['altoCm'] = double.parse(medicion.heightCm.toStringAsFixed(2));
    resultado['areaCm2'] =
        double.parse(medicion.boundingBoxAreaCm2.toStringAsFixed(2));
    resultado['severidad'] = Bache.calcularSeveridad(
      medicion.boundingBoxAreaCm2,
    );
    resultado['referenciaMetricaValida'] = true;
    resultado['metodoMedicion'] = Bache.metodoAruco;
    resultado['marcadorId'] = medicion.markerId;
    resultado['marcadorAnchoCm'] = _markerMetricService.config.widthCm;
    resultado['marcadorAltoCm'] = _markerMetricService.config.heightCm;
    return resultado;
  }

  Map<String, dynamic> medirResultadoConDepth(
    ArCoreDepthFrame depthFrame,
    Map<String, dynamic> stableResult, {
    InferenceProfile? profile,
  }) {
    final resultado = Map<String, dynamic>.from(stableResult);
    debugPrint(
      'SPOTHOLE_COORD bboxCpu=${resultado['centroXPx']},'
      '${resultado['centroYPx']},${resultado['anchoPx']}x'
      '${resultado['altoPx']}',
    );
    final metricWatch = profile == null ? null : (Stopwatch()..start());
    final depthResult = _arCoreMetricEstimator.estimate(
      frame: depthFrame,
      orientedBoundingBox: MetricBoundingBox(
        centerX: resultado['centroXPx'],
        centerY: resultado['centroYPx'],
        width: resultado['anchoPx'],
        height: resultado['altoPx'],
      ),
    );
    for (final attempt in depthResult.attempts) {
      final depthBox = attempt.depthBoundingBox;
      final depthBoxText = depthBox == null
          ? 'invalid'
          : '${depthBox.centerX.toStringAsFixed(1)},'
              '${depthBox.centerY.toStringAsFixed(1)},'
              '${depthBox.width.toStringAsFixed(1)}x'
              '${depthBox.height.toStringAsFixed(1)}';
      debugPrint(
        'SPOTHOLE_COORD cpu=${depthFrame.width}x${depthFrame.height} '
        'yolo=${_inputWidth}x$_inputHeight '
        'depth=${depthFrame.depth.width}x${depthFrame.depth.height} '
        'rotation=${depthFrame.rotationDegrees} bboxDepth=$depthBoxText',
      );
      debugPrint(
        'SPOTHOLE_DEPTH mode=${attempt.depthMode} '
        'samplesTotal=${attempt.candidateSamples} '
        'mapped=${attempt.mappedDepthSamples} '
        'valid=${attempt.positiveDepthSamples} '
        'confident=${attempt.confidentDepthSamples} '
        'medianMeters=${attempt.medianDepthMeters} '
        'minMeters=${attempt.minimumDepthMeters} '
        'maxMeters=${attempt.maximumDepthMeters}',
      );
      debugPrint(
        'SPOTHOLE_PLANE candidateSamples=${attempt.candidateSamples} '
        'valid3DPoints=${attempt.valid3DPoints}',
      );
    }
    metricWatch?.stop();
    profile?.depthMetricUs = metricWatch?.elapsedMicroseconds ?? 0;
    final depthMeasurement = depthResult.measurement;
    if (depthMeasurement != null) {
      profile
        ?..depthValidSamples = depthMeasurement.validSamples
        ..groundPlaneInliers = depthMeasurement.planeInliers;
      resultado['anchoCm'] =
          double.parse(depthMeasurement.widthCm.toStringAsFixed(2));
      resultado['altoCm'] =
          double.parse(depthMeasurement.heightCm.toStringAsFixed(2));
      resultado['areaCm2'] = double.parse(
        depthMeasurement.boundingBoxAreaCm2.toStringAsFixed(2),
      );
      resultado['severidad'] = Bache.calcularSeveridad(
        depthMeasurement.boundingBoxAreaCm2,
      );
      resultado['metodoMedicion'] = Bache.metodoArCoreDepth;
      resultado['profundidadRaw'] = depthMeasurement.usedRawDepth;
      debugPrint(
        'SPOTHOLE_RANSAC inputPoints=${depthMeasurement.validSamples} '
        'inliers=${depthMeasurement.planeInliers} '
        'ratio=${(depthMeasurement.planeInliers / depthMeasurement.validSamples).toStringAsFixed(3)}',
      );
      debugPrint(
        'SPOTHOLE_METRIC widthCm=${resultado['anchoCm']} '
        'heightCm=${resultado['altoCm']} areaCm2=${resultado['areaCm2']}',
      );
      return resultado;
    }
    final lastAttempt =
        depthResult.attempts.isEmpty ? null : depthResult.attempts.last;
    final rejectionReason = switch (depthResult.rejectionReason) {
      'insufficient_depth_samples' when lastAttempt?.mappedDepthSamples == 0 =>
        'invalid_coordinate_transform',
      'insufficient_depth_samples'
          when (lastAttempt?.positiveDepthSamples ?? 0) > 0 &&
              lastAttempt?.confidentDepthSamples == 0 =>
        'low_depth_confidence',
      'insufficient_depth_samples' => 'not_enough_depth_samples',
      'unstable_ground_plane' => 'ransac_failed',
      'ground_plane_not_horizontal' => 'invalid_ground_plane',
      'ray_plane_intersection' => 'ray_plane_failed',
      final reason? => reason,
      _ => 'otro_motivo_real',
    };
    resultado['motivoRechazoMetrico'] = rejectionReason;
    debugPrint('SPOTHOLE_METRIC_REJECTED reason=$rejectionReason');
    return resultado;
  }

  Map<String, dynamic>? _procesarOutput(
    Float32List output,
    int imgWidth,
    int imgHeight,
    int modelInputWidth,
    int modelInputHeight,
  ) {
    final detection = YoloOutputParser.parsePlanarXywhConfidence(
      output: output,
      candidateCount: _outputCandidates,
      imageWidth: imgWidth,
      imageHeight: imgHeight,
      modelInputWidth: modelInputWidth,
      modelInputHeight: modelInputHeight,
      coordinateSpace: YoloCoordinateSpace.normalized,
    );
    if (detection == null) return null;

    final anchoPx = detection.widthPx;
    final altoPx = detection.heightPx;
    final centroXPx = detection.centerXPx;
    final centroYPx = detection.centerYPx;

    return {
      'confianza': double.parse(detection.confidence.toStringAsFixed(4)),
      'anchoPx': anchoPx,
      'altoPx': altoPx,
      'centroXPx': centroXPx,
      'centroYPx': centroYPx,
      'anchoCm': null,
      'altoCm': null,
      'areaCm2': null,
      'alturaMetros': null,
      'forma': _calcularForma(anchoPx, altoPx),
      'severidad': 'No determinada',
      'referenciaMetricaValida': false,
      'metodoMedicion': Bache.metodoSinMedicion,
    };
  }

  @visibleForTesting
  static double escalarDimensionModelo({
    required double dimensionModelo,
    required int dimensionOriginal,
    required int dimensionEntradaModelo,
  }) {
    if (dimensionEntradaModelo <= 0) {
      throw ArgumentError.value(
        dimensionEntradaModelo,
        'dimensionEntradaModelo',
        'Debe ser mayor que cero',
      );
    }
    return YoloOutputParser.scaleModelDimension(
      modelValue: dimensionModelo,
      originalDimension: dimensionOriginal,
      modelInputDimension: dimensionEntradaModelo,
    );
  }

  @visibleForTesting
  static void llenarTensorRgb(img.Image image, Float32List destination) {
    final expectedLength = image.width * image.height * 3;
    if (destination.length != expectedLength) {
      throw ArgumentError.value(
        destination.length,
        'destination',
        'Se esperaban $expectedLength elementos',
      );
    }

    const normalization = 1 / 255.0;
    var index = 0;
    for (final pixel in image) {
      destination[index++] = pixel.r * normalization;
      destination[index++] = pixel.g * normalization;
      destination[index++] = pixel.b * normalization;
    }
  }

  @visibleForTesting
  static void llenarTensorRgbRedimensionado(
    img.Image image,
    Float32List destination,
    Int32List scaleX,
    Int32List scaleY,
  ) {
    final expectedLength = scaleX.length * scaleY.length * 3;
    if (destination.length != expectedLength ||
        scaleX.isEmpty ||
        scaleY.isEmpty ||
        scaleX.any((value) => value < 0 || value >= image.width) ||
        scaleY.any((value) => value < 0 || value >= image.height)) {
      throw ArgumentError('Buffer o mapa de resize inválido');
    }

    const normalization = 1 / 255.0;
    final sourcePixel = image.getPixel(0, 0);
    var index = 0;
    for (var y = 0; y < scaleY.length; y++) {
      for (var x = 0; x < scaleX.length; x++) {
        final pixel = image.getPixel(scaleX[x], scaleY[y], sourcePixel);
        destination[index++] = pixel.r * normalization;
        destination[index++] = pixel.g * normalization;
        destination[index++] = pixel.b * normalization;
      }
    }
  }

  @visibleForTesting
  static void llenarTensorDesdeYuv420({
    required Float32List destination,
    required int imageWidth,
    required int imageHeight,
    required Uint8List yBytes,
    required Uint8List uBytes,
    required Uint8List vBytes,
    required int yRowStride,
    required int uRowStride,
    required int vRowStride,
    required int uPixelStride,
    required int vPixelStride,
    required int rotationDegrees,
    required Int32List scaleX,
    required Int32List scaleY,
  }) {
    if (imageWidth <= 0 ||
        imageHeight <= 0 ||
        destination.length != scaleX.length * scaleY.length * 3 ||
        !const [0, 90, 180, 270].contains(rotationDegrees)) {
      throw ArgumentError('Frame YUV o rotación inválidos');
    }

    const normalization = 1 / 255.0;
    var destinationIndex = 0;
    for (var modelY = 0; modelY < scaleY.length; modelY++) {
      final orientedY = scaleY[modelY];
      for (var modelX = 0; modelX < scaleX.length; modelX++) {
        final orientedX = scaleX[modelX];
        final (sourceX, sourceY) = switch (rotationDegrees) {
          90 => (orientedY, imageHeight - 1 - orientedX),
          180 => (
              imageWidth - 1 - orientedX,
              imageHeight - 1 - orientedY,
            ),
          270 => (imageWidth - 1 - orientedY, orientedX),
          _ => (orientedX, orientedY),
        };

        final yValue = yBytes[sourceY * yRowStride + sourceX];
        final chromaX = sourceX >> 1;
        final chromaY = sourceY >> 1;
        final uValue = uBytes[chromaY * uRowStride + chromaX * uPixelStride];
        final vValue = vBytes[chromaY * vRowStride + chromaX * vPixelStride];

        var red = (yValue + 1.402 * (vValue - 128)).round();
        var green =
            (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
                .round();
        var blue = (yValue + 1.772 * (uValue - 128)).round();
        red = red.clamp(0, 255);
        green = green.clamp(0, 255);
        blue = blue.clamp(0, 255);

        destination[destinationIndex++] = red * normalization;
        destination[destinationIndex++] = green * normalization;
        destination[destinationIndex++] = blue * normalization;
      }
    }
  }

  void _prepareResizeMaps(int sourceWidth, int sourceHeight) {
    if (_resizeX != null &&
        _resizeY != null &&
        _resizeSourceWidth == sourceWidth &&
        _resizeSourceHeight == sourceHeight) {
      return;
    }
    _resizeSourceWidth = sourceWidth;
    _resizeSourceHeight = sourceHeight;
    _resizeX = Int32List(_inputWidth);
    _resizeY = Int32List(_inputHeight);
    for (var x = 0; x < _inputWidth; x++) {
      _resizeX![x] = (x * sourceWidth) ~/ _inputWidth;
    }
    for (var y = 0; y < _inputHeight; y++) {
      _resizeY![y] = (y * sourceHeight) ~/ _inputHeight;
    }
  }

  img.Image _convertirYUV420AImagen(CameraImage image) {
    return _convertirYuv420(
      width: image.width,
      height: image.height,
      yBytes: image.planes[0].bytes,
      uBytes: image.planes[1].bytes,
      vBytes: image.planes[2].bytes,
      yRowStride: image.planes[0].bytesPerRow,
      uRowStride: image.planes[1].bytesPerRow,
      vRowStride: image.planes[2].bytesPerRow,
      uPixelStride: image.planes[1].bytesPerPixel ?? 1,
      vPixelStride: image.planes[2].bytesPerPixel ?? 1,
    );
  }

  static img.Image convertirFrameArCoreAImagen(ArCoreDepthFrame frame) {
    var image = _convertirYuv420(
      width: frame.width,
      height: frame.height,
      yBytes: frame.yBytes,
      uBytes: frame.uBytes,
      vBytes: frame.vBytes,
      yRowStride: frame.yRowStride,
      uRowStride: frame.uRowStride,
      vRowStride: frame.vRowStride,
      uPixelStride: frame.uPixelStride,
      vPixelStride: frame.vPixelStride,
    );
    if (frame.rotationDegrees != 0) {
      image = img.copyRotate(image, angle: frame.rotationDegrees);
    }
    return image;
  }

  static img.Image _convertirYuv420({
    required int width,
    required int height,
    required Uint8List yBytes,
    required Uint8List uBytes,
    required Uint8List vBytes,
    required int yRowStride,
    required int uRowStride,
    required int vRowStride,
    required int uPixelStride,
    required int vPixelStride,
  }) {
    final img.Image imgBuffer = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      final int yRow = yRowStride * y;
      final int uRow = uRowStride * (y >> 1);
      final int vRow = vRowStride * (y >> 1);

      for (int x = 0; x < width; x++) {
        final int yIndex = yRow + x;
        final int uIndex = uRow + (x >> 1) * uPixelStride;
        final int vIndex = vRow + (x >> 1) * vPixelStride;

        final int yp = yBytes[yIndex];
        final int up = uBytes[uIndex];
        final int vp = vBytes[vIndex];

        int r = (yp + 1.402 * (vp - 128)).round();
        int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round();
        int b = (yp + 1.772 * (up - 128)).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        imgBuffer.setPixelRgb(x, y, r, g, b);
      }
    }

    return imgBuffer;
  }

  String _calcularForma(double ancho, double alto) {
    final ratio = ancho / alto;

    if (ratio >= 0.8 && ratio <= 1.2) return 'Circular';
    if (ratio > 1.2) return 'Alargado horizontal';
    return 'Alargado vertical';
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _inputTensor = null;
    _outputTensor = null;
    _inputBuffer = null;
    _inputBytes = null;
    _resizeX = null;
    _resizeY = null;
    _resizeSourceWidth = 0;
    _resizeSourceHeight = 0;
    _markerMetricService.dispose();
  }
}

class InferenceProfile {
  int sourceWidth = 0;
  int sourceHeight = 0;
  int rotationDegrees = 0;
  int rssBeforeBytes = 0;
  int rssAfterBytes = 0;
  int frameAdmissionUs = 0;
  int yuvToRgbUs = 0;
  int rotationUs = 0;
  int resizeUs = 0;
  int tensorConstructionUs = 0;
  int tfliteUs = 0;
  int postprocessUs = 0;
  int grayscalePreparationUs = 0;
  int arucoDetectionUs = 0;
  int homographyUs = 0;
  int metricCalculationUs = 0;
  int markerImagePreparationUs = 0;
  int depthMetricUs = 0;
  int depthValidSamples = 0;
  int groundPlaneInliers = 0;
  int totalUs = 0;
  bool potholeDetected = false;
  bool markerAttempted = false;
  bool markerFound = false;
  bool markerValid = false;

  double _milliseconds(int microseconds) => microseconds / 1000;

  String toLogLine() {
    final markerState = !markerAttempted
        ? 'no_ejecutado'
        : markerValid
            ? 'valido'
            : markerFound
                ? 'rechazado'
                : 'ausente';
    return 'SPOTHOLE_PROFILE '
        'frame=${sourceWidth}x$sourceHeight rot=$rotationDegrees '
        'admision=${_milliseconds(frameAdmissionUs).toStringAsFixed(2)}ms '
        'yuvRgb=${_milliseconds(yuvToRgbUs).toStringAsFixed(2)}ms '
        'rotacion=${_milliseconds(rotationUs).toStringAsFixed(2)}ms '
        'resize=${_milliseconds(resizeUs).toStringAsFixed(2)}ms '
        'tensor=${_milliseconds(tensorConstructionUs).toStringAsFixed(2)}ms '
        'tflite=${_milliseconds(tfliteUs).toStringAsFixed(2)}ms '
        'post=${_milliseconds(postprocessUs).toStringAsFixed(2)}ms '
        'gris=${_milliseconds(grayscalePreparationUs).toStringAsFixed(2)}ms '
        'aruco=${_milliseconds(arucoDetectionUs).toStringAsFixed(2)}ms '
        'homografia=${_milliseconds(homographyUs).toStringAsFixed(2)}ms '
        'metrica=${_milliseconds(metricCalculationUs).toStringAsFixed(2)}ms '
        'imagenMarcador=${_milliseconds(markerImagePreparationUs).toStringAsFixed(2)}ms '
        'depth=${_milliseconds(depthMetricUs).toStringAsFixed(2)}ms '
        'depthSamples=$depthValidSamples planoInliers=$groundPlaneInliers '
        'total=${_milliseconds(totalUs).toStringAsFixed(2)}ms '
        'rss=${(rssAfterBytes / 1048576).toStringAsFixed(1)}MiB '
        'rssDelta=${((rssAfterBytes - rssBeforeBytes) / 1048576).toStringAsFixed(1)}MiB '
        'bache=$potholeDetected marcador=$markerState';
  }
}
