import 'dart:math' as math;

import 'vector_point.dart';

/// A control point with an authored position and a displaced position.
class RigControlPoint {
  const RigControlPoint({
    required this.id,
    required this.restX,
    required this.restY,
    required this.x,
    required this.y,
    this.radius = 100.0,
    this.locked = false,
  });

  final String id;
  final double restX;
  final double restY;
  final double x;
  final double y;
  final double radius;
  final bool locked;
}

/// Stateless, non-destructive stroke deformation.
class RigDeformer {
  const RigDeformer._();

  static List<VectorPoint> deform(
    List<VectorPoint> original,
    List<RigControlPoint> controls,
  ) {
    if (controls.isEmpty) {
      return List<VectorPoint>.from(original);
    }

    return original
        .map((point) {
          var dx = 0.0;
          var dy = 0.0;
          var totalWeight = 0.0;
          var lockedWeight = 0.0;

          for (final control in controls) {
            final distance = math.sqrt(
              math.pow(point.dx - control.restX, 2) +
                  math.pow(point.dy - control.restY, 2),
            );

            final radius = math.max(control.radius, 0.001);
            final t = (1.0 - distance / radius).clamp(0.0, 1.0);

            // Smoothstep falloff.
            final weight = t * t * (3.0 - 2.0 * t);

            if (control.locked) {
              lockedWeight = math.max(lockedWeight, weight);
              continue;
            }

            dx += (control.x - control.restX) * weight;
            dy += (control.y - control.restY) * weight;
            totalWeight += weight;
          }

          // The strongest stationary anchor resists displacement.
          // Using max avoids stacking resistance from overlapping anchors.
          final anchorResistance = 1.0 - lockedWeight;

          // Keep combined movable controls from amplifying displacement.
          final normalization = math.max(1.0, totalWeight);

          dx *= anchorResistance;
          dy *= anchorResistance;

          return VectorPoint(
            dx: point.dx + dx / normalization,
            dy: point.dy + dy / normalization,
            pressure: point.pressure,
          );
        })
        .toList(growable: false);
  }
}
