import 'vector_point.dart';

class VectorStroke {
  VectorStroke({required List<VectorPoint> points})
    : points = List<VectorPoint>.from(points);

  final List<VectorPoint> points;

  VectorStroke copy() {
      return VectorStroke(
          points: points.map((point) => point.copy()).toList(),
        );
     }
}