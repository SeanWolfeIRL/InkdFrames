import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/character_rig.dart';
import 'package:inkdframes/app/models/rig_pose_capture.dart';
import 'package:inkdframes/app/models/stroke_rig.dart';
import 'package:inkdframes/app/models/rig_deformer.dart';

void main() {
  StrokeRig makeRig({
    required String strokeId,
    required String controlId,
    required double x,
  }) {
    return StrokeRig(
      id: 'rig-$strokeId',
      strokeId: strokeId,
      controls: [
        RigControlPoint(
          id: controlId,
          restX: 10,
          restY: 20,
          x: x,
          y: 20,
          radius: 12,
          locked: false,
        ),
      ],
    );
  }

  final character = CharacterRig(
    id: 'john-d',
    targets: [
      CharacterRigTarget(
        id: 'target-left',
        type: RigTargetType.stroke,
        targetId: 'left-leg',
        rig: makeRig(strokeId: 'left-leg', controlId: 'left-flex', x: 10),
      ),
      CharacterRigTarget(
        id: 'target-right',
        type: RigTargetType.stroke,
        targetId: 'right-leg',
        rig: makeRig(strokeId: 'right-leg', controlId: 'right-flex', x: 30),
      ),
    ],
  );

  test('captures applied character pose instead of rest pose', () {
    final controls = captureRigPoseControls(
      rig: character,
      activeRigs: {
        'left-leg': makeRig(
          strokeId: 'left-leg',
          controlId: 'left-flex',
          x: 15,
        ),
        'right-leg': makeRig(
          strokeId: 'right-leg',
          controlId: 'right-flex',
          x: 35,
        ),
      },
    );

    expect(controls, isNotNull);
    expect(controls!.length, 2);
    expect(controls[0].targetId, 'target-left');
    expect(controls[0].x, 15);
    expect(controls[1].targetId, 'target-right');
    expect(controls[1].x, 35);
  });

  test('single stroke preview overrides applied character pose', () {
    final controls = captureRigPoseControls(
      rig: character,
      activeRigs: {
        'left-leg': makeRig(
          strokeId: 'left-leg',
          controlId: 'left-flex',
          x: 15,
        ),
        'right-leg': makeRig(
          strokeId: 'right-leg',
          controlId: 'right-flex',
          x: 35,
        ),
      },
      singleStrokePreview: makeRig(
        strokeId: 'left-leg',
        controlId: 'left-flex',
        x: 50,
      ),
    );

    expect(controls, isNotNull);
    expect(controls![0].x, 50);
    expect(controls[1].x, 35);
  });

  test('rejects mismatched control IDs', () {
    final controls = captureRigPoseControls(
      rig: character,
      activeRigs: {
        'left-leg': makeRig(
          strokeId: 'left-leg',
          controlId: 'wrong-control',
          x: 99,
        ),
      },
    );

    expect(controls, isNull);
  });

  test('uses registered controls when no preview exists', () {
    final controls = captureRigPoseControls(
      rig: character,
      activeRigs: const <String, StrokeRig>{},
    );

    expect(controls, isNotNull);
    expect(controls![0].x, 10);
    expect(controls[1].x, 30);
  });
}
