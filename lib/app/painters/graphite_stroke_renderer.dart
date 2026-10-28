import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/vector_point.dart';

/// Graphite V7: continuous pressure shading with deterministic grain.
class GraphiteStrokeRenderer {
  static double _opacity(double pressure) {
    final p = pressure.clamp(0.0, 1.0);
    return 0.08 + 0.70 * math.pow(p, 2.2).toDouble();
  }

  static double _noise(int x, int y) {
    var n = (x * 374761393 + y * 668265263) & 0x7fffffff;
    n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff;
    return ((n ^ (n >> 16)) & 0xffff) / 65535.0;
  }

  static void paint(
    Canvas canvas,
    List<VectorPoint> points,
    double maximumWidth,
    Color color, {
    bool mask = false,
  }) {
    if (points.isEmpty) return;

    final width = math.max(0.1, maximumWidth * 0.9);
    final path = Path()..moveTo(points.first.dx, points.first.dy);

    if (points.length == 2) {
      path.lineTo(points.last.dx, points.last.dy);
    } else if (points.length > 2) {
      for (var i = 1; i < points.length - 1; i++) {
        final current = points[i];
        final next = points[i + 1];
        path.quadraticBezierTo(
          current.dx,
          current.dy,
          (current.dx + next.dx) / 2,
          (current.dy + next.dy) / 2,
        );
      }
      path.lineTo(points.last.dx, points.last.dy);
    }

    if (mask) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      return;
    }

    if (points.length == 1) {
      canvas.drawCircle(
        Offset(points.first.dx, points.first.dy),
        width / 2,
        Paint()
          ..color = color.withValues(
            alpha: color.a * _opacity(points.first.pressure),
          ),
      );
      return;
    }

    final smoothed = <double>[];
    for (var i = 0; i < points.length; i++) {
      final previous = points[math.max(0, i - 1)].pressure;
      final current = points[i].pressure;
      final next = points[math.min(points.length - 1, i + 1)].pressure;
      smoothed.add(
        (previous * 0.25 + current * 0.5 + next * 0.25).clamp(0.0, 1.0),
      );
    }

    final bounds = path.getBounds().inflate(width);
    canvas.saveLayer(bounds, Paint());

    // Follow the smooth centreline using path metrics.
    // Pressure is interpolated by cumulative source distance.
    final distances = <double>[0.0];
    for (var i = 1; i < points.length; i++) {
      distances.add(
        distances.last +
            math.sqrt(
              math.pow(points[i].dx - points[i - 1].dx, 2) +
                  math.pow(points[i].dy - points[i - 1].dy, 2),
            ),
      );
    }

    final totalSource = distances.last;
    final metric = path.computeMetrics().first;
    final length = metric.length;
    final step = math.max(0.5, math.min(1.5, width / 5));
    final count = math.max(1, (length / step).ceil());

    final vertices = <Offset>[];
    final colors = <Color>[];
    final indices = <int>[];
    var sourceIndex = 0;

    for (var i = 0; i <= count; i++) {
      final distance = length * i / count;
      final tangent = metric.getTangentForOffset(distance);
      if (tangent == null) continue;

      final sourceDistance = totalSource * i / count;
      while (sourceIndex < distances.length - 2 &&
          distances[sourceIndex + 1] < sourceDistance) {
        sourceIndex++;
      }

      final segmentLength = distances[sourceIndex + 1] - distances[sourceIndex];
      final t = segmentLength <= 0
          ? 0.0
          : ((sourceDistance - distances[sourceIndex]) / segmentLength).clamp(
              0.0,
              1.0,
            );

      final pressure =
          smoothed[sourceIndex] +
          (smoothed[sourceIndex + 1] - smoothed[sourceIndex]) * t;

      final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
      // Pressure changes width gently while preserving a broad
      // graphite body. The ends taper over a short physical distance.
      final pressureWidth = 0.55 + 0.45 * pressure;

      final taperLength = math.min(12.0, length * 0.25);
      final entry = taperLength <= 0
          ? 1.0
          : (distance / taperLength).clamp(0.0, 1.0);
      final exit = taperLength <= 0
          ? 1.0
          : ((length - distance) / taperLength).clamp(0.0, 1.0);

      // Smoothstep avoids sudden changes in the silhouette.
      double smoothstep(double value) => value * value * (3.0 - 2.0 * value);

      final taper = smoothstep(math.min(entry, exit));
      final half = width * 0.5 * pressureWidth * (0.12 + 0.88 * taper);

      vertices.add(tangent.position + normal * half);
      vertices.add(tangent.position - normal * half);

      final opacity = _opacity(pressure);
      final pigment = color.withValues(alpha: color.a * opacity);
      colors.add(pigment);
      colors.add(pigment);

      if (i > 0) {
        final base = i * 2;
        indices.addAll([base - 2, base - 1, base, base - 1, base + 1, base]);
      }
    }

    if (vertices.length >= 4) {
      canvas.drawVertices(
        ui.Vertices(
          ui.VertexMode.triangles,
          vertices,
          colors: colors,
          indices: indices,
        ),
        BlendMode.srcOver,
        Paint()..isAntiAlias = true,
      );
    }

    // Deterministic paper tooth, sampled along the stroke rather
    // than across its potentially enormous bounding rectangle.
    final grainPath = Path();
    final grainStep = math.max(1.2, math.min(2.4, width / 4));
    final grainCount = math.max(1, (length / grainStep).ceil());
    final acrossCount = math.max(1, (width / grainStep).ceil());

    for (var i = 0; i <= grainCount; i++) {
      final distance = length * i / grainCount;
      final tangent = metric.getTangentForOffset(distance);
      if (tangent == null) continue;

      final normal = Offset(-tangent.vector.dy, tangent.vector.dx);

      for (var j = 0; j <= acrossCount; j++) {
        final offset = width * (j / acrossCount - 0.5);
        final position = tangent.position + normal * offset;

        final gx = (position.dx / grainStep).floor();
        final gy = (position.dy / grainStep).floor();
        final noise = _noise(gx, gy);

        if (noise < 0.62) continue;

        grainPath.addOval(
          Rect.fromCircle(
            center: position,
            radius: 0.22 + _noise(gx + 137, gy - 79) * 0.48,
          ),
        );
      }
    }

    canvas.drawPath(
      grainPath,
      Paint()
        ..color = const Color(0x88000000)
        ..blendMode = BlendMode.dstOut
        ..isAntiAlias = true,
    );

    // Keep the ribbon and grain within one continuous outline.
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.restore();
    canvas.restore();
  }
}
