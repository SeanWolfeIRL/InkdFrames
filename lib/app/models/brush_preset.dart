import 'vector_stroke.dart';

class BrushPreset {
  BrushPreset({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.brushType,
    required this.brushSize,
    required this.brushOpacity,
    required this.stabilizerStrength,
    required this.stabilizerPullDistance,
    required this.brushColor,
    required this.textureEnabled,
    required this.texturePattern,
    required this.textureScale,
    required this.textureDensity,
    required this.textureScatter,
  });

  factory BrushPreset.fromJson(Map<String, dynamic> json) {
    final brushTypeName = json['brushType'] as String?;

    final brushType = StrokeBrushType.values.firstWhere(
      (type) => type.name == brushTypeName,
      orElse: () => StrokeBrushType.solid,
    );

    return BrushPreset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Brush Preset',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      brushType: brushType,
      brushSize: (json['brushSize'] as num?)?.toDouble() ?? 4.0,
      brushOpacity: (json['brushOpacity'] as num?)?.toDouble() ?? 1.0,
      stabilizerStrength:
          (json['stabilizerStrength'] as num?)?.toDouble() ?? 0.55,
      stabilizerPullDistance:
          (json['stabilizerPullDistance'] as num?)?.toDouble() ?? 14.0,
      brushColor: (json['brushColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
      textureEnabled: json['textureEnabled'] as bool? ?? false,
      texturePattern: json['texturePattern'] as String? ?? 'stipple',
      textureScale: (json['textureScale'] as num?)?.toDouble() ?? 8.0,
      textureDensity: (json['textureDensity'] as num?)?.toDouble() ?? 0.5,
      textureScatter: (json['textureScatter'] as num?)?.toDouble() ?? 18.0,
    );
  }

  final String id;
  final String name;
  final DateTime createdAt;

  final StrokeBrushType brushType;
  final double brushSize;
  final double brushOpacity;
  final double stabilizerStrength;
  final double stabilizerPullDistance;
  final int brushColor;

  final bool textureEnabled;
  final String texturePattern;
  final double textureScale;
  final double textureDensity;
  final double textureScatter;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'brushType': brushType.name,
      'brushSize': brushSize,
      'brushOpacity': brushOpacity,
      'stabilizerStrength': stabilizerStrength,
      'stabilizerPullDistance': stabilizerPullDistance,
      'brushColor': brushColor,
      'textureEnabled': textureEnabled,
      'texturePattern': texturePattern,
      'textureScale': textureScale,
      'textureDensity': textureDensity,
      'textureScatter': textureScatter,
    };
  }
}
