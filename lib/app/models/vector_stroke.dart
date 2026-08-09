import 'vector_point.dart';
import 'package:flutter/material.dart';

class VectorStroke {
  VectorStroke({
    required List<VectorPoint> points,
    this.strokeWidth = 4.0,
    this.color = Colors.white,
  }) : points = List<VectorPoint>.from(points);

  final List<VectorPoint> points;
  final double strokeWidth;
  final Color color;

  VectorStroke copy() {
    return VectorStroke(
      points: points.map((point) => point.copy()).toList(),
      strokeWidth: strokeWidth,
      color: color,
    );
  }
}