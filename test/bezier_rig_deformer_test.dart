import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/bezier_rig_deformer.dart';
import 'package:inkdframes/app/models/rig_deformer.dart';
import 'package:inkdframes/app/models/stroke_rig.dart';
import 'package:inkdframes/app/models/vector_point.dart';

void main() {
  final straight = <VectorPoint>[
    for (var x = 0; x <= 100; x += 25)
      VectorPoint(dx: x.toDouble(), dy: 0, pressure: x / 100),
  ];

  StrokeRig makeRig(List<VectorPoint> points) => StrokeRig.fromStroke(
    id: 'test-rig',
    strokeId: 'test-stroke',
    points: points,
  );

  List<RigControlPoint> pose(
    StrokeRig rig, {
    double flexY = 0,
    double tipX = 100,
    double tipY = 0,
  }) {
    return [
      rig.controls[0],
      RigControlPoint(
        id: rig.controls[1].id,
        restX: rig.controls[1].restX,
        restY: rig.controls[1].restY,
        x: rig.controls[1].restX,
        y: rig.controls[1].restY + flexY,
      ),
      RigControlPoint(
        id: rig.controls[2].id,
        restX: rig.controls[2].restX,
        restY: rig.controls[2].restY,
        x: tipX,
        y: tipY,
      ),
    ];
  }

  group('BezierRigDeformer', () {
    test('rest pose reproduces original points exactly', () {
      final original = [
        const VectorPoint(dx: 0, dy: 0, pressure: 0.2),
        const VectorPoint(dx: 20, dy: 15, pressure: 0.5),
        const VectorPoint(dx: 70, dy: -10, pressure: 0.8),
        const VectorPoint(dx: 100, dy: 0, pressure: 1),
      ];

      final result = BezierRigDeformer.deform(
        original,
        makeRig(original).controls,
      );

      for (var i = 0; i < original.length; i++) {
        expect(result[i].dx, closeTo(original[i].dx, 0.000001));
        expect(result[i].dy, closeTo(original[i].dy, 0.000001));
        expect(result[i].pressure, original[i].pressure);
      }
    });

    test('locked root stays fixed when flex and tip move', () {
      final result = BezierRigDeformer.deform(
        straight,
        pose(makeRig(straight), flexY: 60, tipY: 40),
      );

      expect(result.first.dx, 0);
      expect(result.first.dy, 0);
      expect(result.last.dy, closeTo(40, 0.000001));
    });

    test('moving flex creates a smooth middle bend', () {
      final result = BezierRigDeformer.deform(
        straight,
        pose(makeRig(straight), flexY: 60),
      );

      expect(result.first.dy, 0);
      expect(result[1].dy, closeTo(22.5, 0.000001));
      expect(result[2].dy, closeTo(30, 0.000001));
      expect(result[3].dy, closeTo(22.5, 0.000001));
      expect(result.last.dy, 0);
    });

    test('tip displacement reaches endpoint without moving root', () {
      final result = BezierRigDeformer.deform(
        straight,
        pose(makeRig(straight), tipX: 130, tipY: 50),
      );

      expect(result.first.dx, 0);
      expect(result.first.dy, 0);
      expect(result.last.dx, closeTo(130, 0.000001));
      expect(result.last.dy, closeTo(50, 0.000001));
    });

    test('preserves original curved detail and source geometry', () {
      final original = [
        const VectorPoint(dx: 0, dy: 0, pressure: 0.3),
        const VectorPoint(dx: 25, dy: 12, pressure: 0.5),
        const VectorPoint(dx: 50, dy: -8, pressure: 0.7),
        const VectorPoint(dx: 75, dy: 10, pressure: 0.9),
        const VectorPoint(dx: 100, dy: 0, pressure: 1),
      ];

      final rig = makeRig(original);
      final controls = pose(rig, flexY: 40);
      final result = BezierRigDeformer.deform(original, controls);

      expect(result.length, original.length);
      expect(result.first.dx, original.first.dx);
      expect(result.first.dy, original.first.dy);
      expect(result.last.dx, original.last.dx);
      expect(result.last.dy, original.last.dy);

      expect(result[2].dy, greaterThan(original[2].dy));
      expect(original[2].dy, -8);

      for (var i = 0; i < original.length; i++) {
        expect(result[i].pressure, original[i].pressure);
      }
    });
  });
}
