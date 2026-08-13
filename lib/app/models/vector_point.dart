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
    return VectorPoint(dx: dx, dy: dy, pressure: pressure);
  }

  Map<String, dynamic> toJson() {
    return {'dx': dx, 'dy': dy, 'pressure': pressure};
  }

  factory VectorPoint.fromJson(Map<String, dynamic> json) {
    return VectorPoint(
      dx: (json['dx'] as num).toDouble(),
      dy: (json['dy'] as num).toDouble(),
      pressure: (json['pressure'] as num).toDouble(),
    );
  }
}
