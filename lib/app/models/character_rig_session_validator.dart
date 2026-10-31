import 'character_rig.dart';
import 'character_rig_editing_session.dart';
import 'drawing_layer.dart';
import 'stroke_rig.dart';

/// Validates a temporary deformation against registered controls
/// and the artwork available on its editing frame.
Map<String, StrokeRig>? validateCharacterRigSession(
  CharacterRigEditingSession? session,
  CharacterRig? character,
  List<String> frameIds,
  List<DrawingLayer> layers,
) {
  if (session == null ||
      character == null ||
      session.characterRigId != character.id ||
      !frameIds.contains(session.frameId) ||
      session.strokeRigs.isEmpty) {
    return null;
  }

  final frameIndex = frameIds.indexOf(session.frameId);

  if (frameIds.indexOf(session.frameId) !=
      frameIds.lastIndexOf(session.frameId)) {
    return null;
  }

  final registered = <String, StrokeRig>{};

  for (final target in character.targets) {
    if (target.type != RigTargetType.stroke) {
      continue;
    }
    if (target.targetId.isEmpty ||
        target.rig.strokeId != target.targetId ||
        registered.containsKey(target.targetId)) {
      return null;
    }
    registered[target.targetId] = target.rig;
  }

  final restored = <String, StrokeRig>{};

  for (final saved in session.strokeRigs) {
    final original = registered[saved.strokeId];

    if (original == null ||
        restored.containsKey(saved.strokeId) ||
        saved.id != original.id ||
        saved.controls.length != original.controls.length) {
      return null;
    }

    final strokeExists = layers.any((layer) {
      if (!layer.visible ||
          frameIndex < 0 ||
          frameIndex >= layer.frames.length) {
        return false;
      }

      return layer.frames[frameIndex].any(
        (stroke) =>
            stroke.id == saved.strokeId &&
            !stroke.filled &&
            !stroke.alphaLocked,
      );
    });

    if (!strokeExists) {
      return null;
    }

    for (var i = 0; i < original.controls.length; i++) {
      final expected = original.controls[i];
      final actual = saved.controls[i];

      if (actual.id != expected.id ||
          actual.restX != expected.restX ||
          actual.restY != expected.restY ||
          actual.radius != expected.radius ||
          actual.locked != expected.locked ||
          !actual.x.isFinite ||
          !actual.y.isFinite) {
        return null;
      }
    }

    restored[saved.strokeId] = StrokeRig.fromJson(saved.toJson());
  }

  return restored.isEmpty ? null : restored;
}
