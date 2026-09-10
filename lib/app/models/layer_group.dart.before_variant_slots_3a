class LayerGroup {
  LayerGroup({
    required this.id,
    required this.name,
    required List<String> childLayerIds,
    List<String> childGroupIds = const <String>[],
    List<String>? childOrder,
    this.visible = true,
    this.expanded = true,
  }) : childLayerIds = childLayerIds,
       childGroupIds = childGroupIds,
       childOrder =
           childOrder ??
           <String>[
             ...childGroupIds.map((id) => 'group:$id'),
             ...childLayerIds.map((id) => 'layer:$id'),
           ];

  factory LayerGroup.fromJson(Map<String, dynamic> json) {
    return LayerGroup(
      id: json['id'] as String? ?? 'group',
      name: json['name'] as String? ?? 'Group',
      visible: json['visible'] as bool? ?? true,
      expanded: json['expanded'] as bool? ?? true,
      childLayerIds: (json['childLayerIds'] as List? ?? const [])
          .map((id) => id.toString())
          .toList(),
      childGroupIds: (json['childGroupIds'] as List? ?? const [])
          .map((id) => id.toString())
          .toList(),
      childOrder: json['childOrder'] is List
          ? (json['childOrder'] as List)
                .map((entry) => entry.toString())
                .toList()
          : null,
    );
  }

  final String id;
  final String name;
  final bool visible;
  final bool expanded;

  /// Drawing layers directly owned by this group.
  final List<String> childLayerIds;

  /// Nested groups directly owned by this group.
  ///
  /// Older projects do not contain this field, so fromJson deliberately
  /// defaults to an empty list for backwards compatibility.
  final List<String> childGroupIds;

  /// Authoritative ordered contents of this group.
  ///
  /// Entries use:
  ///   `group:<id>`
  ///   `layer:<id>`
  ///
  /// Older projects automatically derive this from childGroupIds and
  /// childLayerIds, preserving their previous visible ordering.
  final List<String> childOrder;

  LayerGroup copyWith({
    String? id,
    String? name,
    bool? visible,
    bool? expanded,
    List<String>? childLayerIds,
    List<String>? childGroupIds,
    List<String>? childOrder,
  }) {
    return LayerGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      expanded: expanded ?? this.expanded,
      childLayerIds: childLayerIds ?? this.childLayerIds,
      childGroupIds: childGroupIds ?? this.childGroupIds,
      childOrder: childOrder ?? this.childOrder,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'visible': visible,
      'expanded': expanded,
      'childLayerIds': childLayerIds,
      'childGroupIds': childGroupIds,
      'childOrder': childOrder,
    };
  }
}
