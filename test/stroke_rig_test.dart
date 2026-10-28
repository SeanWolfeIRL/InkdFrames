import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/rig_deformer.dart';
import 'package:inkdframes/app/models/stroke_rig.dart';
import 'package:inkdframes/app/models/vector_point.dart';

void main() {
  group('StrokeRig', () {
    test('places handles by arc length, not sample count', () {
      final rig = StrokeRig.fromStroke(
        id: 'rig1',
        strokeId: 'stroke1',
        points: [
          VectorPoint(dx: 0, dy: 0, pressure: 1.0),
          VectorPoint(dx: 1, dy: 0, pressure: 1.0),
          VectorPoint(dx: 2, dy: 0, pressure: 1.0),
          VectorPoint(dx: 100, dy: 0, pressure: 1.0),
        ],
      );

      expect(rig.controls.length, 3);
      expect(rig.controls[0].restX, 0);
      expect(rig.controls[1].restX, closeTo(50, 0.0001));
      expect(rig.controls[2].restX, 100);
      expect(rig.controls[0].locked, isTrue);
      expect(rig.controls[1].locked, isFalse);
      expect(rig.controls[2].locked, isFalse);
      expect(rig.controls.map((control) => control.id).toSet().length, 3);
    });

    test('round-trips through JSON', () {
      final rig = StrokeRig.fromStroke(
        id: 'rig2',
        strokeId: 'stroke2',
        points: [
          VectorPoint(dx: 0, dy: 0, pressure: 1.0),
          VectorPoint(dx: 80, dy: 40, pressure: 1.0),
        ],
      );

      final restored = StrokeRig.fromJson(rig.toJson());

      expect(restored.id, rig.id);
      expect(restored.strokeId, rig.strokeId);
      expect(restored.controls.length, 3);

      for (var i = 0; i < 3; i++) {
        expect(restored.controls[i].id, rig.controls[i].id);
        expect(restored.controls[i].restX, rig.controls[i].restX);
        expect(restored.controls[i].restY, rig.controls[i].restY);
        expect(restored.controls[i].x, rig.controls[i].x);
        expect(restored.controls[i].y, rig.controls[i].y);
        expect(restored.controls[i].radius, rig.controls[i].radius);
        expect(restored.controls[i].locked, rig.controls[i].locked);
      }
    });

    test('does not generate handles for degenerate strokes', () {
      for (final points in [
        <VectorPoint>[],
        [VectorPoint(dx: 5, dy: 5, pressure: 1.0)],
        [
          VectorPoint(dx: 5, dy: 5, pressure: 1.0),
          VectorPoint(dx: 5, dy: 5, pressure: 1.0),
        ],
      ]) {
        final rig = StrokeRig.fromStroke(
          id: 'empty',
          strokeId: 'stroke',
          points: points,
        );

        expect(rig.controls, isEmpty);
      }
    });
  });

  group('RigDeformer', () {
    test('locked root remains fixed', () {
      final points = [
        const VectorPoint(dx: 0, dy: 0, pressure: 1),
        const VectorPoint(dx: 25, dy: 0, pressure: 1),
        const VectorPoint(dx: 50, dy: 0, pressure: 1),
        const VectorPoint(dx: 100, dy: 0, pressure: 1),
      ];

      final result = RigDeformer.deform(points, [
        const RigControlPoint(
          id: 'root',
          restX: 0,
          restY: 0,
          x: 0,
          y: 0,
          radius: 100,
          locked: true,
        ),
        const RigControlPoint(
          id: 'tip',
          restX: 100,
          restY: 0,
          x: 100,
          y: 40,
          radius: 150,
        ),
      ]);

      expect(result.first.dx, 0);
      expect(result.first.dy, 0);
      expect(result.last.dy, greaterThan(0));
    });

    test('bends smoothly between root and tip', () {
      final points = [
        for (var x = 0; x <= 100; x += 25)
          VectorPoint(dx: x.toDouble(), dy: 0, pressure: 1),
      ];

      final result = RigDeformer.deform(points, [
        const RigControlPoint(
          id: 'root',
          restX: 0,
          restY: 0,
          x: 0,
          y: 0,
          radius: 100,
          locked: true,
        ),
        const RigControlPoint(
          id: 'tip',
          restX: 100,
          restY: 0,
          x: 100,
          y: 40,
          radius: 150,
        ),
      ]);

      expect(result.first.dy, 0);
      expect(result[1].dy, greaterThan(0));
      expect(result[2].dy, greaterThan(result[1].dy));
      expect(result[3].dy, greaterThan(result[2].dy));
    });

    test('overlapping movable controls do not amplify movement', () {
      final points = [const VectorPoint(dx: 50, dy: 0, pressure: 0.6)];

      final result = RigDeformer.deform(points, [
        const RigControlPoint(
          id: 'a',
          restX: 50,
          restY: 0,
          x: 50,
          y: 40,
          radius: 100,
        ),
        const RigControlPoint(
          id: 'b',
          restX: 50,
          restY: 0,
          x: 50,
          y: 40,
          radius: 100,
        ),
      ]);

      expect(result.single.dy, closeTo(40, 0.000001));
      expect(result.single.pressure, 0.6);
    });

    test('preserves pressure and original geometry', () {
      final original = [
        VectorPoint(dx: 0, dy: 0, pressure: 0.3),
        VectorPoint(dx: 50, dy: 0, pressure: 0.7),
        VectorPoint(dx: 200, dy: 0, pressure: 1.0),
      ];

      final result = RigDeformer.deform(original, [
        RigControlPoint(
          id: 'flex',
          restX: 50,
          restY: 0,
          x: 50,
          y: 40,
          radius: 100,
        ),
      ]);

      expect(result[1].dy, 40);
      expect(result[2].dy, 0);
      expect(result[1].pressure, 0.7);
      expect(original[1].dy, 0);
    });
  });
}
