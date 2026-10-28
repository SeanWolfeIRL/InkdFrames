import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/bezier_rig_deformer.dart';
import 'package:inkdframes/app/models/rig_deformer.dart';
import 'package:inkdframes/app/models/stroke_rig.dart';
import 'package:inkdframes/app/models/vector_point.dart';

void main() {
  final straight = <VectorPoint>[
    for (var x = 0; x <= 100; x += 25)
      VectorPoint(dx: x.toDouble(), dy: 0, pressure: 0.6),
  ];

  List<RigControlPoint> controls({
    double flexX = 50,
    double flexY = 0,
    double tipX = 100,
    double tipY = 0,
  }) => [
    const RigControlPoint(
      id: 'root',
      restX: 0,
      restY: 0,
      x: 0,
      y: 0,
      locked: true,
    ),
    RigControlPoint(id: 'flex', restX: 50, restY: 0, x: flexX, y: flexY),
    RigControlPoint(id: 'tip', restX: 100, restY: 0, x: tipX, y: tipY),
  ];

  group('Tangent-aware Bézier', () {
    test('unchanged controls preserve every original point', () {
      final original = [
        const VectorPoint(dx: 0, dy: 0, pressure: 0.2),
        const VectorPoint(dx: 25, dy: 15, pressure: 0.5),
        const VectorPoint(dx: 50, dy: -10, pressure: 0.8),
        const VectorPoint(dx: 100, dy: 0, pressure: 1),
      ];

      final rig = StrokeRig.fromStroke(
        id: 'rest',
        strokeId: 'stroke',
        points: original,
      );

      final result = BezierRigDeformer.deformWithTangents(
        original,
        rig.controls,
      );

      for (var i = 0; i < original.length; i++) {
        expect(result[i].dx, original[i].dx);
        expect(result[i].dy, original[i].dy);
        expect(result[i].pressure, original[i].pressure);
      }
    });

    test('locked root and moved tip remain anchored', () {
      final result = BezierRigDeformer.deformWithTangents(
        straight,
        controls(flexY: 60, tipX: 130, tipY: 40),
      );

      expect(result.first.dx, closeTo(0, 0.000001));
      expect(result.first.dy, closeTo(0, 0.000001));
      expect(result.last.dx, closeTo(130, 0.000001));
      expect(result.last.dy, closeTo(40, 0.000001));
    });

    test('rotates local detail when curve changes direction', () {
      final original = [
        const VectorPoint(dx: 0, dy: 0, pressure: 1),
        const VectorPoint(dx: 25, dy: 0, pressure: 1),
        const VectorPoint(dx: 50, dy: 10, pressure: 0.5),
        const VectorPoint(dx: 75, dy: 0, pressure: 1),
        const VectorPoint(dx: 100, dy: 0, pressure: 1),
      ];

      final pose = controls(flexY: 65);
      final translated = BezierRigDeformer.deform(original, pose);
      final rotated = BezierRigDeformer.deformWithTangents(original, pose);

      expect(rotated.length, original.length);
      expect(rotated[2].pressure, 0.5);

      final difference = math.sqrt(
        math.pow(rotated[1].dx - translated[1].dx, 2) +
            math.pow(rotated[1].dy - translated[1].dy, 2),
      );
      expect(difference, greaterThan(0.001));
    });

    test('reversed tip remains finite', () {
      final result = BezierRigDeformer.deformWithTangents(
        straight,
        controls(flexX: 20, flexY: 70, tipX: -30, tipY: 15),
      );

      for (final point in result) {
        expect(point.dx.isFinite, isTrue);
        expect(point.dy.isFinite, isTrue);
      }

      expect(result.last.dx, closeTo(-30, 0.000001));
      expect(result.last.dy, closeTo(15, 0.000001));
    });

    test('collapsed posed curve remains finite', () {
      final result = BezierRigDeformer.deformWithTangents(
        straight,
        controls(flexX: 0, flexY: 0, tipX: 0, tipY: 0),
      );

      for (final point in result) {
        expect(point.dx.isFinite, isTrue);
        expect(point.dy.isFinite, isTrue);
        expect(point.pressure, 0.6);
      }
    });

    test('degenerate original geometry remains unchanged', () {
      final original = [
        const VectorPoint(dx: 5, dy: 5, pressure: 0.4),
        const VectorPoint(dx: 5, dy: 5, pressure: 0.8),
      ];

      final result = BezierRigDeformer.deformWithTangents(
        original,
        controls(flexY: 50),
      );

      expect(result[0].dx, 5);
      expect(result[0].dy, 5);
      expect(result[1].dx, 5);
      expect(result[1].dy, 5);
    });
  });
}
