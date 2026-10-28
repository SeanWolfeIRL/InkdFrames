import 'dart:math' as math;

import 'rig_deformer.dart';
import 'vector_point.dart';

/// Experimental curve-guided deformation.
///
/// Controls are ordered root, flex, tip. The original geometry
/// is preserved; each point receives the displacement between
/// the rest and posed quadratic Bezier curves.
class BezierRigDeformer {
  const BezierRigDeformer._();

  /// Experimental tangent-aware curve deformation.
  ///
  /// Retains each point's local offset from the rest curve,
  /// then rotates that offset into the posed curve's frame.
  static List<VectorPoint> deformWithTangents(
    List<VectorPoint> original,
    List<RigControlPoint> controls,
  ) {
    if (original.length < 2 || controls.length != 3) {
      return List<VectorPoint>.from(original);
    }

    final lengths = <double>[0];
    var total = 0.0;

    for (var i = 1; i < original.length; i++) {
      final dx = original[i].dx - original[i - 1].dx;
      final dy = original[i].dy - original[i - 1].dy;
      total += math.sqrt(dx * dx + dy * dy);
      lengths.add(total);
    }

    if (total <= 0.000001) {
      return List<VectorPoint>.from(original);
    }

    final root = controls[0];
    final flex = controls[1];
    final tip = controls[2];

    double targetX(RigControlPoint c) => c.locked ? c.restX : c.x;
    double targetY(RigControlPoint c) => c.locked ? c.restY : c.y;

    final rest = [
      [root.restX, root.restY],
      [flex.restX, flex.restY],
      [tip.restX, tip.restY],
    ];

    final posed = [
      [targetX(root), targetY(root)],
      [targetX(flex), targetY(flex)],
      [targetX(tip), targetY(tip)],
    ];

    if (List.generate(
      3,
      (i) => rest[i][0] == posed[i][0] && rest[i][1] == posed[i][1],
    ).every((same) => same)) {
      return List<VectorPoint>.from(original);
    }

    List<double> position(List<List<double>> c, double t) {
      final u = 1.0 - t;
      return [
        u * u * c[0][0] + 2 * u * t * c[1][0] + t * t * c[2][0],
        u * u * c[0][1] + 2 * u * t * c[1][1] + t * t * c[2][1],
      ];
    }

    List<double> tangent(List<List<double>> c, double t) {
      final dx =
          2 * (1 - t) * (c[1][0] - c[0][0]) + 2 * t * (c[2][0] - c[1][0]);
      final dy =
          2 * (1 - t) * (c[1][1] - c[0][1]) + 2 * t * (c[2][1] - c[1][1]);

      final length = math.sqrt(dx * dx + dy * dy);
      if (length <= 0.000001) {
        final chordX = c[2][0] - c[0][0];
        final chordY = c[2][1] - c[0][1];
        final chordLength = math.sqrt(chordX * chordX + chordY * chordY);
        if (chordLength <= 0.000001) {
          return [1.0, 0.0];
        }
        return [chordX / chordLength, chordY / chordLength];
      }
      return [dx / length, dy / length];
    }

    return List<VectorPoint>.generate(original.length, (i) {
      final point = original[i];
      final t = lengths[i] / total;

      final a = position(rest, t);
      final b = position(posed, t);
      final ta = tangent(rest, t);
      final tb = tangent(posed, t);

      final offsetX = point.dx - a[0];
      final offsetY = point.dy - a[1];

      final along = offsetX * ta[0] + offsetY * ta[1];
      final across = -offsetX * ta[1] + offsetY * ta[0];

      return VectorPoint(
        dx: b[0] + along * tb[0] - across * tb[1],
        dy: b[1] + along * tb[1] + across * tb[0],
        pressure: point.pressure,
      );
    }, growable: false);
  }

  static List<VectorPoint> deform(
    List<VectorPoint> original,
    List<RigControlPoint> controls,
  ) {
    if (original.length < 2 || controls.length != 3) {
      return List<VectorPoint>.from(original);
    }

    final lengths = <double>[0];
    var total = 0.0;

    for (var i = 1; i < original.length; i++) {
      total += math.sqrt(
        math.pow(original[i].dx - original[i - 1].dx, 2) +
            math.pow(original[i].dy - original[i - 1].dy, 2),
      );
      lengths.add(total);
    }

    if (total <= 0.000001) {
      return List<VectorPoint>.from(original);
    }

    double curve(double a, double b, double c, double t) {
      final u = 1.0 - t;
      return u * u * a + 2.0 * u * t * b + t * t * c;
    }

    final root = controls[0];
    final flex = controls[1];
    final tip = controls[2];

    // Locked controls remain at their authored rest positions.
    double targetX(RigControlPoint c) => c.locked ? c.restX : c.x;
    double targetY(RigControlPoint c) => c.locked ? c.restY : c.y;

    return List<VectorPoint>.generate(original.length, (i) {
      final point = original[i];
      final t = lengths[i] / total;

      final restX = curve(root.restX, flex.restX, tip.restX, t);
      final restY = curve(root.restY, flex.restY, tip.restY, t);

      final posedX = curve(targetX(root), targetX(flex), targetX(tip), t);
      final posedY = curve(targetY(root), targetY(flex), targetY(tip), t);

      return VectorPoint(
        dx: point.dx + posedX - restX,
        dy: point.dy + posedY - restY,
        pressure: point.pressure,
      );
    }, growable: false);
  }
}
