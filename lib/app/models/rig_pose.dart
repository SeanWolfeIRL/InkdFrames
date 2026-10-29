class RigControlPose {
  const RigControlPose({
    required this.targetId,
    required this.controlId,
    required this.x,
    required this.y,
  });

  /// Identifies the CharacterRigTarget.
  final String targetId;
  final String controlId;
  final double x;
  final double y;

  factory RigControlPose.fromJson(Map<String, dynamic> json) {
    return RigControlPose(
      targetId: json['targetId']?.toString() ?? '',
      controlId: json['controlId']?.toString() ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'targetId': targetId,
    'controlId': controlId,
    'x': x,
    'y': y,
  };
}

class RigPose {
  const RigPose({
    required this.id,
    required this.name,
    required this.characterRigId,
    this.controls = const <RigControlPose>[],
  });

  final String id;
  final String name;
  final String characterRigId;
  final List<RigControlPose> controls;

  factory RigPose.fromJson(Map<String, dynamic> json) {
    return RigPose(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      characterRigId: json['characterRigId']?.toString() ?? '',
      controls: (json['controls'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => RigControlPose.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'characterRigId': characterRigId,
    'controls': controls.map((control) => control.toJson()).toList(),
  };
}
