class LayerGroup {
  LayerGroup({
    required this.id,
    required this.name,
    required this.childLayerIds,
    this.visible = true,
    this.expanded = true,
  });

  factory LayerGroup.fromJson(Map<String, dynamic> json) {
    return LayerGroup(
      id: json['id'] as String? ?? 'group',
      name: json['name'] as String? ?? 'Group',
      visible: json['visible'] as bool? ?? true,
      expanded: json['expanded'] as bool? ?? true,
      childLayerIds: (json['childLayerIds'] as List? ?? const [])
          .map((id) => id.toString())
          .toList(),
    );
  }

  final String id;
  final String name;
  final bool visible;
  final bool expanded;
  final List<String> childLayerIds;

  LayerGroup copyWith({
    String? id,
    String? name,
    bool? visible,
    bool? expanded,
    List<String>? childLayerIds,
  }) {
    return LayerGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      expanded: expanded ?? this.expanded,
      childLayerIds: childLayerIds ?? this.childLayerIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'visible': visible,
      'expanded': expanded,
      'childLayerIds': childLayerIds,
    };
  }
}
