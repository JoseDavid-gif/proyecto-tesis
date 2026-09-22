import 'dart:math' as math;

import 'arcore_depth_frame.dart';
import 'marker_metric_service.dart';

class ArCoreMetricMeasurement {
  const ArCoreMetricMeasurement({
    required this.widthCm,
    required this.heightCm,
    required this.validSamples,
    required this.planeInliers,
    required this.usedRawDepth,
  });

  final double widthCm;
  final double heightCm;
  final int validSamples;
  final int planeInliers;
  final bool usedRawDepth;
  double get boundingBoxAreaCm2 => widthCm * heightCm;
}

class ArCoreMetricResult {
  const ArCoreMetricResult.accepted(
    this.measurement, {
    this.attempts = const [],
  }) : rejectionReason = null;
  const ArCoreMetricResult.rejected(
    this.rejectionReason, {
    this.attempts = const [],
  }) : measurement = null;

  final ArCoreMetricMeasurement? measurement;
  final String? rejectionReason;
  final List<ArCoreMetricAttemptDiagnostics> attempts;
}

class ArCoreMetricAttemptDiagnostics {
  ArCoreMetricAttemptDiagnostics({required this.depthMode});

  final String depthMode;
  int candidateSamples = 0;
  int mappedDepthSamples = 0;
  int positiveDepthSamples = 0;
  int confidentDepthSamples = 0;
  int valid3DPoints = 0;
  double? minimumDepthMeters;
  double? medianDepthMeters;
  double? maximumDepthMeters;
  MetricBoundingBox? depthBoundingBox;
}

class ArCoreMetricEstimator {
  const ArCoreMetricEstimator({
    this.minimumSamples = 30,
    this.minimumConfidence = 128,
    this.ransacIterations = 100,
    this.inlierThresholdMeters = 0.03,
    this.minimumInlierRatio = 0.55,
    this.maximumPlaneTiltDegrees = 35,
  });

  final int minimumSamples;
  final int minimumConfidence;
  final int ransacIterations;
  final double inlierThresholdMeters;
  final double minimumInlierRatio;
  final double maximumPlaneTiltDegrees;

  ArCoreMetricResult estimate({
    required ArCoreDepthFrame frame,
    required MetricBoundingBox orientedBoundingBox,
  }) {
    final rawResult = _estimateOnce(
      frame: frame,
      orientedBoundingBox: orientedBoundingBox,
    );
    final fallbackDepth = frame.fallbackDepth;
    if (rawResult.measurement != null ||
        !frame.rawDepth ||
        fallbackDepth == null) {
      return rawResult;
    }
    final fullResult = _estimateOnce(
      frame: frame.usingFullDepth(fallbackDepth),
      orientedBoundingBox: orientedBoundingBox,
    );
    final attempts = [...rawResult.attempts, ...fullResult.attempts];
    return fullResult.measurement == null
        ? ArCoreMetricResult.rejected(
            fullResult.rejectionReason,
            attempts: attempts,
          )
        : ArCoreMetricResult.accepted(
            fullResult.measurement,
            attempts: attempts,
          );
  }

