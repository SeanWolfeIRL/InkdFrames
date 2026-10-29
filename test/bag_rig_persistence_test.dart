import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/bag_item.dart';
import 'package:inkdframes/app/models/character_rig.dart';
import 'package:inkdframes/app/models/rig_pose.dart';

void main() {
  BagItem makeItem({CharacterRig? rig, List<RigPose> poses = const []}) {
    return BagItem(
      id: 'john-d',
      name: 'John D',
      sourceGroupName: 'Spider',
      layers: const [],
      createdAt: DateTime.utc(2026, 10, 28),
      characterRig: rig,
      rigPoses: poses,
    );
  }

  test('Bag item preserves rig and named poses', () {
    const rig = CharacterRig(id: 'john-d-rig');

    const pose = RigPose(
      id: 'crouch',
      name: 'Crouch',
      characterRigId: 'john-d-rig',
      controls: [
        RigControlPose(
          targetId: 'front-left-leg',
          controlId: 'flex',
          x: 25,
          y: 45,
        ),
      ],
    );

    final original = makeItem(rig: rig, poses: [pose]);

    final restored = BagItem.fromJson(original.toJson());

    expect(restored.characterRig, isNotNull);
    expect(restored.characterRig!.id, 'john-d-rig');
    expect(restored.rigPoses, hasLength(1));
    expect(restored.rigPoses.first.name, 'Crouch');
    expect(restored.rigPoses.first.controls.first.targetId, 'front-left-leg');
    expect(restored.rigPoses.first.controls.first.y, 45);
  });

  test('legacy Bag items remain compatible', () {
    final original = makeItem();
    final json = original.toJson();

    expect(json.containsKey('characterRig'), isFalse);
    expect(json.containsKey('rigPoses'), isFalse);

    final restored = BagItem.fromJson(json);

    expect(restored.characterRig, isNull);
    expect(restored.rigPoses, isEmpty);
  });
}
