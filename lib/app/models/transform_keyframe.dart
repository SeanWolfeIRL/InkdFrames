class TransformKeyframe {
  const TransformKeyframe({
    required this.id,
    required this.frameId,
    required this.targetGroupId,
    this.translateX = 0.0,
    this.translateY = 0.0,
    this.rotation = 0.0,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.pivotX,
    this.pivotY,
    this.enabled = true,
  });

  factory TransformKeyframe.fromJson(Map<String, dynamic> json) {
    return TransformKeyframe(
      id: json['id'] as String? ?? 'keyframe',
      frameId: json['frameId'] as String? ?? '',
      targetGroupId: json['targetGroupId'] as String? ?? '',
      translateX: (json['translateX'] as num?)?.toDouble() ?? 0.0,
      translateY: (json['translateY'] as num?)?.toDouble() ?? 0.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      scaleX: (json['scaleX'] as num?)?.toDouble() ?? 1.0,
      scaleY: (json['scaleY'] as num?)?.toDouble() ?? 1.0,
      pivotX: (json['pivotX'] as num?)?.toDouble(),
      pivotY: (json['pivotY'] as num?)?.toDouble(),
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  final String id;

  /// Stable animation-frame identity rather than positional frame index.
  final String frameId;

  /// Stable LayerGroup identity targeted by this pose.
  final String targetGroupId;

  /// Pose transform relative to the authored/base artwork.
  final double translateX;
  final double translateY;
  final double rotation;
  final double scaleX;
  final double scaleY;
  final double? pivotX;
  final double? pivotY;

  final bool enabled;

  TransformKeyframe copyWith({
    String? id,
    String? frameId,
    String? targetGroupId,
    double? translateX,
    double? translateY,
    double? rotation,
    double? scaleX,
    double? scaleY,
    double? pivotX,
    double? pivotY,
    bool clearPivot = false,
    bool? enabled,
  }) {
    return TransformKeyframe(
      id: id ?? this.id,
      frameId: frameId ?? this.frameId,
      targetGroupId: targetGroupId ?? this.targetGroupId,
      translateX: translateX ?? this.translateX,
      translateY: translateY ?? this.translateY,
      rotation: rotation ?? this.rotation,
      scaleX: scaleX ?? this.scaleX,
      scaleY: scaleY ?? this.scaleY,
      pivotX: clearPivot ? null : pivotX ?? this.pivotX,
      pivotY: clearPivot ? null : pivotY ?? this.pivotY,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'frameId': frameId,
      'targetGroupId': targetGroupId,
      'translateX': translateX,
      'translateY': translateY,
      'rotation': rotation,
      'scaleX': scaleX,
      'scaleY': scaleY,
      'pivotX': pivotX,
      'pivotY': pivotY,
      'enabled': enabled,
    };
  }
}
