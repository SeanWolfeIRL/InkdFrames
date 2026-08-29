import 'package:flutter/material.dart';

import '../models/vector_stroke.dart';
import 'animation_canvas_painter.dart';

/// Renders Bag assets using the same stroke engine as the Workspace,
/// while fitting the asset bounds into the available preview area.
class BagItemPreviewPainter extends CustomPainter {
  BagItemPreviewPainter({required this.strokes, this.fitFraction = 0.82});

  final List<VectorStroke> strokes;
  final double fitFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final drawableStrokes = strokes
        .where((stroke) => stroke.points.isNotEmpty)
        .toList();

    if (drawableStrokes.isEmpty || size.isEmpty) {
      return;
    }

    final allPoints = drawableStrokes
        .expand((stroke) => stroke.points)
        .toList();

    var minX = allPoints.first.dx;
    var maxX = allPoints.first.dx;
    var minY = allPoints.first.dy;
    var maxY = allPoints.first.dy;

    var maxStrokeWidth = 1.0;

    for (final stroke in drawableStrokes) {
      if (stroke.strokeWidth > maxStrokeWidth) {
        maxStrokeWidth = stroke.strokeWidth;
      }

      for (final point in stroke.points) {
        if (point.dx < minX) minX = point.dx;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dy > maxY) maxY = point.dy;
      }
    }

    // Leave enough room for the widest pressure/stroke edge.
    final padding = (maxStrokeWidth / 2) + 2;

    minX -= padding;
    maxX += padding;
    minY -= padding;
    maxY += padding;

    final drawingWidth = (maxX - minX).clamp(1.0, double.infinity);
    final drawingHeight = (maxY - minY).clamp(1.0, double.infinity);

    final scaleX = (size.width * fitFraction) / drawingWidth;
    final scaleY = (size.height * fitFraction) / drawingHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final sourceCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);

    final targetCenter = Offset(size.width / 2, size.height / 2);

    canvas.save();

    canvas.translate(targetCenter.dx, targetCenter.dy);
    canvas.scale(scale);
    canvas.translate(-sourceCenter.dx, -sourceCenter.dy);

    // IMPORTANT:
    // Delegate the actual stroke rendering to AnimationCanvasPainter.
    // This gives the Bag viewer the same:
    //   • pressure response
    //   • point smoothing
    //   • cubic curves
    //   • rounded caps
    //   • filled paths
    // as the live Workspace.
    AnimationCanvasPainter(
      strokes: drawableStrokes,
      currentStroke: null,
      previousOnionSkinStrokes: const [],
      nextOnionSkinStrokes: const [],
      strokeColor: Colors.white,
      previousOnionSkinColor: Colors.transparent,
      nextOnionSkinColor: Colors.transparent,
      strokeWidth: 1,
      brushType: StrokeBrushType.solid,
      backgroundColor: Colors.transparent,
      paintBackground: false,
    ).paint(canvas, Size(drawingWidth, drawingHeight));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BagItemPreviewPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.fitFraction != fitFraction;
  }
}
