import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/rig_pose.dart';

void main() {
  test('pose preserves controls from separate rig targets', () {
    const pose = RigPose(
      id: 'pose-crouch',
      name: 'Crouch',
      characterRigId: 'john-d-rig',
      controls: [
        RigControlPose(targetId: 'left-leg', controlId: 'flex', x: 20, y: 40),
        RigControlPose(targetId: 'right-leg', controlId: 'flex', x: 80, y: 40),
      ],
    );

    final restored = RigPose.fromJson(pose.toJson());

    expect(restored.id, 'pose-crouch');
    expect(restored.name, 'Crouch');
    expect(restored.characterRigId, 'john-d-rig');
    expect(restored.controls.length, 2);
    expect(restored.controls[0].targetId, 'left-leg');
    expect(restored.controls[1].targetId, 'right-leg');
    expect(restored.controls[0].controlId, 'flex');
    expect(restored.controls[1].controlId, 'flex');
    expect(restored.controls[0].x, 20);
    expect(restored.controls[1].x, 80);
  });
}
