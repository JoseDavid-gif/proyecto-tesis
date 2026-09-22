import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spothole_app/services/arcore_depth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('spothole/arcore_depth_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('dispositivo no compatible conserva fallback sin Depth', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'checkAvailability');
      return <String, Object>{
        'availability': 'UNSUPPORTED_DEVICE_NOT_CAPABLE',
        'supported': false,
        'transient': false,
      };
    });

    final result = await ArCoreDepthService(channel: channel).probe();

    expect(result.arCoreAvailable, isFalse);
    expect(result.canUseAutomaticDepth, isFalse);
    expect(result.reason, 'device_not_supported');
  });

  test('ARCore instalado distingue Automatic y Raw Depth', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'checkAvailability') {
        return <String, Object>{
          'availability': 'SUPPORTED_INSTALLED',
          'supported': true,
          'transient': false,
        };
      }
      expect(call.method, 'checkDepthSupport');
      return <String, Object>{
        'sessionSupported': true,
        'automaticDepthSupported': true,
        'rawDepthSupported': false,
      };
    });

    final result = await ArCoreDepthService(channel: channel).probe();

    expect(result.canUseAutomaticDepth, isTrue);
    expect(result.rawDepthSupported, isFalse);
  });

  test('ARCore compatible sin Depth conserva detección normal', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'checkAvailability') {
        return <String, Object>{
          'availability': 'SUPPORTED_INSTALLED',
          'supported': true,
          'transient': false,
        };
      }
      return <String, Object>{
        'sessionSupported': true,
        'automaticDepthSupported': false,
        'rawDepthSupported': false,
      };
    });

    final result = await ArCoreDepthService(channel: channel).probe();

    expect(result.arCoreAvailable, isTrue);
    expect(result.canUseAutomaticDepth, isFalse);
  });

  test('solicita instalación oficial sin bloquear el fallback', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'checkAvailability') {
        return <String, Object>{
          'availability': 'SUPPORTED_NOT_INSTALLED',
          'supported': true,
          'transient': false,
        };
      }
      expect(call.method, 'requestInstall');
      expect(call.arguments, <String, Object>{'userRequestedInstall': true});
      return <String, Object>{'installStatus': 'INSTALL_REQUESTED'};
    });

    final result = await ArCoreDepthService(channel: channel).probe();

    expect(result.installRequested, isTrue);
    expect(result.canUseAutomaticDepth, isFalse);
    expect(result.reason, 'install_requested');
  });

  test('recibe un frame RGB, Raw Depth y Full Depth sincronizados', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'acquireFrame');
      final depth = <String, Object>{
        'width': 1,
        'height': 1,
        'timestampNs': 42,
        'bytes': Uint8List.fromList([232, 3]),
        'rowStride': 2,
        'pixelStride': 2,
      };
      return <String, Object>{
        'width': 2,
        'height': 2,
        'frameTimestampNs': 42,
        'rotationDegrees': 0,
        'yBytes': Uint8List(4),
        'uBytes': Uint8List(1),
        'vBytes': Uint8List(1),
        'yRowStride': 2,
        'uRowStride': 1,
        'vRowStride': 1,
        'uPixelStride': 1,
        'vPixelStride': 1,
        'fx': 2.0,
        'fy': 2.0,
        'cx': 1.0,
        'cy': 1.0,
        'imageToTexture': <double>[0, 0, 1, 0, 0, 1],
        'cameraPose': <double>[
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
        'depth': depth,
        'confidence': <String, Object>{
          ...depth,
          'bytes': Uint8List.fromList([255]),
          'rowStride': 1,
          'pixelStride': 1,
        },
        'fallbackDepth': depth,
        'rawDepth': true,
      };
    });

    final frame = await ArCoreDepthService(channel: channel).acquireFrame();

    expect(frame, isNotNull);
    expect(frame!.timestampNs, 42);
    expect(frame.depth.unsigned16At(0, 0), 1000);
    expect(frame.fallbackDepth, isNotNull);
  });

  test('lifecycle nativo recibe pausa, reanudación y cierre', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    final service = ArCoreDepthService(channel: channel);

    await service.pauseDepthCamera();
    await service.resumeDepthCamera();
    await service.disposeDepthCamera();

    expect(
      calls,
      ['pauseDepthCamera', 'resumeDepthCamera', 'disposeDepthCamera'],
    );
  });

  test('frame aún no disponible no rompe el flujo', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'FRAME_NOT_YET_AVAILABLE');
    });

    final frame = await ArCoreDepthService(channel: channel).acquireFrame();

    expect(frame, isNull);
  });
}
