import 'vector_point.dart';
import 'package:flutter/material.dart';

class VectorStroke {
  VectorStroke({
    required List<VectorPoint> points,
    this.strokeWidth = 4.0,
    this.color = Colors.white,
  }) : points = List<VectorPoint>.from(points);

  factory VectorStroke.fromJson(Map<String, dynamic> json) {
    return VectorStroke(
      points: (json['points'] as List)
          .map(
            (point) =>
                VectorPoint.fromJson(Map<String, dynamic>.from(point as Map)),
          )
          .toList(),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      color: Color(json['color'] as int),
    );
  }

  final List<VectorPoint> points;
  final double strokeWidth;
  final Color color;

  Map<String, dynamic> toJson() {
    return {
      'points': points.map((point) => point.toJson()).toList(),
      'strokeWidth': strokeWidth,
      'color': color.toARGB32(),
    };
  }

  VectorStroke copy() {
    return VectorStroke(
      points: points.map((point) => point.copy()).toList(),
      strokeWidth: strokeWidth,
      color: color,
    );
  }
}
