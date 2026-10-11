import 'bag_motion_asset.dart';

/// An independently animated composite asset placed inside a scene.
///
/// The rootGroupId refers to the destination Workspace hierarchy.
/// Motion group IDs must be remapped to destination IDs on insertion.
class SceneMotionInstance {
  const SceneMotionInstance({
    required this.id,
    required this.rootGroupId,
    required this.bagItemId,
    required this.motion,
    this.clipName = 'idle',
    this.enabled = true,
    this.loop = true,
    this.placementX = 0,
    this.placementY = 0,
    this.placementScaleX = 1,
    this.placementScaleY = 1,
    this.placementRotation = 0,
    this.placementPivotX = 0,
    this.placementPivotY = 0,
  });

  final String id;
  final String rootGroupId;
  final String bagItemId;
  final BagMotionAsset motion;
  final String clipName;
  final bool enabled;
  final bool loop;

  /// Outer scene placement, independent of authored animation poses.
  final double placementX;
  final double placementY;
  final double placementScaleX;
  final double placementScaleY;
  final double placementRotation;
  final double placementPivotX;
  final double placementPivotY;

  SceneMotionInstance copyWith({
    double? placementX,
    double? placementY,
    double? placementScaleX,
    double? placementScaleY,
    double? placementRotation,
    double? placementPivotX,
    double? placementPivotY,
  }) {
    return SceneMotionInstance(
      id: id,
      rootGroupId: rootGroupId,
      bagItemId: bagItemId,
      motion: motion,
      clipName: clipName,
      enabled: enabled,
      loop: loop,
      placementX: placementX ?? this.placementX,
      placementY: placementY ?? this.placementY,
      placementScaleX: placementScaleX ?? this.placementScaleX,
      placementScaleY: placementScaleY ?? this.placementScaleY,
      placementRotation: placementRotation ?? this.placementRotation,
      placementPivotX: placementPivotX ?? this.placementPivotX,
      placementPivotY: placementPivotY ?? this.placementPivotY,
    );
  }

  factory SceneMotionInstance.fromJson(Map<String, dynamic> json) {
    return SceneMotionInstance(
      id: json['id']?.toString() ?? '',
      rootGroupId: json['rootGroupId']?.toString() ?? '',
      bagItemId: json['bagItemId']?.toString() ?? '',
      clipName: json['clipName']?.toString() ?? 'idle',
      enabled: json['enabled'] != false,
      loop: json['loop'] != false,
      placementX: (json['placementX'] as num?)?.toDouble() ?? 0,
      placementY: (json['placementY'] as num?)?.toDouble() ?? 0,
      placementScaleX: (json['placementScaleX'] as num?)?.toDouble() ?? 1,
      placementScaleY: (json['placementScaleY'] as num?)?.toDouble() ?? 1,
      placementRotation: (json['placementRotation'] as num?)?.toDouble() ?? 0,
      placementPivotX: (json['placementPivotX'] as num?)?.toDouble() ?? 0,
      placementPivotY: (json['placementPivotY'] as num?)?.toDouble() ?? 0,
      motion: BagMotionAsset.fromJson(
        Map<String, dynamic>.from(json['motion'] as Map? ?? const {}),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'rootGroupId': rootGroupId,
    'bagItemId': bagItemId,
    'clipName': clipName,
    'enabled': enabled,
    'loop': loop,
    'placementX': placementX,
    'placementY': placementY,
    'placementScaleX': placementScaleX,
    'placementScaleY': placementScaleY,
    'placementRotation': placementRotation,
    'placementPivotX': placementPivotX,
    'placementPivotY': placementPivotY,
    'motion': motion.toJson(),
  };
}
