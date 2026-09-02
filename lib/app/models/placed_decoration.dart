class PlacedDecoration {
  const PlacedDecoration({
    required this.id,
    required this.bagItemId,
    required this.name,
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
    this.mirrored = false,
  });

  final String id;
  final String bagItemId;
  final String name;

  /// Normalised room coordinates, 0..1.
  final double x;
  final double y;

  final double scale;
  final double rotation;
  final bool mirrored;

  PlacedDecoration copyWith({
    String? id,
    String? bagItemId,
    String? name,
    double? x,
    double? y,
    double? scale,
    double? rotation,
    bool? mirrored,
  }) {
    return PlacedDecoration(
      id: id ?? this.id,
      bagItemId: bagItemId ?? this.bagItemId,
      name: name ?? this.name,
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      mirrored: mirrored ?? this.mirrored,
    );
  }

  factory PlacedDecoration.fromJson(Map<String, dynamic> json) {
    return PlacedDecoration(
      id: json['id']?.toString() ?? '',
      bagItemId: json['bagItemId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Decoration',
      x: (json['x'] as num?)?.toDouble() ?? 0.5,
      y: (json['y'] as num?)?.toDouble() ?? 0.5,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      mirrored: json['mirrored'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'bagItemId': bagItemId,
      'name': name,
      'x': x,
      'y': y,
      'scale': scale,
      'rotation': rotation,
      'mirrored': mirrored,
    };
  }
}
