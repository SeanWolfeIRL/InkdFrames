import 'character_rig.dart';
import 'composite_asset.dart';
import 'rig_pose.dart';

class RigExport {
  const RigExport({required this.rig, required this.poses});

  final CharacterRig? rig;
  final List<RigPose> poses;
}

RigExport captureRigExport(
  CompositeAsset composite,
  CharacterRig? workingRig,
  List<RigPose> workingPoses,
) {
  if (workingRig == null) {
    return const RigExport(rig: null, poses: []);
  }

  final strokeIds = <String>{};
  final groupIds = <String>{};

  void collect(CompositeNode node) {
    if (node.type == 'group') {
      groupIds.add(node.id);
    }

    if (node.type == 'layer') {
      final frames = node.payload['frames'];
      if (frames is List) {
        for (final frame in frames) {
          if (frame is! List) continue;
          for (final stroke in frame) {
            if (stroke is Map && stroke['id'] != null) {
              strokeIds.add(stroke['id'].toString());
            }
          }
        }
      }
    }

    for (final child in node.children) {
      collect(child);
    }
  }

  collect(composite.root);

  final targets = workingRig.targets.where((target) {
    return target.type == RigTargetType.stroke
        ? strokeIds.contains(target.targetId)
        : groupIds.contains(target.targetId);
  }).toList();

  if (targets.isEmpty) {
    return const RigExport(rig: null, poses: []);
  }

  final rig = CharacterRig(id: workingRig.id, targets: targets);

  final targetIds = targets.map((target) => target.id).toSet();

  final poses = workingPoses
      .where((pose) => pose.characterRigId == rig.id)
      .map(
        (pose) => RigPose(
          id: pose.id,
          name: pose.name,
          characterRigId: pose.characterRigId,
          controls: pose.controls
              .where((control) => targetIds.contains(control.targetId))
              .toList(),
        ),
      )
      .where((pose) => pose.controls.isNotEmpty)
      .toList();

  return RigExport(rig: rig, poses: poses);
}
