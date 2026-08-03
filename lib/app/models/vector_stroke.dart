import 'vector_point.dart';

class VectorStroke {
  VectorStroke({required List<VectorPoint> points})
    : points = List<VectorPoint>.from(points);

  final List<VectorPoint> points;
}
