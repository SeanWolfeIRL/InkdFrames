import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/bezier_rig_deformer.dart';
import 'package:inkdframes/app/models/rig_deformer.dart';
import 'package:inkdframes/app/models/vector_point.dart';

void main() {
  test('compare three Flex Rig solvers', () {
    final original = <VectorPoint>[
      for (var i = 0; i <= 20; i++)
        VectorPoint(
          dx: i * 5.0,
          dy: 6 * math.sin(i * math.pi / 5),
          pressure: 0.7,
        ),
    ];

    final controls = <RigControlPoint>[
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
        id: 'flex',
        restX: 50,
        restY: 0,
        x: 45,
        y: 45,
        radius: 100,
      ),
      const RigControlPoint(
        id: 'tip',
        restX: 100,
        restY: 0,
        x: 85,
        y: 65,
        radius: 100,
      ),
    ];

    final results = <String, List<VectorPoint>>{
      'Radial': RigDeformer.deform(original, controls),
      'Bezier': BezierRigDeformer.deform(original, controls),
      'Tangent': BezierRigDeformer.deformWithTangents(original, controls),
    };

    final bezier = results['Bezier']!;
    final tangent = results['Tangent']!;

    var maximumDifference = 0.0;
    var maximumIndex = 0;

    print('=== TANGENT DIFFERENCES ===');

    for (var i = 0; i < original.length; i++) {
      final dx = tangent[i].dx - bezier[i].dx;
      final dy = tangent[i].dy - bezier[i].dy;
      final difference = math.sqrt(dx * dx + dy * dy);

      if (difference > maximumDifference) {
        maximumDifference = difference;
        maximumIndex = i;
      }

      if (difference > 0.001) {
        print('point $i: difference=${difference.toStringAsFixed(4)}');
      }
    }

    print(
      'MAX DIFFERENCE: '
      '${maximumDifference.toStringAsFixed(4)} '
      'at point $maximumIndex',
    );

    for (final entry in results.entries) {
      final points = entry.value;
      print('=== ${entry.key} ===');

      for (final index in [0, 5, 10, 15, 20]) {
        final p = points[index];
        print(
          'point $index: '
          'x=${p.dx.toStringAsFixed(2)} '
          'y=${p.dy.toStringAsFixed(2)}',
        );
      }

      expect(points.length, original.length);
      expect(points.first.dx, closeTo(0, 0.000001));
      expect(points.first.dy, closeTo(0, 0.000001));

      for (final point in points) {
        expect(point.dx.isFinite, isTrue);
        expect(point.dy.isFinite, isTrue);
        expect(point.pressure, 0.7);
      }
    }
  });
}
