import 'character_rig.dart';
import 'rig_pose.dart';
import 'stroke_rig.dart';

List<RigControlPose>? captureRigPoseControls({
  required CharacterRig rig,
  required Map<String, StrokeRig> activeRigs,
  StrokeRig? singleStrokePreview,
}) {
  final result = <RigControlPose>[];

  for (final target in rig.targets) {
    if (target.type != RigTargetType.stroke) continue;

    final source = singleStrokePreview?.strokeId == target.targetId
        ? singleStrokePreview!
        : activeRigs[target.targetId] ?? target.rig;

    if (source.strokeId != target.targetId) return null;

    final registeredIds = target.rig.controls
        .map((control) => control.id)
        .toSet();
    final sourceIds = source.controls.map((control) => control.id).toSet();

    if (registeredIds.length != target.rig.controls.length ||
        sourceIds.length != source.controls.length ||
        registeredIds.length != sourceIds.length ||
        !registeredIds.containsAll(sourceIds)) {
      return null;
    }

    for (final control in source.controls) {
      result.add(
        RigControlPose(
          targetId: target.id,
          controlId: control.id,
          x: control.x,
          y: control.y,
        ),
      );
    }
  }

  return result.isEmpty ? null : result;
}
