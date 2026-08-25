import 'vector_stroke.dart';

class BagLayer {
  BagLayer({
    required this.name,
    required this.strokes,
    this.opacity = 1.0,
    this.visible = true,
  });

  factory BagLayer.fromJson(Map<String, dynamic> json) {
    final rawStrokes = json['strokes'] as List? ?? const [];

    return BagLayer(
      name: json['name'] as String? ?? 'Layer',
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      visible: json['visible'] as bool? ?? true,
      strokes: rawStrokes
          .map(
            (stroke) =>
                VectorStroke.fromJson(Map<String, dynamic>.from(stroke as Map)),
          )
          .toList(),
    );
  }

  final String name;
  final double opacity;
  final bool visible;
  final List<VectorStroke> strokes;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'opacity': opacity,
      'visible': visible,
      'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
    };
  }
}

class BagItem {
  BagItem({
    required this.id,
    required this.name,
    required this.sourceGroupName,
    required this.layers,
    required this.createdAt,
  });

  factory BagItem.fromJson(Map<String, dynamic> json) {
    final rawLayers = json['layers'] as List? ?? const [];

    return BagItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Bag Item',
      sourceGroupName: json['sourceGroupName'] as String? ?? 'Group',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      layers: rawLayers
          .map(
            (layer) =>
                BagLayer.fromJson(Map<String, dynamic>.from(layer as Map)),
          )
          .toList(),
    );
  }

  final String id;
  final String name;
  final String sourceGroupName;
  final List<BagLayer> layers;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'sourceGroupName': sourceGroupName,
      'createdAt': createdAt.toIso8601String(),
      'layers': layers.map((layer) => layer.toJson()).toList(),
    };
  }
}