  ArCoreMetricResult _estimateOnce({
    required ArCoreDepthFrame frame,
    required MetricBoundingBox orientedBoundingBox,
  }) {
    final diagnostics = ArCoreMetricAttemptDiagnostics(
      depthMode: frame.rawDepth ? 'raw' : 'full',
    );
    if (!_validFrame(frame) || !_validBox(frame, orientedBoundingBox)) {
      return ArCoreMetricResult.rejected(
        'invalid_geometry',
        attempts: [diagnostics],
      );
    }
    diagnostics.depthBoundingBox = _depthBoundingBox(
      frame,
      orientedBoundingBox,
    );
    final samples = _samplePavementRing(
      frame,
      orientedBoundingBox,
      diagnostics,
    );
    if (samples.length < minimumSamples) {
      return ArCoreMetricResult.rejected(
        'insufficient_depth_samples',
        attempts: [diagnostics],
      );
    }
    final fit = _fitPlane(samples);
    if (fit == null ||
        fit.inliers < minimumSamples ||
        fit.inliers / samples.length < minimumInlierRatio) {
      return ArCoreMetricResult.rejected(
        'unstable_ground_plane',
        attempts: [diagnostics],
      );
    }
    final verticalAlignment = fit.plane.normalY.abs();
    final minimumAlignment = math.cos(maximumPlaneTiltDegrees * math.pi / 180);
    if (verticalAlignment < minimumAlignment) {
      return ArCoreMetricResult.rejected(
        'ground_plane_not_horizontal',
        attempts: [diagnostics],
      );
    }

    final projected = <_Point3>[];
    for (final point in orientedBoundingBox.corners) {
      final source = orientedToSource(frame, point);
      final intersection = _intersectRayWithPlane(frame, source, fit.plane);
      if (intersection == null) {
        return ArCoreMetricResult.rejected(
          'ray_plane_intersection',
          attempts: [diagnostics],
        );
      }
      projected.add(intersection);
    }
    final widthMeters = (_distance(projected[0], projected[1]) +
            _distance(projected[3], projected[2])) /
        2;
    final heightMeters = (_distance(projected[0], projected[3]) +
            _distance(projected[1], projected[2])) /
        2;
    final widthCm = widthMeters * 100;
    final heightCm = heightMeters * 100;
    if (!widthCm.isFinite ||
        !heightCm.isFinite ||
        widthCm < 2 ||
        heightCm < 2 ||
        widthCm > 500 ||
        heightCm > 500) {
      return ArCoreMetricResult.rejected(
        'dimensions_out_of_range',
        attempts: [diagnostics],
      );
    }
    return ArCoreMetricResult.accepted(
      ArCoreMetricMeasurement(
        widthCm: widthCm,
        heightCm: heightCm,
        validSamples: samples.length,
        planeInliers: fit.inliers,
        usedRawDepth: frame.rawDepth,
      ),
      attempts: [diagnostics],
    );
  }

  MetricBoundingBox? _depthBoundingBox(
    ArCoreDepthFrame frame,
    MetricBoundingBox box,
  ) {
    final points = <MetricPoint>[];
    for (final corner in box.corners) {
      final texture = sourceToTexture(frame, orientedToSource(frame, corner));
      if (texture == null) return null;
      points.add(
        MetricPoint(
          texture.x * frame.depth.width,
          texture.y * frame.depth.height,
        ),
      );
    }
    final xs = points.map((point) => point.x);
    final ys = points.map((point) => point.y);
    final left = xs.reduce(math.min);
    final right = xs.reduce(math.max);
    final top = ys.reduce(math.min);
    final bottom = ys.reduce(math.max);
    return MetricBoundingBox(
      centerX: (left + right) / 2,
      centerY: (top + bottom) / 2,
      width: right - left,
      height: bottom - top,
    );
  }

  bool _validFrame(ArCoreDepthFrame frame) =>
      frame.width > 0 &&
      frame.height > 0 &&
      frame.fx.isFinite &&
      frame.fy.isFinite &&
      frame.fx > 0 &&
      frame.fy > 0 &&
      frame.imageToTexture.length == 6 &&
      frame.cameraPose.length == 16 &&
      const [0, 90, 180, 270].contains(frame.rotationDegrees);

  bool _validBox(ArCoreDepthFrame frame, MetricBoundingBox box) =>
      box.centerX.isFinite &&
      box.centerY.isFinite &&
      box.width.isFinite &&
      box.height.isFinite &&
      box.width > 0 &&
      box.height > 0 &&
      box.corners.every(
        (point) =>
            point.x >= 0 &&
            point.y >= 0 &&
            point.x < frame.orientedWidth &&
            point.y < frame.orientedHeight,
      );

