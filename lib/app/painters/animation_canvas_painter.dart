import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/vector_point.dart';
import '../models/vector_stroke.dart';

class AnimationCanvasPainter extends CustomPainter {
  AnimationCanvasPainter({
    super.repaint,
    required this.strokes,
    required this.currentStroke,
    this.symmetryCurrentStrokes = const <List<VectorPoint>>[],
    required this.previousOnionSkinStrokes,
    required this.nextOnionSkinStrokes,
    required this.strokeColor,
    required this.previousOnionSkinColor,
    required this.nextOnionSkinColor,
    required this.strokeWidth,
    required this.brushType,
    required this.backgroundColor,
    this.paintBackground = true,
    this.alphaLockMaskStrokes = const <VectorStroke>[],
  });

  final List<VectorStroke> strokes;
  final List<VectorPoint>? currentStroke;

  /// View-only live siblings derived from the authoritative drawing gesture.
  ///
  /// These use the exact same brush renderer, pressure response, and Alpha
  /// Lock mask as the source draft. They are committed by Workspace as
  /// independent VectorStrokes when the gesture ends.
  final List<List<VectorPoint>> symmetryCurrentStrokes;

  final List<VectorStroke> previousOnionSkinStrokes;
  final List<VectorStroke> nextOnionSkinStrokes;

  final Color strokeColor;
  final Color previousOnionSkinColor;
  final Color nextOnionSkinColor;
  final double strokeWidth;
  final StrokeBrushType brushType;
  final Color backgroundColor;
  final bool paintBackground;

  /// Saved artwork used as the Alpha Lock footprint.
  ///
  /// When non-empty, the current live stroke is composited through the
  /// rendered alpha of these strokes rather than being allowed to paint
  /// outside the existing artwork.
  final List<VectorStroke> alphaLockMaskStrokes;

  @override
  void paint(Canvas canvas, Size size) {
    if (paintBackground) {
      final backgroundPaint = Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.fill;

      canvas.drawRect(Offset.zero & size, backgroundPaint);
    }

    // Current saved frame.
    //
    // Ordinary strokes establish the layer's Alpha Lock footprint.
    // Strokes authored while Alpha Lock was enabled are rendered through
    // that stable footprint and never enlarge the mask themselves.
    final alphaLockMask = strokes
        .where((stroke) => !stroke.alphaLocked)
        .toList(growable: false);

    // Paint the ordinary artwork first. It establishes both the visible
    // base and the stable Alpha Lock footprint.
    for (final stroke in strokes) {
      if (!stroke.alphaLocked) {
        _paintStroke(canvas, stroke, stroke.color);
      }
    }

    // Composite all saved Alpha-Locked strokes as one batch.
    //
    // Previously every locked stroke created its own pair of saveLayers and
    // repainted the complete base artwork as a dstIn mask. Complex painted
    // layers therefore scaled roughly as:
    //
    //   locked strokes × complete mask geometry
    //
    // which could exhaust the renderer on large projects.
    //
    // The Alpha Lock footprint is identical for every locked stroke, so build
    // the locked artwork together and apply that footprint exactly once.
    if (alphaLockMask.isNotEmpty) {
      final alphaLockedStrokes = strokes
          .where((stroke) => stroke.alphaLocked)
          .toList(growable: false);

      if (alphaLockedStrokes.isNotEmpty) {
        canvas.saveLayer(Offset.zero & size, Paint());

        for (final stroke in alphaLockedStrokes) {
          _paintStroke(canvas, stroke, stroke.color);
        }

        canvas.saveLayer(
          Offset.zero & size,
          Paint()..blendMode = BlendMode.dstIn,
        );

        for (final maskStroke in alphaLockMask) {
          _paintStroke(canvas, maskStroke, Colors.white);
        }

        canvas.restore();
        canvas.restore();
      }
    }

    // Current stroke being drawn plus any view-only symmetry siblings.
    //
    // Every live sibling travels through the same brush renderer and Alpha
    // Lock mask as the authoritative source gesture, so preview and commit
    // remain visually identical.
    final livePointSets = <List<VectorPoint>>[
      if (currentStroke != null && currentStroke!.isNotEmpty) currentStroke!,
      ...symmetryCurrentStrokes.where((points) => points.isNotEmpty),
    ];

    if (livePointSets.isNotEmpty) {
      final liveAlphaLockMask = alphaLockMaskStrokes
          .where((stroke) => !stroke.alphaLocked)
          .toList(growable: false);

      void paintLiveStrokes() {
        for (final points in livePointSets) {
          final liveStroke = VectorStroke(
            points: points,
            strokeWidth: strokeWidth,
            brushType: brushType,
          );

          _paintStroke(canvas, liveStroke, strokeColor);
        }
      }

      if (liveAlphaLockMask.isEmpty) {
        paintLiveStrokes();
      } else {
        // Composite the complete live symmetry family as one batch, then
        // retain only pixels covered by established non-Alpha-Locked artwork.
        canvas.saveLayer(Offset.zero & size, Paint());

        paintLiveStrokes();

        canvas.saveLayer(
          Offset.zero & size,
          Paint()..blendMode = BlendMode.dstIn,
        );

        for (final maskStroke in liveAlphaLockMask) {
          _paintStroke(canvas, maskStroke, Colors.white);
        }

        canvas.restore();
        canvas.restore();
      }
    }

    // Onion skins are intentionally painted last so they remain
    // visible while drawing the in-between frame.
    for (final stroke in previousOnionSkinStrokes) {
      _paintStroke(canvas, stroke, previousOnionSkinColor);
    }

    for (final stroke in nextOnionSkinStrokes) {
      _paintStroke(canvas, stroke, nextOnionSkinColor);
    }
  }

