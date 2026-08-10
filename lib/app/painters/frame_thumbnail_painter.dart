import 'package:flutter/material.dart';

import '../models/vector_stroke.dart';

class FrameThumbnailPainter extends CustomPainter {
  FrameThumbnailPainter({required this.strokes});

  final List<VectorStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;

    final allPoints = strokes.expand((stroke) => stroke.points).toList();

    if (allPoints.isEmpty) return;

    double minX = allPoints.first.dx;
    double maxX = allPoints.first.dx;
    double minY = allPoints.first.dy;
    double maxY = allPoints.first.dy;

    for (final point in allPoints) {
      if (point.dx < minX) minX = point.dx;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dy > maxY) maxY = point.dy;
    }

    final drawingWidth = maxX - minX;
    final drawingHeight = maxY - minY;

    final scaleX = drawingWidth == 0 ? 1.0 : size.width / drawingWidth;
    final scaleY = drawingHeight == 0 ? 1.0 : size.height / drawingHeight;

    final scale = (scaleX < scaleY ? scaleX : scaleY) * 0.8;

    final scaledWidth = drawingWidth * scale;
    final scaledHeight = drawingHeight * scale;

    final offsetX = (size.width - scaledWidth) / 2;
    final offsetY = (size.height - scaledHeight) / 2;

    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth * scale < 1
            ? 1
            : stroke.strokeWidth * scale
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final path = Path();

      final first = stroke.points.first;
      path.moveTo(
        (first.dx - minX) * scale + offsetX,
        (first.dy - minY) * scale + offsetY,
      );

      for (var i = 1; i < stroke.points.length; i++) {
        final point = stroke.points[i];

        path.lineTo(
          (point.dx - minX) * scale + offsetX,
          (point.dy - minY) * scale + offsetY,
        );
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant FrameThumbnailPainter oldDelegate) {
    return true;
  }
}
