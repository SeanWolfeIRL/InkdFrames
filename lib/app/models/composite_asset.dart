/// A reusable structured InkdFrames scene asset.
///
/// Composite assets preserve hierarchy instead of flattening their contents.
/// They can contain drawing layers, raster/video references, nested groups,
/// Variant Slots, and future node types.
///
/// Child transforms remain authored relative to the composite scene.
/// A placed Composite later receives its own separate instance transform.
class CompositeAsset {
  const CompositeAsset({
    required this.version,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.root,
  });

  factory CompositeAsset.fromJson(Map<String, dynamic> json) {
    return CompositeAsset(
      version: (json['version'] as num?)?.toInt() ?? 1,
      canvasWidth: (json['canvasWidth'] as num?)?.toDouble() ?? 1920.0,
      canvasHeight: (json['canvasHeight'] as num?)?.toDouble() ?? 1080.0,
      root: CompositeNode.fromJson(
        Map<String, dynamic>.from(
          json['root'] as Map? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  final int version;
  final double canvasWidth;
  final double canvasHeight;
  final CompositeNode root;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'canvasWidth': canvasWidth,
      'canvasHeight': canvasHeight,
      'root': root.toJson(),
    };
  }
}

/// One node in a CompositeAsset hierarchy.
///
/// Known V1 node types:
///   group
///   layer
///   reference
///   variant
///
/// `payload` deliberately stores node-specific authored data. This keeps the
/// Composite format extensible without forcing unrelated node types into one
/// giant model.
///
/// Examples:
///   layer     -> opacity + stroke data
///   reference -> media type/path + authored transform + frame times
///   variant   -> active index
class CompositeNode {
  const CompositeNode({
    required this.type,
    required this.id,
    required this.name,
    this.visible = true,
    this.children = const <CompositeNode>[],
    this.payload = const <String, dynamic>{},
  });

  factory CompositeNode.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'] as List? ?? const [];

    return CompositeNode(
      type: json['type'] as String? ?? 'group',
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Composite Node',
      visible: json['visible'] as bool? ?? true,
      children: rawChildren
          .map(
            (child) =>
                CompositeNode.fromJson(Map<String, dynamic>.from(child as Map)),
          )
          .toList(),
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const <String, dynamic>{},
    );
  }

  final String type;
  final String id;
  final String name;
  final bool visible;

  /// Ordered front-to-back hierarchy contents.
  ///
  /// This uses the same conceptual ordering as Workspace childOrder.
  final List<CompositeNode> children;

  /// Node-specific authored data.
  ///
  /// This is serialized recursively and must contain JSON-safe values only.
  final Map<String, dynamic> payload;

  int? get activeVariantIndex {
    if (type != 'variant') {
      return null;
    }

    return (payload['activeIndex'] as num?)?.toInt();
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'id': id,
      'name': name,
      'visible': visible,
      'children': children.map((child) => child.toJson()).toList(),
      'payload': payload,
    };
  }
}
