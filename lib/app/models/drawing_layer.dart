import 'vector_stroke.dart';

class DrawingLayer {
  DrawingLayer({
    required this.id,
    required this.name,
    required this.frames,
    this.visible = true,
    this.opacity = 1.0,
    this.alphaLocked = false,
  });

  factory DrawingLayer.fromJson(Map<String, dynamic> json) {
    final rawFrames = json['frames'] as List? ?? const [];

    return DrawingLayer(
      id: json['id'] as String? ?? 'layer',
      name: json['name'] as String? ?? 'Layer',
      visible: json['visible'] as bool? ?? true,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      alphaLocked: json['alphaLocked'] as bool? ?? false,
      frames: rawFrames
          .map(
            (frame) => (frame as List)
                .map(
                  (stroke) => VectorStroke.fromJson(
                    Map<String, dynamic>.from(stroke as Map),
                  ),
                )
                .toList(),
          )
          .toList(),
    );
  }

  final String id;
  final String name;
  final bool visible;
  final double opacity;

  /// When enabled, new painting is restricted to the existing painted
  /// footprint of this layer on the current animation frame.
  final bool alphaLocked;

  /// One stroke list for every animation frame.
  final List<List<VectorStroke>> frames;

  DrawingLayer copyWith({
    String? id,
    String? name,
    bool? visible,
    double? opacity,
    bool? alphaLocked,
    List<List<VectorStroke>>? frames,
  }) {
    return DrawingLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      alphaLocked: alphaLocked ?? this.alphaLocked,
      frames: frames ?? this.frames,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'visible': visible,
      'opacity': opacity,
      'alphaLocked': alphaLocked,
      'frames': frames
          .map((frame) => frame.map((stroke) => stroke.toJson()).toList())
          .toList(),
    };
  }
}
