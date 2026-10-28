import 'dart:math' as math;

import 'rig_deformer.dart';
import 'vector_point.dart';

/// A reusable rig definition for one vector stroke.
///
/// Frame-specific control positions can be introduced separately.
class StrokeRig {
  const StrokeRig({
    required this.id,
    required this.strokeId,
    required this.controls,
  });

  final String id;
  final String strokeId;
  final List<RigControlPoint> controls;

  /// Generate root, middle and tip handles by arc length.
  ///
  /// Degenerate strokes are left without handles rather than
  /// generating overlapping controls.
  static StrokeRig fromStroke({
    required String id,
    required String strokeId,
    required List<VectorPoint> points,
  }) {
    if (points.length < 2) {
      return StrokeRig(id: id, strokeId: strokeId, controls: const []);
    }

    final lengths = <double>[0];
    var total = 0.0;

    for (var i = 1; i < points.length; i++) {
      total += math.sqrt(
        math.pow(points[i].dx - points[i - 1].dx, 2) +
            math.pow(points[i].dy - points[i - 1].dy, 2),
      );
      lengths.add(total);
    }

    if (total <= 0.000001) {
      return StrokeRig(id: id, strokeId: strokeId, controls: const []);
    }

    VectorPoint atFraction(double fraction) {
      final target = total * fraction;

      for (var i = 1; i < points.length; i++) {
        if (lengths[i] < target) continue;

        final segment = lengths[i] - lengths[i - 1];
        if (segment <= 0) continue;

        final t = ((target - lengths[i - 1]) / segment).clamp(0.0, 1.0);

        return VectorPoint(
          dx: points[i - 1].dx + (points[i].dx - points[i - 1].dx) * t,
          dy: points[i - 1].dy + (points[i].dy - points[i - 1].dy) * t,
          pressure:
              points[i - 1].pressure +
              (points[i].pressure - points[i - 1].pressure) * t,
        );
      }

      return points.last.copy();
    }

    final radius = math.max(1.0, total * 0.6);
    final fractions = [0.0, 0.5, 1.0];
    final names = ['root', 'flex', 'tip'];

    final controls = <RigControlPoint>[];

    for (var i = 0; i < fractions.length; i++) {
      final point = atFraction(fractions[i]);

      controls.add(
        RigControlPoint(
          id: '${id}_${names[i]}',
          restX: point.dx,
          restY: point.dy,
          x: point.dx,
          y: point.dy,
          radius: radius,
          locked: i == 0,
        ),
      );
    }

    return StrokeRig(id: id, strokeId: strokeId, controls: controls);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'strokeId': strokeId,
    'controls': controls
        .map(
          (control) => {
            'id': control.id,
            'restX': control.restX,
            'restY': control.restY,
            'x': control.x,
            'y': control.y,
            'radius': control.radius,
            'locked': control.locked,
          },
        )
        .toList(),
  };

  factory StrokeRig.fromJson(Map<String, dynamic> json) {
    return StrokeRig(
      id: json['id'] as String,
      strokeId: json['strokeId'] as String,
      controls: (json['controls'] as List).map((raw) {
        final control = Map<String, dynamic>.from(raw as Map);

        return RigControlPoint(
          id: control['id'] as String,
          restX: (control['restX'] as num).toDouble(),
          restY: (control['restY'] as num).toDouble(),
          x: (control['x'] as num).toDouble(),
          y: (control['y'] as num).toDouble(),
          radius: (control['radius'] as num).toDouble(),
          locked: control['locked'] as bool? ?? false,
        );
      }).toList(),
    );
  }
}
