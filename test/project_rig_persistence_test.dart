import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/character_rig.dart';
import 'package:inkdframes/app/models/inkdframes_project.dart';
import 'package:inkdframes/app/models/rig_deformer.dart';
import 'package:inkdframes/app/models/rig_pose.dart';
import 'package:inkdframes/app/models/stroke_rig.dart';

void main() {
  final rig = CharacterRig(
    id: 'jd-mini',
    targets: [
      CharacterRigTarget(
        id: 'left-leg',
        type: RigTargetType.stroke,
        targetId: 'stroke-left',
        rig: StrokeRig(
          id: 'rig-left',
          strokeId: 'stroke-left',
          controls: [
            RigControlPoint(
              id: 'tip',
              restX: 10,
              restY: 20,
              x: 15,
              y: 25,
              radius: 8,
              locked: false,
            ),
          ],
        ),
      ),
    ],
  );

  const pose = RigPose(
    id: 'wave',
    name: 'Wave',
    characterRigId: 'jd-mini',
    controls: [
      RigControlPose(targetId: 'left-leg', controlId: 'tip', x: 30, y: 40),
    ],
  );

  InkdFramesProject project({
    CharacterRig? characterRig,
    List<RigPose> rigPoses = const [],
  }) => InkdFramesProject(
    id: 'test-project',
    name: 'JD Mini Test',
    fps: 12,
    frames: const [],
    frameDurations: [1],
    characterRig: characterRig,
    rigPoses: rigPoses,
  );

  test('project JSON preserves registered controls and named poses', () {
    final original = project(characterRig: rig, rigPoses: [pose]);

    final restored = InkdFramesProject.fromJson(original.toJson());

    expect(restored.characterRig, isNotNull);
    expect(restored.characterRig!.id, 'jd-mini');
    expect(restored.characterRig!.targets, hasLength(1));

    final control = restored.characterRig!.targets.single.rig.controls.single;

    expect(control.id, 'tip');
    expect(control.restX, 10);
    expect(control.restY, 20);
    expect(control.x, 15);
    expect(control.y, 25);

    expect(restored.rigPoses, hasLength(1));
    expect(restored.rigPoses.single.name, 'Wave');
    expect(restored.rigPoses.single.controls.single.x, 30);
    expect(restored.rigPoses.single.controls.single.y, 40);
  });

  test('older projects without rig fields remain compatible', () {
    final json = project().toJson()
      ..remove('characterRig')
      ..remove('rigPoses');

    final restored = InkdFramesProject.fromJson(json);

    expect(restored.characterRig, isNull);
    expect(restored.rigPoses, isEmpty);
  });
}
