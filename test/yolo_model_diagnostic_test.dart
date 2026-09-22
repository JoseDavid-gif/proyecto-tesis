import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spothole_app/services/ia_service.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

void main() {
  group('escalado de bounding boxes YOLO', () {
    test('revierte el resize independiente de ancho y alto', () {
      final ancho = IAService.escalarDimensionModelo(
        dimensionModelo: 64,
        dimensionOriginal: 1280,
        dimensionEntradaModelo: 640,
      );
      final alto = IAService.escalarDimensionModelo(
        dimensionModelo: 320,
        dimensionOriginal: 720,
        dimensionEntradaModelo: 640,
      );

      expect(ancho, 128);
      expect(alto, 360);
    });

    test('mantiene la dimensión en una imagen del tamaño del modelo', () {
      final dimension = IAService.escalarDimensionModelo(
        dimensionModelo: 125.5,
        dimensionOriginal: 640,
        dimensionEntradaModelo: 640,
      );

      expect(dimension, 125.5);
    });

    test('rechaza un tamaño de entrada inválido', () {
      expect(
        () => IAService.escalarDimensionModelo(
          dimensionModelo: 10,
          dimensionOriginal: 100,
          dimensionEntradaModelo: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('tensor de entrada tipado', () {
    test('mantiene orden RGB y normalización del tensor anterior', () {
      final image = img.Image(width: 2, height: 1)
        ..setPixelRgb(0, 0, 0, 127, 255)
        ..setPixelRgb(1, 0, 255, 64, 0);
      final buffer = Float32List(6);

      IAService.llenarTensorRgb(image, buffer);

      expect(buffer[0], 0);
      expect(buffer[1], closeTo(127 / 255, 1e-6));
      expect(buffer[2], 1);
      expect(buffer[3], 1);
      expect(buffer[4], closeTo(64 / 255, 1e-6));
      expect(buffer[5], 0);
    });

    test('rechaza un buffer con tamaño incorrecto', () {
      final image = img.Image(width: 2, height: 2);

      expect(
        () => IAService.llenarTensorRgb(image, Float32List(3)),
        throwsArgumentError,
      );
    });

    test('resize fusionado produce el mismo tensor nearest-neighbor', () {
      final source = img.Image(width: 5, height: 3);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgb(x, y, x * 20, y * 30, x + y);
        }
      }
      final resized = img.copyResize(source, width: 4, height: 4);
      final expected = Float32List(4 * 4 * 3);
      final actual = Float32List(4 * 4 * 3);
      IAService.llenarTensorRgb(resized, expected);

      IAService.llenarTensorRgbRedimensionado(
        source,
        actual,
        Int32List.fromList([0, 1, 2, 3]),
        Int32List.fromList([0, 0, 1, 2]),
      );

      expect(actual, orderedEquals(expected));
    });

    for (final rotation in [0, 90, 180, 270]) {
      test('YUV directo equivale al flujo RGB con rotación $rotation°', () {
        const width = 4;
        const height = 3;
        final yBytes = Uint8List.fromList([
          20,
          40,
          60,
          80,
          100,
          120,
          140,
          160,
          180,
          200,
          220,
          240,
        ]);
        final uBytes = Uint8List.fromList([128, 140, 116, 132]);
        final vBytes = Uint8List.fromList([128, 118, 142, 124]);
        final legacy = _legacyYuvImage(
          width: width,
          height: height,
          yBytes: yBytes,
          uBytes: uBytes,
          vBytes: vBytes,
        );
        final oriented =
            rotation == 0 ? legacy : img.copyRotate(legacy, angle: rotation);
        final expected = Float32List(oriented.width * oriented.height * 3);
        final actual = Float32List(expected.length);
        IAService.llenarTensorRgb(oriented, expected);

        IAService.llenarTensorDesdeYuv420(
          destination: actual,
          imageWidth: width,
          imageHeight: height,
          yBytes: yBytes,
          uBytes: uBytes,
          vBytes: vBytes,
          yRowStride: width,
          uRowStride: 2,
          vRowStride: 2,
          uPixelStride: 1,
          vPixelStride: 1,
          rotationDegrees: rotation,
          scaleX: Int32List.fromList(
            List.generate(oriented.width, (index) => index),
          ),
          scaleY: Int32List.fromList(
            List.generate(oriented.height, (index) => index),
          ),
        );

        expect(actual, orderedEquals(expected));
      });
    }
  });

  group('orientación del frame', () {
    test('rota 90 grados un sensor trasero en portrait', () {
      final rotation = IAService.calcularRotacionFrame(
        sensorOrientation: 90,
        deviceOrientation: DeviceOrientation.portraitUp,
        lensDirection: CameraLensDirection.back,
      );

      expect(rotation, 90);
    });

    test('compensa un sensor trasero en landscape left', () {
      final rotation = IAService.calcularRotacionFrame(
        sensorOrientation: 90,
        deviceOrientation: DeviceOrientation.landscapeLeft,
        lensDirection: CameraLensDirection.back,
      );

      expect(rotation, 0);
    });

    test('invierte la compensación para la cámara frontal', () {
      final rotation = IAService.calcularRotacionFrame(
        sensorOrientation: 90,
        deviceOrientation: DeviceOrientation.landscapeLeft,
        lensDirection: CameraLensDirection.front,
      );

      expect(rotation, 180);
    });
  });

  test(
    'diagnostica los tensores y rangos del modelo YOLO real en Android',
    () {
      final interpreter = Interpreter.fromFile(
        File('assets/model/spothole.tflite'),
      );
      addTearDown(interpreter.close);

      final inputs = interpreter.getInputTensors();
      final outputs = interpreter.getOutputTensors();

      for (final tensor in inputs) {
        // ignore: avoid_print
        print(
          'INPUT name=${tensor.name} shape=${tensor.shape} type=${tensor.type} '
          'scale=${tensor.params.scale} zeroPoint=${tensor.params.zeroPoint}',
        );
      }
      for (final tensor in outputs) {
        // ignore: avoid_print
        print(
          'OUTPUT name=${tensor.name} shape=${tensor.shape} '
          'type=${tensor.type} scale=${tensor.params.scale} '
          'zeroPoint=${tensor.params.zeroPoint}',
        );
      }

      expect(inputs.single.shape, [1, 640, 640, 3]);
      expect(inputs.single.type, TensorType.float32);
      expect(inputs.single.params.scale, 0);
      expect(inputs.single.params.zeroPoint, 0);
      expect(outputs.single.shape, [1, 5, 8400]);
      expect(outputs.single.type, TensorType.float32);
      expect(outputs.single.params.scale, 0);
      expect(outputs.single.params.zeroPoint, 0);

      inputs.single.data = Uint8List(inputs.single.numBytes());
      interpreter.invoke();

      final output = outputs.single;
      final bytes = output.data;
      final values = ByteData.sublistView(bytes);
      final channelCount = output.shape[1];
      final candidateCount = output.shape[2];
      final channels = List.generate(channelCount, (_) => <double>[]);

      for (var channel = 0; channel < channelCount; channel++) {
        for (var candidate = 0; candidate < candidateCount; candidate++) {
          final flatIndex = channel * candidateCount + candidate;
          channels[channel].add(
            values.getFloat32(flatIndex * 4, Endian.host),
          );
        }
      }

      for (var channel = 0; channel < channels.length; channel++) {
        final sorted = [...channels[channel]]..sort();
        // ignore: avoid_print
        print('CHANNEL $channel min=${sorted.first} max=${sorted.last}');
      }
    },
    skip: !Platform.isAndroid
        ? 'La biblioteca nativa tflite_flutter solo está disponible en Android.'
        : false,
  );
}

img.Image _legacyYuvImage({
  required int width,
  required int height,
  required Uint8List yBytes,
  required Uint8List uBytes,
  required Uint8List vBytes,
}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final yValue = yBytes[y * width + x];
      final chromaIndex = (y >> 1) * 2 + (x >> 1);
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
