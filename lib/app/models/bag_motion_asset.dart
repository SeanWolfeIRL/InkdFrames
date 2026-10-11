import 'group_animation_track.dart';
import 'transform_keyframe.dart';

/// One named animation sharing its parent CompositeAsset artwork.
class BagMotionClip {
  const BagMotionClip({
    required this.name,
    required this.fps,
    required this.frameIds,
    required this.frameDurations,
    this.transformKeyframes = const <TransformKeyframe>[],
    this.groupAnimationTracks = const <GroupAnimationTrack>[],
  });

  final String name;
  final double fps;
  final List<String> frameIds;
  final List<int> frameDurations;
  final List<TransformKeyframe> transformKeyframes;
  final List<GroupAnimationTrack> groupAnimationTracks;

  factory BagMotionClip.fromJson(Map<String, dynamic> json) {
    final rawIds = json['frameIds'];
    final rawDurations = json['frameDurations'];
    final rawKeys = json['transformKeyframes'];
    final rawTracks = json['groupAnimationTracks'];

    return BagMotionClip(
      name: json['name']?.toString() ?? 'idle',
      fps: (json['fps'] as num?)?.toDouble() ?? 12.0,
      frameIds: rawIds is List
          ? rawIds.map((value) => value.toString()).toList()
          : <String>[],
      frameDurations: rawDurations is List
          ? rawDurations
                .map(
                  (value) => ((value as num?)?.toInt() ?? 1).clamp(1, 1000000),
                )
                .toList()
          : <int>[],
      transformKeyframes: rawKeys is List
          ? rawKeys
                .whereType<Map>()
                .map(
                  (value) => TransformKeyframe.fromJson(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList()
          : <TransformKeyframe>[],
      groupAnimationTracks: rawTracks is List
          ? rawTracks
                .whereType<Map>()
                .map(
                  (value) => GroupAnimationTrack.fromJson(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList()
          : <GroupAnimationTrack>[],
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'fps': fps,
    'frameIds': frameIds,
    'frameDurations': frameDurations,
    'transformKeyframes': transformKeyframes
        .map((keyframe) => keyframe.toJson())
        .toList(),
    'groupAnimationTracks': groupAnimationTracks
        .map((track) => track.toJson())
        .toList(),
  };
}

/// Portable animation authored for a CompositeAsset hierarchy.
///
/// Artwork remains in the CompositeAsset. This model preserves the
/// frame catalogue and animation relationships required to replay it.
///
/// Group IDs refer to authored CompositeNode IDs, not destination
/// Workspace IDs. Importers must remap them when instantiating an asset.
class BagMotionAsset {
  const BagMotionAsset({
    required this.frameIds,
    required this.frameDurations,
    required this.fps,
    this.version = 2,
    this.clips = const <BagMotionClip>[],
    this.transformKeyframes = const <TransformKeyframe>[],
    this.groupAnimationTracks = const <GroupAnimationTrack>[],
  });

  final int version;

  /// Additional authored clips. The original fields remain the default
  /// animation for older Workspace code.
  final List<BagMotionClip> clips;

  /// Named clips, including an implicit idle clip for legacy assets.
  List<BagMotionClip> get availableClips {
    if (clips.isNotEmpty) return clips;
    return <BagMotionClip>[
      BagMotionClip(
        name: 'idle',
        fps: fps,
        frameIds: frameIds,
        frameDurations: frameDurations,
        transformKeyframes: transformKeyframes,
        groupAnimationTracks: groupAnimationTracks,
      ),
    ];
  }

  final double fps;
  final List<String> frameIds;
  final List<int> frameDurations;
  final List<TransformKeyframe> transformKeyframes;
  final List<GroupAnimationTrack> groupAnimationTracks;

  factory BagMotionAsset.fromJson(Map<String, dynamic> json) {
    final rawFrameIds = json['frameIds'];
    final rawDurations = json['frameDurations'];
    final rawKeyframes = json['transformKeyframes'];
    final rawTracks = json['groupAnimationTracks'];

    return BagMotionAsset(
      version: (json['version'] as num?)?.toInt() ?? 1,
      clips: json['clips'] is List
          ? (json['clips'] as List)
                .whereType<Map>()
                .map(
                  (value) =>
                      BagMotionClip.fromJson(Map<String, dynamic>.from(value)),
                )
                .toList()
          : const <BagMotionClip>[],
      fps: (json['fps'] as num?)?.toDouble() ?? 12.0,
      frameIds: rawFrameIds is List
          ? rawFrameIds.map((value) => value.toString()).toList()
          : <String>[],
      frameDurations: rawDurations is List
          ? rawDurations
                .map(
                  (value) => ((value as num?)?.toInt() ?? 1).clamp(1, 1000000),
                )
                .toList()
          : <int>[],
      transformKeyframes: rawKeyframes is List
          ? rawKeyframes
                .whereType<Map>()
                .map(
                  (value) => TransformKeyframe.fromJson(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList()
          : <TransformKeyframe>[],
      groupAnimationTracks: rawTracks is List
          ? rawTracks
                .whereType<Map>()
                .map(
                  (value) => GroupAnimationTrack.fromJson(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList()
          : <GroupAnimationTrack>[],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      if (clips.isNotEmpty)
        'clips': clips.map((clip) => clip.toJson()).toList(),
      'fps': fps,
      'frameIds': frameIds,
      'frameDurations': frameDurations,
      'transformKeyframes': transformKeyframes
          .map((keyframe) => keyframe.toJson())
          .toList(),
      'groupAnimationTracks': groupAnimationTracks
          .map((track) => track.toJson())
          .toList(),
    };
  }
}