  List<VectorPoint> _smoothPoints(List<VectorPoint> source) {
    if (source.length < 3) {
      return source;
    }

    final smoothed = <VectorPoint>[source.first];

    for (var i = 1; i < source.length - 1; i++) {
      final previous = source[i - 1];
      final current = source[i];
      final next = source[i + 1];

      smoothed.add(
        VectorPoint(
          dx: (previous.dx * 0.25) + (current.dx * 0.50) + (next.dx * 0.25),
          dy: (previous.dy * 0.25) + (current.dy * 0.50) + (next.dy * 0.25),
          pressure:
              (previous.pressure * 0.25) +
              (current.pressure * 0.50) +
              (next.pressure * 0.25),
        ),
      );
    }

    smoothed.add(source.last);
    return smoothed;
  }

  double _pressureWidth(VectorPoint point, double maximumWidth) {
    final pressure = point.pressure.clamp(0.0, 1.0);

    // Finer taper at very light contact while still reaching
    // the full selected brush width under firm pressure.
    final response = math.pow(pressure, 1.35).toDouble();

    const minimumFactor = 0.015;

    final factor = minimumFactor + (response * (1.0 - minimumFactor));

    return maximumWidth * factor;
  }

  void _appendSmoothEdge(Path path, List<Offset> points) {
    if (points.isEmpty) {
      return;
    }

    path.moveTo(points.first.dx, points.first.dy);

    if (points.length == 1) {
      return;
    }

    if (points.length == 2) {
      path.lineTo(points.last.dx, points.last.dy);
      return;
    }

    // Catmull-Rom style interpolation converted to cubic Bézier segments.
    //
    // This is the same curve principle used by the ordinary freehand brush,
    // but applied to each side of the pressure-sensitive ribbon.
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i == 0 ? points[i] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;

      final control1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );

