import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/vector_point.dart';
import '../models/vector_stroke.dart';

class AnimationCanvasPainter extends CustomPainter {
  AnimationCanvasPainter({
    required this.strokes,
    required this.currentStroke,
    required this.onionSkinStroke,
    required this.strokeColor,
    required this.onionSkinColor,
  });

  final List<VectorStroke> strokes;
  final List<VectorPoint>? currentStroke;
  final VectorStroke? onionSkinStroke;
  final Color strokeColor;
  final Color onionSkinColor;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = const Color(0xFF1F1B24)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    for (final stroke in strokes) {
      _paintStroke(canvas, stroke.points, strokeColor);
    }

    if (currentStroke != null && currentStroke!.isNotEmpty) {
      _paintStroke(canvas, currentStroke!, strokeColor);
    }

    if (onionSkinStroke != null && onionSkinStroke!.points.isNotEmpty) {
      _paintStroke(canvas, onionSkinStroke!.points, onionSkinColor);
    }
  }

  void _paintStroke(Canvas canvas, List<VectorPoint> points, Color color) {
    if (points.length < 2) {
      final point = points.first;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawPoints(ui.PointMode.points, [
        Offset(point.dx, point.dy),
      ], paint);
      return;
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      path.lineTo(current.dx, current.dy);
      if (previous.pressure > 0 && current.pressure > 0) {
        final width = 1.5 + (current.pressure * 2.5);
        paint.strokeWidth = width;
        canvas.drawLine(
          Offset(previous.dx, previous.dy),
          Offset(current.dx, current.dy),
          paint,
        );
      }
    }

    if (path.getBounds().size != Size.zero) {
      final strokePaint = Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant AnimationCanvasPainter oldDelegate) {
    return true;
  }
}
