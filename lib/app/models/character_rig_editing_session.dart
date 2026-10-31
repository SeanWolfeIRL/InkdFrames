import 'stroke_rig.dart';

/// Temporary, non-destructive character deformation for one editing frame.
///
/// This is not an animation keyframe or a named pose.
class CharacterRigEditingSession {
  const CharacterRigEditingSession({
    required this.characterRigId,
    required this.frameId,
    required this.strokeRigs,
  });

  final String characterRigId;
  final String frameId;
  final List<StrokeRig> strokeRigs;

  Map<String, dynamic> toJson() => {
    'characterRigId': characterRigId,
    'frameId': frameId,
    'strokeRigs': strokeRigs.map((rig) => rig.toJson()).toList(),
  };

  factory CharacterRigEditingSession.fromJson(Map<String, dynamic> json) {
    return CharacterRigEditingSession(
      characterRigId: json['characterRigId'] as String,
      frameId: json['frameId'] as String,
      strokeRigs: (json['strokeRigs'] as List)
          .map(
            (entry) =>
                StrokeRig.fromJson(Map<String, dynamic>.from(entry as Map)),
          )
          .toList(),
    );
  }
}
