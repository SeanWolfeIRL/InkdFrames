import 'stroke_rig.dart';

enum RigTargetType { stroke, group }

class CharacterRigTarget {
  const CharacterRigTarget({
    required this.id,
    required this.type,
    required this.targetId,
    required this.rig,
  });

  final String id;
  final RigTargetType type;
  final String targetId;
  final StrokeRig rig;

  factory CharacterRigTarget.fromJson(Map<String, dynamic> json) {
    return CharacterRigTarget(
      id: json['id']?.toString() ?? '',
      type: json['type'] == 'group'
          ? RigTargetType.group
          : RigTargetType.stroke,
      targetId: json['targetId']?.toString() ?? '',
      rig: StrokeRig.fromJson(Map<String, dynamic>.from(json['rig'] as Map)),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'targetId': targetId,
    'rig': rig.toJson(),
  };
}

class CharacterRig {
  const CharacterRig({
    required this.id,
    this.targets = const <CharacterRigTarget>[],
  });

  final String id;
  final List<CharacterRigTarget> targets;

  factory CharacterRig.fromJson(Map<String, dynamic> json) {
    return CharacterRig(
      id: json['id']?.toString() ?? '',
      targets: (json['targets'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                CharacterRigTarget.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'targets': targets.map((target) => target.toJson()).toList(),
  };
}
