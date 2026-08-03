class VectorPoint {
  const VectorPoint({
    required this.dx,
    required this.dy,
    required this.pressure,
  });

  final double dx;
  final double dy;
  final double pressure;

  VectorPoint copy() {
    return VectorPoint(
      dx: dx,
      dy: dy,
      pressure: pressure,
    );
  }
}
