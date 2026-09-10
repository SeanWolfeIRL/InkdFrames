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
    this.roomNodeOverrides = const <String, Map<String, dynamic>>{},
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

  /// Instance-local overrides for authored Composite nodes.
  ///
  /// Keyed by Composite node ID. The reusable Bag source remains immutable.
  final Map<String, Map<String, dynamic>> roomNodeOverrides;

  PlacedDecoration copyWith({
    String? id,
    String? bagItemId,
    String? name,
    double? x,
    double? y,
    double? scale,
    double? rotation,
    bool? mirrored,
    Map<String, Map<String, dynamic>>? roomNodeOverrides,
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
      roomNodeOverrides: roomNodeOverrides ?? this.roomNodeOverrides,
    );
  }

  factory PlacedDecoration.fromJson(Map<String, dynamic> json) {
    final roomNodeOverrides = <String, Map<String, dynamic>>{};

    final rawOverrides = json['roomNodeOverrides'];

    if (rawOverrides is Map) {
      for (final entry in rawOverrides.entries) {
        final rawNode = entry.value;

        if (rawNode is Map) {
          roomNodeOverrides[entry.key.toString()] = rawNode
              .map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              );
        }
      }
    }

    return PlacedDecoration(
      id: json['id']?.toString() ?? '',
      bagItemId: json['bagItemId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Decoration',
      x: (json['x'] as num?)?.toDouble() ?? 0.5,
      y: (json['y'] as num?)?.toDouble() ?? 0.5,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      mirrored: json['mirrored'] == true,
      roomNodeOverrides: roomNodeOverrides,
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
      'roomNodeOverrides': roomNodeOverrides,
    };
  }
}
