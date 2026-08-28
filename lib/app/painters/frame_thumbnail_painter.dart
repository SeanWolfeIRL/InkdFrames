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

    if (allPoints.length == 1) {
      final stroke = strokes.firstWhere((stroke) => stroke.points.isNotEmpty);

      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        (stroke.strokeWidth / 2).clamp(1.0, 4.0),
        Paint()
          ..color = stroke.color
          ..style = PaintingStyle.fill,
      );

      return;
    }

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

    double maxStrokeWidth = 1.0;

    for (final stroke in strokes) {
      if (stroke.strokeWidth > maxStrokeWidth) {
        maxStrokeWidth = stroke.strokeWidth;
      }
    }

    final strokePadding = maxStrokeWidth / 2;

    minX -= strokePadding;
    maxX += strokePadding;
    minY -= strokePadding;
    maxY += strokePadding;

    final drawingWidth = maxX - minX;
    final drawingHeight = maxY - minY;

    if (drawingWidth < 2 && drawingHeight < 2) {
      final stroke = strokes.firstWhere((stroke) => stroke.points.isNotEmpty);

      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        (stroke.strokeWidth / 2).clamp(1.0, 4.0),
        Paint()
          ..color = stroke.color
          ..style = PaintingStyle.fill,
      );

      return;
    }

    final scaleX = drawingWidth == 0 ? 1.0 : size.width / drawingWidth;
    final scaleY = drawingHeight == 0 ? 1.0 : size.height / drawingHeight;

    final scale = (scaleX < scaleY ? scaleX : scaleY) * 0.8;

    final scaledWidth = drawingWidth * scale;
    final scaledHeight = drawingHeight * scale;

    final offsetX = (size.width - scaledWidth) / 2;
    final offsetY = (size.height - scaledHeight) / 2;

    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      if (stroke.points.length == 1) {
        final point = stroke.points.first;

        final center = Offset(
          (point.dx - minX) * scale + offsetX,
          (point.dy - minY) * scale + offsetY,
        );

        final radius = (stroke.strokeWidth * scale / 2).clamp(1.0, 4.0);

        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = stroke.color
            ..style = PaintingStyle.fill,
        );

        continue;
      }

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth * scale < 1
            ? 1
            : stroke.strokeWidth * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = stroke.filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..isAntiAlias = true;

      final path = Path();

      final first = stroke.points.first;
      path.moveTo(
        (first.dx - minX) * scale + offsetX,
        (first.dy - minY) * scale + offsetY,
      );

      for (var i = 1; i < stroke.points.length; i++) {
        final current = stroke.points[i];
        final previous = stroke.points[i - 1];

        final previousX = (previous.dx - minX) * scale + offsetX;
        final previousY = (previous.dy - minY) * scale + offsetY;

        final currentX = (current.dx - minX) * scale + offsetX;
        final currentY = (current.dy - minY) * scale + offsetY;

        final midpointX = (previousX + currentX) / 2;
        final midpointY = (previousY + currentY) / 2;

        path.quadraticBezierTo(previousX, previousY, midpointX, midpointY);
      }

      if (stroke.filled) {
        path.close();
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant FrameThumbnailPainter oldDelegate) {
    return true;
  }
}
