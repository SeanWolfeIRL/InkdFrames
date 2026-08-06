import 'vector_point.dart';

class VectorStroke {
  VectorStroke({
    required List<VectorPoint> points,
    this.strokeWidth = 4.0,
  }) : points = List<VectorPoint>.from(points);

  final List<VectorPoint> points;
  final double strokeWidth;

  VectorStroke copy() {
    return VectorStroke(
      points: points.map((point) => point.copy()).toList(),
      strokeWidth: strokeWidth,
    );
  }
}