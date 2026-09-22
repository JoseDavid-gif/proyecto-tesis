import 'dart:typed_data';

class ArCoreDepthImage {
  const ArCoreDepthImage({
    required this.width,
    required this.height,
    required this.timestampNs,
    required this.bytes,
    required this.rowStride,
    required this.pixelStride,
  });

  final int width;
  final int height;
  final int timestampNs;
  final Uint8List bytes;
  final int rowStride;
  final int pixelStride;

  int unsigned16At(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    final offset = y * rowStride + x * pixelStride;
    if (offset < 0 || offset + 1 >= bytes.length) return 0;
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  int unsigned8At(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    final offset = y * rowStride + x * pixelStride;
    if (offset < 0 || offset >= bytes.length) return 0;
    return bytes[offset];
  }
}

class ArCoreDepthFrame {
  const ArCoreDepthFrame({
    required this.width,
    required this.height,
    required this.timestampNs,
    required this.rotationDegrees,
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.yRowStride,
    required this.uRowStride,
    required this.vRowStride,
    required this.uPixelStride,
    required this.vPixelStride,
    required this.fx,
    required this.fy,
    required this.cx,
    required this.cy,
    required this.imageToTexture,
    required this.cameraPose,
    required this.depth,
    required this.rawDepth,
    this.confidence,
    this.fallbackDepth,
  });

  final int width;
  final int height;
  final int timestampNs;
  final int rotationDegrees;
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int yRowStride;
  final int uRowStride;
  final int vRowStride;
  final int uPixelStride;
  final int vPixelStride;
  final double fx;
  final double fy;
  final double cx;
  final double cy;
  final List<double> imageToTexture;
  final List<double> cameraPose;
  final ArCoreDepthImage depth;
  final ArCoreDepthImage? confidence;
  final ArCoreDepthImage? fallbackDepth;
  final bool rawDepth;

  int get orientedWidth =>
      rotationDegrees == 90 || rotationDegrees == 270 ? height : width;
  int get orientedHeight =>
      rotationDegrees == 90 || rotationDegrees == 270 ? width : height;

  ArCoreDepthFrame usingFullDepth(ArCoreDepthImage fullDepth) =>
      ArCoreDepthFrame(
        width: width,
        height: height,
        timestampNs: timestampNs,
        rotationDegrees: rotationDegrees,
        yBytes: yBytes,
        uBytes: uBytes,
        vBytes: vBytes,
        yRowStride: yRowStride,
        uRowStride: uRowStride,
        vRowStride: vRowStride,
        uPixelStride: uPixelStride,
        vPixelStride: vPixelStride,
        fx: fx,
        fy: fy,
        cx: cx,
        cy: cy,
        imageToTexture: imageToTexture,
        cameraPose: cameraPose,
        depth: fullDepth,
        rawDepth: false,
      );

  static ArCoreDepthFrame fromMap(Map<Object?, Object?> map) {
    T requiredValue<T>(Object key) {
      final value = map[key];
      if (value is! T) throw FormatException('Campo ARCore inválido: $key');
      return value;
    }

    List<double> doubles(Object key, int length) {
      final value = requiredValue<List<Object?>>(key);
      if (value.length != length) {
        throw FormatException('Longitud ARCore inválida: $key');
      }
      return value.map((item) => (item as num).toDouble()).toList();
    }

    ArCoreDepthImage image(Object key) {
      final value = requiredValue<Map<Object?, Object?>>(key);
      return ArCoreDepthImage(
        width: value['width'] as int,
        height: value['height'] as int,
        timestampNs: value['timestampNs'] as int,
        bytes: value['bytes'] as Uint8List,
        rowStride: value['rowStride'] as int,
        pixelStride: value['pixelStride'] as int,
      );
    }

    final confidenceMap = map['confidence'];
    final fallbackDepthMap = map['fallbackDepth'];
    return ArCoreDepthFrame(
      width: requiredValue<int>('width'),
      height: requiredValue<int>('height'),
      timestampNs: requiredValue<int>('frameTimestampNs'),
      rotationDegrees: requiredValue<int>('rotationDegrees'),
      yBytes: requiredValue<Uint8List>('yBytes'),
      uBytes: requiredValue<Uint8List>('uBytes'),
      vBytes: requiredValue<Uint8List>('vBytes'),
      yRowStride: requiredValue<int>('yRowStride'),
      uRowStride: requiredValue<int>('uRowStride'),
      vRowStride: requiredValue<int>('vRowStride'),
      uPixelStride: requiredValue<int>('uPixelStride'),
      vPixelStride: requiredValue<int>('vPixelStride'),
      fx: requiredValue<num>('fx').toDouble(),
      fy: requiredValue<num>('fy').toDouble(),
      cx: requiredValue<num>('cx').toDouble(),
      cy: requiredValue<num>('cy').toDouble(),
      imageToTexture: doubles('imageToTexture', 6),
      cameraPose: doubles('cameraPose', 16),
      depth: image('depth'),
      confidence: confidenceMap is Map<Object?, Object?>
          ? ArCoreDepthImage(
              width: confidenceMap['width'] as int,
              height: confidenceMap['height'] as int,
              timestampNs: confidenceMap['timestampNs'] as int,
              bytes: confidenceMap['bytes'] as Uint8List,
              rowStride: confidenceMap['rowStride'] as int,
              pixelStride: confidenceMap['pixelStride'] as int,
            )
          : null,
      fallbackDepth: fallbackDepthMap is Map<Object?, Object?>
          ? ArCoreDepthImage(
              width: fallbackDepthMap['width'] as int,
              height: fallbackDepthMap['height'] as int,
              timestampNs: fallbackDepthMap['timestampNs'] as int,
              bytes: fallbackDepthMap['bytes'] as Uint8List,
              rowStride: fallbackDepthMap['rowStride'] as int,
              pixelStride: fallbackDepthMap['pixelStride'] as int,
            )
          : null,
      rawDepth: requiredValue<bool>('rawDepth'),
    );
  }
}