  List<_Point3> _samplePavementRing(
    ArCoreDepthFrame frame,
    MetricBoundingBox box,
    ArCoreMetricAttemptDiagnostics diagnostics,
  ) {
    final points = <_Point3>[];
    final depthsMeters = <double>[];
    final left = box.centerX - box.width * 0.75;
    final right = box.centerX + box.width * 0.75;
    final top = box.centerY - box.height * 0.75;
    final bottom = box.centerY + box.height * 0.75;
    final innerLeft = box.centerX - box.width * 0.55;
    final innerRight = box.centerX + box.width * 0.55;
    final innerTop = box.centerY - box.height * 0.55;
    final innerBottom = box.centerY + box.height * 0.55;
    const grid = 18;
    for (var yi = 0; yi <= grid; yi++) {
      final y = top + (bottom - top) * yi / grid;
      for (var xi = 0; xi <= grid; xi++) {
        final x = left + (right - left) * xi / grid;
        final insideInner =
            x > innerLeft && x < innerRight && y > innerTop && y < innerBottom;
        if (insideInner ||
            x < 0 ||
            y < 0 ||
            x >= frame.orientedWidth ||
            y >= frame.orientedHeight) {
          continue;
        }
        diagnostics.candidateSamples++;
        final source = orientedToSource(frame, MetricPoint(x, y));
        final texture = sourceToTexture(frame, source);
        if (texture == null) continue;
        final depthX = (texture.x * frame.depth.width).floor();
        final depthY = (texture.y * frame.depth.height).floor();
        if (depthX < 0 ||
            depthY < 0 ||
            depthX >= frame.depth.width ||
            depthY >= frame.depth.height) {
          continue;
        }
        diagnostics.mappedDepthSamples++;
        final depthMm = frame.depth.unsigned16At(depthX, depthY);
        if (depthMm == 0) continue;
        diagnostics.positiveDepthSamples++;
        final confidence = frame.confidence;
        if (confidence != null) {
          final confidenceX = (texture.x * confidence.width)
              .floor()
              .clamp(0, confidence.width - 1);
          final confidenceY = (texture.y * confidence.height)
              .floor()
              .clamp(0, confidence.height - 1);
          if (confidence.unsigned8At(confidenceX, confidenceY) <
              minimumConfidence) {
            continue;
          }
        }
        diagnostics.confidentDepthSamples++;
        final depthMeters = depthMm / 1000;
        depthsMeters.add(depthMeters);
        points.add(_worldPoint(frame, source, depthMeters));
      }
    }
    diagnostics.valid3DPoints = points.length;
    if (depthsMeters.isNotEmpty) {
      depthsMeters.sort();
      diagnostics
        ..minimumDepthMeters = depthsMeters.first
        ..medianDepthMeters = depthsMeters[depthsMeters.length ~/ 2]
        ..maximumDepthMeters = depthsMeters.last;
    }
    return points;
  }

  static MetricPoint orientedToSource(
    ArCoreDepthFrame frame,
    MetricPoint point,
  ) =>
      switch (frame.rotationDegrees) {
        90 => MetricPoint(point.y, frame.height - 1 - point.x),
        180 => MetricPoint(
            frame.width - 1 - point.x,
            frame.height - 1 - point.y,
          ),
        270 => MetricPoint(frame.width - 1 - point.y, point.x),
        _ => point,
      };

  static MetricPoint? sourceToTexture(
    ArCoreDepthFrame frame,
    MetricPoint source,
  ) {
    final transform = frame.imageToTexture;
    final xRatio = source.x / frame.width;
    final yRatio = source.y / frame.height;
    final u = transform[0] +
        xRatio * (transform[2] - transform[0]) +
        yRatio * (transform[4] - transform[0]);
    final v = transform[1] +
        xRatio * (transform[3] - transform[1]) +
        yRatio * (transform[5] - transform[1]);
    if (!u.isFinite || !v.isFinite || u < 0 || v < 0 || u >= 1 || v >= 1) {
      return null;
    }
    return MetricPoint(u, v);
  }

