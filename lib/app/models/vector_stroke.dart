import 'package:flutter/material.dart';

import 'vector_point.dart';

enum StrokeBrushType { solid, pressure }

class VectorStroke {
  VectorStroke({
    required List<VectorPoint> points,
    this.strokeWidth = 4.0,
    this.color = Colors.white,
    this.filled = false,
    this.brushType = StrokeBrushType.solid,
  }) : points = List<VectorPoint>.from(points);

  factory VectorStroke.fromJson(Map<String, dynamic> json) {
    final brushTypeName = json['brushType'] as String?;

    final brushType = StrokeBrushType.values.firstWhere(
      (type) => type.name == brushTypeName,
      orElse: () => StrokeBrushType.solid,
    );

    return VectorStroke(
      points: (json['points'] as List)
          .map(
            (point) =>
                VectorPoint.fromJson(Map<String, dynamic>.from(point as Map)),
          )
          .toList(),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      color: Color(json['color'] as int),
      filled: json['filled'] as bool? ?? false,
      brushType: brushType,
    );
  }

  final List<VectorPoint> points;
  final double strokeWidth;
  final Color color;
  final bool filled;
  final StrokeBrushType brushType;

  Map<String, dynamic> toJson() {
    return {
      'points': points.map((point) => point.toJson()).toList(),
      'strokeWidth': strokeWidth,
      'color': color.toARGB32(),
      'filled': filled,
      'brushType': brushType.name,
    };
  }

  VectorStroke copy() {
    return VectorStroke(
      points: points.map((point) => point.copy()).toList(),
      strokeWidth: strokeWidth,
      color: color,
      filled: filled,
      brushType: brushType,
    );
  }
}
