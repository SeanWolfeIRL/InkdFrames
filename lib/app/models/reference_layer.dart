class ReferenceLayer {
  ReferenceLayer({
    required this.id,
    required this.name,
    required this.mediaPath,
    required this.mediaType,
    this.visible = true,
    this.opacity = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.rotation = 0.0,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.pivotX,
    this.pivotY,
    List<int>? frameTimesMs,
  }) : frameTimesMs = frameTimesMs ?? <int>[];

  factory ReferenceLayer.fromJson(Map<String, dynamic> json) {
    return ReferenceLayer(
      id: json['id'] as String? ?? 'reference',
      name: json['name'] as String? ?? 'Reference',
      mediaPath: json['mediaPath'] as String? ?? '',
      mediaType: json['mediaType'] as String? ?? 'image',
      visible: json['visible'] as bool? ?? true,
      opacity: (json['opacity'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 1.0,
      offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0.0,
      offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      scaleX: (json['scaleX'] as num?)?.toDouble() ?? 1.0,
      scaleY: (json['scaleY'] as num?)?.toDouble() ?? 1.0,
      pivotX: (json['pivotX'] as num?)?.toDouble(),
      pivotY: (json['pivotY'] as num?)?.toDouble(),
      frameTimesMs: json['frameTimesMs'] is List
          ? (json['frameTimesMs'] as List)
                .map((time) => (time as num).toInt())
                .toList()
          : <int>[],
    );
  }

  final String id;
  final String name;
  final String mediaPath;
  final String mediaType;

  final bool visible;
  final double opacity;

  /// Non-destructive transform state.
  final double offsetX;
  final double offsetY;
  final double rotation;
  final double scaleX;
  final double scaleY;

  /// Optional transform pivot in canvas coordinates.
  final double? pivotX;
  final double? pivotY;

  /// Animation-frame → source-video timestamp mapping.
  ///
  /// Normally empty for image references.
  final List<int> frameTimesMs;

  ReferenceLayer copyWith({
    String? id,
    String? name,
    String? mediaPath,
    String? mediaType,
    bool? visible,
    double? opacity,
    double? offsetX,
    double? offsetY,
    double? rotation,
    double? scaleX,
    double? scaleY,
    double? pivotX,
    double? pivotY,
    bool clearPivot = false,
    List<int>? frameTimesMs,
  }) {
    return ReferenceLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      mediaPath: mediaPath ?? this.mediaPath,
      mediaType: mediaType ?? this.mediaType,
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      rotation: rotation ?? this.rotation,
      scaleX: scaleX ?? this.scaleX,
      scaleY: scaleY ?? this.scaleY,
      pivotX: clearPivot ? null : pivotX ?? this.pivotX,
      pivotY: clearPivot ? null : pivotY ?? this.pivotY,
      frameTimesMs: frameTimesMs ?? this.frameTimesMs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'mediaPath': mediaPath,
      'mediaType': mediaType,
      'visible': visible,
      'opacity': opacity,
      'offsetX': offsetX,
      'offsetY': offsetY,
      'rotation': rotation,
      'scaleX': scaleX,
      'scaleY': scaleY,
      'pivotX': pivotX,
      'pivotY': pivotY,
      'frameTimesMs': frameTimesMs,
    };
  }
}
