import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/vector_point.dart';
import '../models/vector_stroke.dart';

class AnimationCanvasPainter extends CustomPainter {
  AnimationCanvasPainter({
    required this.strokes,
    required this.currentStroke,
    required this.previousOnionSkinStrokes,
    required this.nextOnionSkinStrokes,
    required this.strokeColor,
    required this.previousOnionSkinColor,
    required this.nextOnionSkinColor,
    required this.strokeWidth,
  });

  final List<VectorStroke> strokes;
  final List<VectorPoint>? currentStroke;

  final List<VectorStroke> previousOnionSkinStrokes;
  final List<VectorStroke> nextOnionSkinStrokes;

  final Color strokeColor;
  final Color previousOnionSkinColor;
  final Color nextOnionSkinColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = const Color(0xFF1F1B24)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Offset.zero & size, backgroundPaint);

    // Current saved frame.
    for (final stroke in strokes) {
      _paintStroke(canvas, stroke, stroke.color);
    }

    // Current stroke being drawn.
    if (currentStroke != null && currentStroke!.isNotEmpty) {
      _paintStroke(
        canvas,
        VectorStroke(points: currentStroke!, strokeWidth: strokeWidth),
        strokeColor,
      );
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

  void _paintStroke(Canvas canvas, VectorStroke stroke, Color color) {
    final points = _smoothPoints(stroke.points);

    if (points.isEmpty) {
      return;
    }

    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
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

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant AnimationCanvasPainter oldDelegate) {
    return true;
  }
}