  _Point3 _worldPoint(
    ArCoreDepthFrame frame,
    MetricPoint source,
    double depthMeters,
  ) {
    final cameraX = (source.x - frame.cx) * depthMeters / frame.fx;
    final cameraY = (source.y - frame.cy) * depthMeters / frame.fy;
    return _transformPoint(
      frame.cameraPose,
      _Point3(cameraX, -cameraY, -depthMeters),
    );
  }

  _PlaneFit? _fitPlane(List<_Point3> points) {
    final random = math.Random(9701);
    _Plane? best;
    var bestInliers = 0;
    for (var iteration = 0; iteration < ransacIterations; iteration++) {
      final first = points[random.nextInt(points.length)];
      final second = points[random.nextInt(points.length)];
      final third = points[random.nextInt(points.length)];
      final plane = _Plane.fromPoints(first, second, third);
      if (plane == null) continue;
      var inliers = 0;
      for (final point in points) {
        if (plane.distance(point) <= inlierThresholdMeters) inliers++;
      }
      if (inliers > bestInliers) {
        best = plane;
        bestInliers = inliers;
      }
    }
    return best == null ? null : _PlaneFit(best, bestInliers);
  }

  _Point3? _intersectRayWithPlane(
    ArCoreDepthFrame frame,
    MetricPoint source,
    _Plane plane,
  ) {
    final origin = _Point3(
      frame.cameraPose[12],
      frame.cameraPose[13],
      frame.cameraPose[14],
    );
    final localRay = _Point3(
      (source.x - frame.cx) / frame.fx,
      -(source.y - frame.cy) / frame.fy,
      -1,
    );
    final direction = _transformVector(frame.cameraPose, localRay);
    final denominator = plane.dot(direction);
    if (!denominator.isFinite || denominator.abs() < 1e-6) return null;
    final distance = -(plane.dot(origin) + plane.d) / denominator;
    if (!distance.isFinite || distance <= 0 || distance > 20) return null;
    return origin + direction * distance;
  }

  static _Point3 _transformPoint(List<double> m, _Point3 p) => _Point3(
        m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12],
        m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13],
        m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14],
      );

  static _Point3 _transformVector(List<double> m, _Point3 p) => _Point3(
        m[0] * p.x + m[4] * p.y + m[8] * p.z,
        m[1] * p.x + m[5] * p.y + m[9] * p.z,
        m[2] * p.x + m[6] * p.y + m[10] * p.z,
      );

  static double _distance(_Point3 first, _Point3 second) {
    final delta = first - second;
    return math.sqrt(delta.dot(delta));
  }
}

class _PlaneFit {
  const _PlaneFit(this.plane, this.inliers);
  final _Plane plane;
  final int inliers;
}

class _Plane {
  const _Plane(this.normalX, this.normalY, this.normalZ, this.d);
  final double normalX;
  final double normalY;
  final double normalZ;
  final double d;

  static _Plane? fromPoints(_Point3 a, _Point3 b, _Point3 c) {
    final first = b - a;
    final second = c - a;
    final cross = _Point3(
      first.y * second.z - first.z * second.y,
      first.z * second.x - first.x * second.z,
      first.x * second.y - first.y * second.x,
    );
    final length = math.sqrt(cross.dot(cross));
    if (!length.isFinite || length < 1e-8) return null;
    final nx = cross.x / length;
    final ny = cross.y / length;
    final nz = cross.z / length;
    return _Plane(nx, ny, nz, -(nx * a.x + ny * a.y + nz * a.z));
  }

  double dot(_Point3 point) =>
      normalX * point.x + normalY * point.y + normalZ * point.z;
  double distance(_Point3 point) => (dot(point) + d).abs();
}

class _Point3 {
  const _Point3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;

  _Point3 operator +(_Point3 other) =>
      _Point3(x + other.x, y + other.y, z + other.z);
  _Point3 operator -(_Point3 other) =>
      _Point3(x - other.x, y - other.y, z - other.z);
  _Point3 operator *(double scale) => _Point3(x * scale, y * scale, z * scale);
  double dot(_Point3 other) => x * other.x + y * other.y + z * other.z;
}
