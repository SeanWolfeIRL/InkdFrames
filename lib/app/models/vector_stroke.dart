import 'package:flutter/material.dart';
import 'dart:math';

import 'vector_point.dart';

enum StrokeBrushType { solid, pressure, graphite }

String _newStrokeId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));

  // RFC 4122 UUID version 4.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

class VectorStroke {
  VectorStroke({
    required List<VectorPoint> points,
    String? id,
    this.strokeWidth = 4.0,
    this.color = Colors.white,
    this.filled = false,
    this.brushType = StrokeBrushType.solid,
    this.alphaLocked = false,
  }) : id = id ?? _newStrokeId(),
       points = List<VectorPoint>.from(points);

  factory VectorStroke.fromJson(Map<String, dynamic> json) {
    final brushTypeName = json['brushType'] as String?;

    final brushType = StrokeBrushType.values.firstWhere(
      (type) => type.name == brushTypeName,
      orElse: () => StrokeBrushType.solid,
    );

    return VectorStroke(
      id: json['id'] as String?,
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
      alphaLocked: json['alphaLocked'] as bool? ?? false,
    );
  }

  final String id;
  final List<VectorPoint> points;
  final double strokeWidth;
  final Color color;
  final bool filled;
  final StrokeBrushType brushType;

  /// True when this stroke was painted while its drawing layer had
  /// Alpha Lock enabled. The renderer can therefore reconstruct the
  /// clipping relationship without rasterising the vector artwork.
  final bool alphaLocked;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'points': points.map((point) => point.toJson()).toList(),
      'strokeWidth': strokeWidth,
      'color': color.toARGB32(),
      'filled': filled,
      'brushType': brushType.name,
      'alphaLocked': alphaLocked,
    };
  }

  VectorStroke copy() {
    return VectorStroke(
      id: id,
      points: points.map((point) => point.copy()).toList(),
      strokeWidth: strokeWidth,
      color: color,
      filled: filled,
      brushType: brushType,
      alphaLocked: alphaLocked,
    );
  }
}
