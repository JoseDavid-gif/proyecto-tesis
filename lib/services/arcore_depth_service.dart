import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'arcore_depth_frame.dart';

class ArCoreDepthCapabilities {
  const ArCoreDepthCapabilities({
    required this.availability,
    required this.arCoreAvailable,
    required this.installed,
    required this.installRequested,
    required this.sessionSupported,
    required this.automaticDepthSupported,
    required this.rawDepthSupported,
    this.reason,
  });

  final String availability;
  final bool arCoreAvailable;
  final bool installed;
  final bool installRequested;
  final bool sessionSupported;
  final bool automaticDepthSupported;
  final bool rawDepthSupported;
  final String? reason;

  bool get canUseAutomaticDepth =>
      installed && sessionSupported && automaticDepthSupported;
}

class ArCoreDepthService {
  ArCoreDepthService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('spothole/arcore_depth');

  final MethodChannel _channel;

  static const _temporaryFrameErrors = <String>{
    'FRAME_NOT_YET_AVAILABLE',
    'FRAME_REQUEST_BUSY',
    'TRACKING_UNAVAILABLE',
    'DEPTH_CAMERA_NOT_READY',
    'DEPTH_CAMERA_PAUSED',
  };

  Future<ArCoreDepthFrame?> acquireFrame() async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>(
        'acquireFrame',
      );
      return map == null ? null : ArCoreDepthFrame.fromMap(map);
    } on PlatformException catch (error) {
      if (_temporaryFrameErrors.contains(error.code)) return null;
      rethrow;
    }
  }

  Future<void> pauseDepthCamera() =>
      _channel.invokeMethod<void>('pauseDepthCamera');

  Future<void> resumeDepthCamera() =>
      _channel.invokeMethod<void>('resumeDepthCamera');

  Future<void> disposeDepthCamera() =>
      _channel.invokeMethod<void>('disposeDepthCamera');

  Future<ArCoreDepthCapabilities> probe({bool requestInstall = true}) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const ArCoreDepthCapabilities(
        availability: 'NON_ANDROID',
        arCoreAvailable: false,
        installed: false,
        installRequested: false,
        sessionSupported: false,
        automaticDepthSupported: false,
        rawDepthSupported: false,
        reason: 'non_android',
      );
    }

    try {
      final availability = await _readMap('checkAvailability');
      final state = availability['availability'] as String? ?? 'UNKNOWN_ERROR';
      final supported = availability['supported'] == true;
      final transient = availability['transient'] == true;
      if (!supported || transient) {
        return _unavailable(
          state,
          transient ? 'availability_transient' : 'device_not_supported',
        );
      }

      var installed = state == 'SUPPORTED_INSTALLED';
      var installRequested = false;
      if (!installed && requestInstall) {
        final install = await _readMap(
          'requestInstall',
          <String, Object>{'userRequestedInstall': true},
        );
        final status = install['installStatus'] as String?;
        installed = status == 'INSTALLED';
        installRequested = status == 'INSTALL_REQUESTED';
      }
      if (!installed) {
        return ArCoreDepthCapabilities(
          availability: state,
          arCoreAvailable: true,
          installed: false,
          installRequested: installRequested,
          sessionSupported: false,
          automaticDepthSupported: false,
          rawDepthSupported: false,
          reason:
              installRequested ? 'install_requested' : 'arcore_not_installed',
        );
      }

      final depth = await _readMap('checkDepthSupport');
      return ArCoreDepthCapabilities(
        availability: state,
        arCoreAvailable: true,
        installed: true,
        installRequested: false,
        sessionSupported: depth['sessionSupported'] == true,
        automaticDepthSupported: depth['automaticDepthSupported'] == true,
        rawDepthSupported: depth['rawDepthSupported'] == true,
        reason: depth['reason'] as String?,
      );
    } on PlatformException catch (error) {
      return _unavailable('PLATFORM_ERROR', error.code);
    } on MissingPluginException {
      return _unavailable('MISSING_PLUGIN', 'native_bridge_unavailable');
    }
  }

  Future<Map<Object?, Object?>> _readMap(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      method,
      arguments,
    );
    return result ?? const <Object?, Object?>{};
  }

  ArCoreDepthCapabilities _unavailable(String availability, String reason) {
    return ArCoreDepthCapabilities(
      availability: availability,
      arCoreAvailable: false,
      installed: false,
      installRequested: false,
      sessionSupported: false,
      automaticDepthSupported: false,
      rawDepthSupported: false,
      reason: reason,
    );
  }
}
