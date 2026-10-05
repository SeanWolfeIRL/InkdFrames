class GroupAnimationClip {
  const GroupAnimationClip({required this.sourceFrameId, this.duration = 1});

  final String sourceFrameId;
  final int duration;

  Map<String, dynamic> toJson() {
    return {'sourceFrameId': sourceFrameId, 'duration': duration};
  }

  factory GroupAnimationClip.fromJson(Map<String, dynamic> json) {
    return GroupAnimationClip(
      sourceFrameId: json['sourceFrameId']?.toString() ?? '',
      duration: ((json['duration'] as num?)?.toInt() ?? 1).clamp(1, 1000000),
    );
  }

  GroupAnimationClip copyWith({String? sourceFrameId, int? duration}) {
    return GroupAnimationClip(
      sourceFrameId: sourceFrameId ?? this.sourceFrameId,
      duration: duration ?? this.duration,
    );
  }
}

class GroupAnimationTrack {
  const GroupAnimationTrack({
    required this.targetGroupId,
    this.enabled = true,
    this.loop = true,
    this.clips = const <GroupAnimationClip>[],
  });

  final String targetGroupId;
  final bool enabled;
  final bool loop;
  final List<GroupAnimationClip> clips;

  Map<String, dynamic> toJson() {
    return {
      'targetGroupId': targetGroupId,
      'enabled': enabled,
      'loop': loop,
      'clips': clips.map((clip) => clip.toJson()).toList(),
    };
  }

  factory GroupAnimationTrack.fromJson(Map<String, dynamic> json) {
    final rawClips = json['clips'];

    return GroupAnimationTrack(
      targetGroupId: json['targetGroupId']?.toString() ?? '',
      enabled: json['enabled'] as bool? ?? true,
      loop: json['loop'] as bool? ?? true,
      clips: rawClips is List
          ? rawClips
                .whereType<Map>()
                .map(
                  (clip) => GroupAnimationClip.fromJson(
                    Map<String, dynamic>.from(clip),
                  ),
                )
                .where((clip) => clip.sourceFrameId.isNotEmpty)
                .toList()
          : <GroupAnimationClip>[],
    );
  }

  GroupAnimationTrack copyWith({
    String? targetGroupId,
    bool? enabled,
    bool? loop,
    List<GroupAnimationClip>? clips,
  }) {
    return GroupAnimationTrack(
      targetGroupId: targetGroupId ?? this.targetGroupId,
      enabled: enabled ?? this.enabled,
      loop: loop ?? this.loop,
      clips: clips ?? this.clips,
    );
  }
}
