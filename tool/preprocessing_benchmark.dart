import 'dart:typed_data';

import 'package:image/image.dart' as img;

const _sourceWidth = 1280;
const _sourceHeight = 720;
const _modelSize = 640;
const _iterations = 7;

void main() {
  final source = img.Image(width: _sourceWidth, height: _sourceHeight);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      source.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }

  _legacyIteration(source);
  final resizeSamples = <int>[];
  final tensorSamples = <int>[];
  final typedTensorSamples = <int>[];
  final fusedTensorSamples = <int>[];
  final typedBuffer = Float32List(_modelSize * _modelSize * 3);
  final scaleX = Int32List.fromList(
    List.generate(_modelSize, (x) => (x * source.width) ~/ _modelSize),
  );
  final scaleY = Int32List.fromList(
    List.generate(_modelSize, (y) => (y * source.height) ~/ _modelSize),
  );
  for (var iteration = 0; iteration < _iterations; iteration++) {
    final sample = _legacyIteration(source);
    resizeSamples.add(sample.$1);
    tensorSamples.add(sample.$2);
    typedTensorSamples.add(_typedIteration(source, typedBuffer));
    fusedTensorSamples.add(
      _fusedIteration(source, typedBuffer, scaleX, scaleY),
    );
  }

  resizeSamples.sort();
  tensorSamples.sort();
  typedTensorSamples.sort();
  fusedTensorSamples.sort();
  // ignore: avoid_print
  print(
    'PREPROCESS_BASELINE desktop=windows source=${source.width}x${source.height} '
    'model=${_modelSize}x$_modelSize iterations=$_iterations '
    'resizeMedianUs=${resizeSamples[_iterations ~/ 2]} '
    'tensorMedianUs=${tensorSamples[_iterations ~/ 2]} '
    'typedTensorMedianUs=${typedTensorSamples[_iterations ~/ 2]} '
    'fusedTensorMedianUs=${fusedTensorSamples[_iterations ~/ 2]}',
  );

  _benchmarkYuvPath();
}

void _benchmarkYuvPath() {
  final yBytes = Uint8List(_sourceWidth * _sourceHeight);
  const chromaWidth = _sourceWidth ~/ 2;
  const chromaHeight = (_sourceHeight + 1) ~/ 2;
  final uBytes = Uint8List(chromaWidth * chromaHeight);
  final vBytes = Uint8List(chromaWidth * chromaHeight);
  for (var index = 0; index < yBytes.length; index++) {
    yBytes[index] = index % 256;
  }
  uBytes.fillRange(0, uBytes.length, 128);
  vBytes.fillRange(0, vBytes.length, 128);

  const orientedWidth = _sourceHeight;
  const orientedHeight = _sourceWidth;
  final scaleX = Int32List.fromList(
    List.generate(_modelSize, (x) => (x * orientedWidth) ~/ _modelSize),
  );
  final scaleY = Int32List.fromList(
    List.generate(_modelSize, (y) => (y * orientedHeight) ~/ _modelSize),
  );
  final buffer = Float32List(_modelSize * _modelSize * 3);
  final conversionSamples = <int>[];
  final rotationSamples = <int>[];
  final legacyTensorSamples = <int>[];
  final directSamples = <int>[];

  for (var iteration = 0; iteration < _iterations; iteration++) {
    final conversionWatch = Stopwatch()..start();
    final rgb = _legacyYuvImage(yBytes, uBytes, vBytes);
    conversionWatch.stop();
    conversionSamples.add(conversionWatch.elapsedMicroseconds);

    final rotationWatch = Stopwatch()..start();
    final rotated = img.copyRotate(rgb, angle: 90);
    rotationWatch.stop();
    rotationSamples.add(rotationWatch.elapsedMicroseconds);
    legacyTensorSamples.add(
      _fusedIteration(rotated, buffer, scaleX, scaleY),
    );

    final directWatch = Stopwatch()..start();
    _directYuv90Tensor(yBytes, uBytes, vBytes, buffer, scaleX, scaleY);
    directWatch.stop();
    directSamples.add(directWatch.elapsedMicroseconds);
  }

  conversionSamples.sort();
  rotationSamples.sort();
  legacyTensorSamples.sort();
  directSamples.sort();
  // ignore: avoid_print
  print(
    'YUV_PATH desktop=windows source=${_sourceWidth}x$_sourceHeight '
    'rotation=90 iterations=$_iterations '
    'legacyConversionMedianUs=${conversionSamples[_iterations ~/ 2]} '
    'legacyRotationMedianUs=${rotationSamples[_iterations ~/ 2]} '
    'legacyTensorMedianUs=${legacyTensorSamples[_iterations ~/ 2]} '
    'directYuvTensorMedianUs=${directSamples[_iterations ~/ 2]}',
  );
}

