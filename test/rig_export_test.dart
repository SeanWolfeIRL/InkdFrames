import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/character_rig.dart';
import 'package:inkdframes/app/models/composite_asset.dart';
import 'package:inkdframes/app/models/rig_export.dart';
import 'package:inkdframes/app/models/rig_pose.dart';
import 'package:inkdframes/app/models/stroke_rig.dart';

void main() {
  CompositeNode limb(String id) => CompositeNode(
    type: 'layer',
    id: 'layer-$id',
    name: id,
    payload: {
      'frames': [
        [
          {'id': id},
        ],
      ],
    },
  );

  CompositeAsset asset(List<CompositeNode> children) => CompositeAsset(
    version: 1,
    canvasWidth: 1920,
    canvasHeight: 1080,
    root: CompositeNode(
      type: 'group',
      id: 'spider',
      name: 'Spider',
      children: children,
    ),
  );

  CharacterRigTarget target(String id) => CharacterRigTarget(
    id: 'rig-$id',
    type: RigTargetType.stroke,
    targetId: id,
    rig: StrokeRig(id: 'stroke-rig-$id', strokeId: id, controls: const []),
  );

  final rig = CharacterRig(
    id: 'spider-rig',
    targets: [target('leg1'), target('leg2')],
  );

  const pose = RigPose(
    id: 'test',
    name: 'Test',
    characterRigId: 'spider-rig',
    controls: [
      RigControlPose(targetId: 'rig-leg1', controlId: 'tip', x: 10, y: 20),
      RigControlPose(targetId: 'rig-leg2', controlId: 'tip', x: 30, y: 40),
    ],
  );

  test('full export preserves both rig targets and pose controls', () {
    final result = captureRigExport(asset([limb('leg1'), limb('leg2')]), rig, [
      pose,
    ]);

    expect(result.rig!.targets, hasLength(2));
    expect(result.poses, hasLength(1));
    expect(result.poses.single.controls, hasLength(2));
  });

  test('partial export preserves only included limb controls', () {
    final result = captureRigExport(asset([limb('leg1')]), rig, [pose]);

    expect(result.rig!.targets, hasLength(1));
    expect(result.rig!.targets.single.targetId, 'leg1');
    expect(result.poses.single.controls, hasLength(1));
    expect(result.poses.single.controls.single.targetId, 'rig-leg1');
  });

  test('unrelated group exports no character rig', () {
    final result = captureRigExport(asset([limb('unrelated')]), rig, [pose]);

    expect(result.rig, isNull);
    expect(result.poses, isEmpty);
  });
}