      final control2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );

      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        p2.dx,
        p2.dy,
      );
    }
  }

  void _paintPressureStroke(
    Canvas canvas,
    List<VectorPoint> points,
    double maximumWidth,
    Color color,
  ) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    if (points.length == 1) {
      final point = points.first;
      final radius = _pressureWidth(point, maximumWidth) / 2;

      canvas.drawCircle(Offset(point.dx, point.dy), radius, paint);
      return;
    }

    // Resolve the two pressure-sensitive edges around the smoothed centre
    // line. Pressure and tangent behaviour remain exactly the same as before.
    final left = <Offset>[];
    final right = <Offset>[];

    for (var i = 0; i < points.length; i++) {
      final point = points[i];

      final previous = i == 0 ? point : points[i - 1];
      final next = i == points.length - 1 ? point : points[i + 1];

      var dx = next.dx - previous.dx;
      var dy = next.dy - previous.dy;

      final length = math.sqrt((dx * dx) + (dy * dy));

      if (length > 0.0001) {
        dx /= length;
        dy /= length;
      } else {
        dx = 1;
        dy = 0;
      }

      final normalX = -dy;
      final normalY = dx;
      final halfWidth = _pressureWidth(point, maximumWidth) / 2;

      left.add(
        Offset(
          point.dx + (normalX * halfWidth),
          point.dy + (normalY * halfWidth),
        ),
      );

      right.add(
        Offset(
          point.dx - (normalX * halfWidth),
          point.dy - (normalY * halfWidth),
        ),
      );
    }

    // Curve both ribbon edges rather than joining pressure samples with
    // straight polygon segments. This keeps fast S Pen gestures visually
    // smooth even when consecutive samples are farther apart.
    final ribbon = Path();

    _appendSmoothEdge(ribbon, left);

    final reversedRight = right.reversed.toList(growable: false);

    if (reversedRight.isNotEmpty) {
      ribbon.lineTo(reversedRight.first.dx, reversedRight.first.dy);

      if (reversedRight.length == 2) {
        ribbon.lineTo(reversedRight.last.dx, reversedRight.last.dy);
      } else if (reversedRight.length > 2) {
        for (var i = 0; i < reversedRight.length - 1; i++) {
          final p0 = i == 0 ? reversedRight[i] : reversedRight[i - 1];

          final p1 = reversedRight[i];
          final p2 = reversedRight[i + 1];

          final p3 = i + 2 < reversedRight.length ? reversedRight[i + 2] : p2;

          final control1 = Offset(
            p1.dx + (p2.dx - p0.dx) / 6,
            p1.dy + (p2.dy - p0.dy) / 6,
          );

          final control2 = Offset(
            p2.dx - (p3.dx - p1.dx) / 6,
            p2.dy - (p3.dy - p1.dy) / 6,
          );

          ribbon.cubicTo(
            control1.dx,
            control1.dy,
            control2.dx,
            control2.dy,
            p2.dx,
            p2.dy,
          );
        }
      }
    }

    ribbon.close();
    canvas.drawPath(ribbon, paint);

    // Rounded pressure-sensitive caps remain unchanged.
    final first = points.first;
    final last = points.last;

    canvas.drawCircle(
      Offset(first.dx, first.dy),
      _pressureWidth(first, maximumWidth) / 2,
      paint,
    );

    canvas.drawCircle(
      Offset(last.dx, last.dy),
      _pressureWidth(last, maximumWidth) / 2,
      paint,
    );
  }

  void _paintStroke(Canvas canvas, VectorStroke stroke, Color color) {
    final points = stroke.filled ? stroke.points : _smoothPoints(stroke.points);

    if (points.isEmpty) {
      return;
    }

    if (!stroke.filled && stroke.brushType == StrokeBrushType.pressure) {
      _paintPressureStroke(canvas, points, stroke.strokeWidth, color);
      return;
    }

    // Generated filled rectangles/squares use four exact corner points.
    // Render them as true polygon geometry instead of feeding them through
    // the cubic freehand curve renderer.
    //
    // Freehand Fill normally contains many points, so it keeps its existing
    // smooth curved rendering behaviour.
    if (stroke.filled && points.length == 4) {
      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      final path = Path()..moveTo(points.first.dx, points.first.dy);

      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }

      path.close();
      canvas.drawPath(path, fillPaint);
      return;
    }

    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = stroke.filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..isAntiAlias = true;

    if (points.length == 1) {
      final point = points.first;

      canvas.drawPoints(ui.PointMode.points, [
        Offset(point.dx, point.dy),
      ], strokePaint);
      return;
    }

    if (points.length == 2) {
      final path = Path()
        ..moveTo(points[0].dx, points[0].dy)
        ..lineTo(points[1].dx, points[1].dy);

      canvas.drawPath(path, strokePaint);
      return;
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);

    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i == 0 ? points[i] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;

      final control1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );

      final control2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );

      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        p2.dx,
        p2.dy,
      );
    }

    if (stroke.filled) {
      path.close();
    }

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant AnimationCanvasPainter oldDelegate) {
    return true;
  }
}