img.Image _legacyYuvImage(
  Uint8List yBytes,
  Uint8List uBytes,
  Uint8List vBytes,
) {
  final image = img.Image(width: _sourceWidth, height: _sourceHeight);
  const chromaWidth = _sourceWidth ~/ 2;
  for (var y = 0; y < _sourceHeight; y++) {
    for (var x = 0; x < _sourceWidth; x++) {
      final yValue = yBytes[y * _sourceWidth + x];
      final chromaIndex = (y >> 1) * chromaWidth + (x >> 1);
      final uValue = uBytes[chromaIndex];
      final vValue = vBytes[chromaIndex];
      var red = (yValue + 1.402 * (vValue - 128)).round();
      var green =
          (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
              .round();
      var blue = (yValue + 1.772 * (uValue - 128)).round();
      red = red.clamp(0, 255);
      green = green.clamp(0, 255);
      blue = blue.clamp(0, 255);
      image.setPixelRgb(x, y, red, green, blue);
    }
  }
  return image;
}

void _directYuv90Tensor(
  Uint8List yBytes,
  Uint8List uBytes,
  Uint8List vBytes,
  Float32List destination,
  Int32List scaleX,
  Int32List scaleY,
) {
  const normalization = 1 / 255.0;
  const chromaWidth = _sourceWidth ~/ 2;
  var index = 0;
  for (var modelY = 0; modelY < scaleY.length; modelY++) {
    final sourceX = scaleY[modelY];
    for (var modelX = 0; modelX < scaleX.length; modelX++) {
      final sourceY = _sourceHeight - 1 - scaleX[modelX];
      final yValue = yBytes[sourceY * _sourceWidth + sourceX];
      final chromaIndex = (sourceY >> 1) * chromaWidth + (sourceX >> 1);
      final uValue = uBytes[chromaIndex];
      final vValue = vBytes[chromaIndex];
      var red = (yValue + 1.402 * (vValue - 128)).round();
      var green =
          (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
              .round();
      var blue = (yValue + 1.772 * (uValue - 128)).round();
      red = red.clamp(0, 255);
      green = green.clamp(0, 255);
      blue = blue.clamp(0, 255);
      destination[index++] = red * normalization;
      destination[index++] = green * normalization;
      destination[index++] = blue * normalization;
    }
  }
}

int _fusedIteration(
  img.Image source,
  Float32List buffer,
  Int32List scaleX,
  Int32List scaleY,
) {
  final watch = Stopwatch()..start();
  const normalization = 1 / 255.0;
  final sourcePixel = source.getPixel(0, 0);
  var index = 0;
  for (var y = 0; y < scaleY.length; y++) {
    for (var x = 0; x < scaleX.length; x++) {
      final pixel = source.getPixel(scaleX[x], scaleY[y], sourcePixel);
      buffer[index++] = pixel.r * normalization;
      buffer[index++] = pixel.g * normalization;
      buffer[index++] = pixel.b * normalization;
    }
  }
  watch.stop();
  if (buffer[0] < 0) throw StateError('Tensor inválido');
  return watch.elapsedMicroseconds;
}

int _typedIteration(img.Image source, Float32List buffer) {
  final resized = img.copyResize(
    source,
    width: _modelSize,
    height: _modelSize,
  );
  final tensorWatch = Stopwatch()..start();
  _fillTypedTensor(resized, buffer);
  tensorWatch.stop();
  if (buffer[0] < 0) throw StateError('Tensor inválido');
  return tensorWatch.elapsedMicroseconds;
}

void _fillTypedTensor(img.Image image, Float32List destination) {
  const normalization = 1 / 255.0;
  var index = 0;
  for (final pixel in image) {
    destination[index++] = pixel.r * normalization;
    destination[index++] = pixel.g * normalization;
    destination[index++] = pixel.b * normalization;
  }
}

(int, int) _legacyIteration(img.Image source) {
  final resizeWatch = Stopwatch()..start();
  final resized = img.copyResize(
    source,
    width: _modelSize,
    height: _modelSize,
  );
  resizeWatch.stop();

  final tensorWatch = Stopwatch()..start();
  final tensor = List.generate(
    1,
    (_) => List.generate(
      _modelSize,
      (y) => List.generate(
        _modelSize,
        (x) {
          final pixel = resized.getPixel(x, y);
          return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
        },
      ),
    ),
  );
  tensorWatch.stop();

  if (tensor[0][0][0][0] < 0) throw StateError('Tensor inválido');
  return (resizeWatch.elapsedMicroseconds, tensorWatch.elapsedMicroseconds);
}
