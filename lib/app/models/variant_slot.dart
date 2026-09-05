class VariantSlot {
  VariantSlot({
    required this.id,
    required this.name,
    List<String>? childOrder,
    this.activeIndex = 0,
    this.expanded = true,
  }) : childOrder = childOrder ?? <String>[];

  factory VariantSlot.fromJson(Map<String, dynamic> json) {
    final childOrder = json['childOrder'] is List
        ? (json['childOrder'] as List).map((entry) => entry.toString()).toList()
        : <String>[];

    final rawActiveIndex = (json['activeIndex'] as num?)?.toInt() ?? 0;

    final safeActiveIndex = childOrder.isEmpty
        ? 0
        : rawActiveIndex.clamp(0, childOrder.length - 1);

    return VariantSlot(
      id: json['id'] as String? ?? 'variant',
      name: json['name'] as String? ?? 'Variant Slot',
      childOrder: childOrder,
      activeIndex: safeActiveIndex,
      expanded: json['expanded'] as bool? ?? true,
    );
  }

  final String id;
  final String name;

  /// Ordered selectable alternatives belonging to this slot.
  ///
  /// Entries use the normal hierarchy token language:
  ///   group:<id>
  ///   layer:<id>
  ///   reference:<id>
  ///
  /// Upgrade #3B will make only activeEntry render in the scene.
  final List<String> childOrder;

  final int activeIndex;
  final bool expanded;

  String? get activeEntry {
    if (childOrder.isEmpty) {
      return null;
    }

    final safeIndex = activeIndex.clamp(0, childOrder.length - 1);
    return childOrder[safeIndex];
  }

  VariantSlot copyWith({
    String? id,
    String? name,
    List<String>? childOrder,
    int? activeIndex,
    bool? expanded,
  }) {
    final nextOrder = childOrder ?? this.childOrder;
    final requestedIndex = activeIndex ?? this.activeIndex;

    final safeActiveIndex = nextOrder.isEmpty
        ? 0
        : requestedIndex.clamp(0, nextOrder.length - 1);

    return VariantSlot(
      id: id ?? this.id,
      name: name ?? this.name,
      childOrder: nextOrder,
      activeIndex: safeActiveIndex,
      expanded: expanded ?? this.expanded,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'childOrder': childOrder,
      'activeIndex': activeIndex,
      'expanded': expanded,
    };
  }
}
