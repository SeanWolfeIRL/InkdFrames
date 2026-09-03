import 'drawing_layer.dart';
import 'layer_group.dart';
import 'reference_layer.dart';
import 'vector_stroke.dart';

class InkdFramesProject {
  InkdFramesProject({
    required this.id,
    required this.name,
    required this.fps,
    required this.frames,
    required this.frameDurations,
    this.canvasWidth = 1920,
    this.canvasHeight = 1080,
    this.canvasBackgroundColor = 0xFF1F1B24,
    this.referenceMediaPath,
    this.referenceMediaType,
    List<DrawingLayer>? layers,
    List<LayerGroup>? layerGroups,
    List<String>? rootOrder,
    List<ReferenceLayer>? referenceLayers,
    this.activeReferenceLayerId,
    List<int>? referenceFrameTimesMs,
    this.referenceVisible = true,
    this.referenceOpacity = 1.0,
  }) : layers = layers ?? _layersFromLegacyFrames(frames),
       layerGroups = layerGroups ?? <LayerGroup>[],
       rootOrder =
           rootOrder ??
           _deriveRootOrder(
             layers ?? _layersFromLegacyFrames(frames),
             layerGroups ?? <LayerGroup>[],
           ),
       referenceLayers =
           referenceLayers ??
           _referenceLayersFromLegacy(
             referenceMediaPath: referenceMediaPath,
             referenceMediaType: referenceMediaType,
             referenceVisible: referenceVisible,
             referenceOpacity: referenceOpacity,
             referenceFrameTimesMs: referenceFrameTimesMs ?? <int>[],
           ),
       referenceFrameTimesMs = referenceFrameTimesMs ?? <int>[];

  factory InkdFramesProject.fromJson(Map<String, dynamic> json) {
    final legacyFrames = _readLegacyFrames(json['frames']);

    final rawLayers = json['layers'];
    final rawLayerGroups = json['layerGroups'];
    final rawRootOrder = json['rootOrder'];
    final rawReferenceLayers = json['referenceLayers'];

    final layers = rawLayers is List && rawLayers.isNotEmpty
        ? rawLayers
              .map(
                (layer) => DrawingLayer.fromJson(
                  Map<String, dynamic>.from(layer as Map),
                ),
              )
              .toList()
        : _layersFromLegacyFrames(legacyFrames);

    final layerGroups = rawLayerGroups is List
        ? rawLayerGroups
              .map(
                (group) => LayerGroup.fromJson(
                  Map<String, dynamic>.from(group as Map),
                ),
              )
              .toList()
        : <LayerGroup>[];

    final legacyReferenceFrameTimesMs = json['referenceFrameTimesMs'] is List
        ? (json['referenceFrameTimesMs'] as List)
              .map((time) => (time as num).toInt())
              .toList()
        : <int>[];

    final referenceLayers =
        rawReferenceLayers is List && rawReferenceLayers.isNotEmpty
        ? rawReferenceLayers
              .map(
                (reference) => ReferenceLayer.fromJson(
                  Map<String, dynamic>.from(reference as Map),
                ),
              )
              .toList()
        : _referenceLayersFromLegacy(
            referenceMediaPath: json['referenceMediaPath'] as String?,
            referenceMediaType: json['referenceMediaType'] as String?,
            referenceVisible: json['referenceVisible'] as bool? ?? true,
            referenceOpacity:
                (json['referenceOpacity'] as num?)?.toDouble().clamp(
                  0.0,
                  1.0,
                ) ??
                1.0,
            referenceFrameTimesMs: legacyReferenceFrameTimesMs,
          );

    final frameCount = legacyFrames.isNotEmpty
        ? legacyFrames.length
        : layers.isNotEmpty
        ? layers.first.frames.length
        : 1;

    final frames = legacyFrames.isNotEmpty
        ? legacyFrames
        : _legacyFramesFromLayers(layers, frameCount);

    return InkdFramesProject(
      id: json['id'] as String,
      name: json['name'] as String,
      fps: (json['fps'] as num).toDouble(),
      frames: frames,
      frameDurations: json['frameDurations'] != null
          ? (json['frameDurations'] as List)
                .map((duration) => (duration as num).toInt())
                .toList()
          : List<int>.filled(frameCount, 1),
      canvasWidth: (json['canvasWidth'] as num?)?.toDouble() ?? 1920,
      canvasHeight: (json['canvasHeight'] as num?)?.toDouble() ?? 1080,
      canvasBackgroundColor:
          (json['canvasBackgroundColor'] as num?)?.toInt() ?? 0xFF1F1B24,
      referenceMediaPath: json['referenceMediaPath'] as String?,
      referenceMediaType: json['referenceMediaType'] as String?,
      referenceVisible: json['referenceVisible'] as bool? ?? true,
      referenceOpacity:
          (json['referenceOpacity'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 1.0,
      layers: layers,
      layerGroups: layerGroups,
      rootOrder: rawRootOrder is List
          ? rawRootOrder.map((entry) => entry.toString()).toList()
          : null,
      referenceLayers: referenceLayers,
      activeReferenceLayerId:
          json['activeReferenceLayerId'] as String? ??
          (referenceLayers.isNotEmpty ? referenceLayers.first.id : null),
      referenceFrameTimesMs: legacyReferenceFrameTimesMs,
    );
  }

  final String id;
  final String name;
  final double fps;

  /// Legacy/composited frame representation.
  ///
  /// Kept while InkdFrames migrates to drawing layers and for backwards
  /// compatibility with older saved projects.
  final List<List<VectorStroke>> frames;

  final List<DrawingLayer> layers;
  final List<LayerGroup> layerGroups;

  /// Ordered root-level drawing hierarchy.
  ///
  /// Entries use:
  ///   `group:<id>`
  ///   `layer:<id>`
  ///
  /// Reference layers remain separate from the drawing hierarchy.
  final List<String> rootOrder;

  /// Persistent image/video reference layers.
  ///
  /// Older projects containing only referenceMediaPath/referenceMediaType are
  /// automatically migrated into a single ReferenceLayer when loaded.
  final List<ReferenceLayer> referenceLayers;

  /// Reference currently driving video playback/scrubbing.
  final String? activeReferenceLayerId;

  final List<int> frameDurations;
  final double canvasWidth;
  final double canvasHeight;
  final int canvasBackgroundColor;

  final String? referenceMediaPath;
  final String? referenceMediaType;

  final bool referenceVisible;
  final double referenceOpacity;

  /// Exact video timestamp belonging to each animation frame.
  ///
  /// Empty for blank animations, image references, and legacy projects.
  final List<int> referenceFrameTimesMs;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'fps': fps,

      // Keep the legacy representation during the migration so older
      // InkdFrames builds can still understand the project.
      'frames': frames
          .map((frame) => frame.map((stroke) => stroke.toJson()).toList())
          .toList(),

      'layers': layers.map((layer) => layer.toJson()).toList(),
      'layerGroups': layerGroups.map((group) => group.toJson()).toList(),
      'rootOrder': rootOrder,

      'referenceLayers': referenceLayers
          .map((reference) => reference.toJson())
          .toList(),
      'activeReferenceLayerId': activeReferenceLayerId,

      'frameDurations': frameDurations,
      'canvasWidth': canvasWidth,
      'canvasHeight': canvasHeight,
      'canvasBackgroundColor': canvasBackgroundColor,
      'referenceMediaPath': referenceMediaPath,
      'referenceMediaType': referenceMediaType,
      'referenceVisible': referenceVisible,
      'referenceOpacity': referenceOpacity,
      'referenceFrameTimesMs': referenceFrameTimesMs,
    };
  }

  static List<String> _deriveRootOrder(
    List<DrawingLayer> layers,
    List<LayerGroup> groups,
  ) {
    final nestedGroupIds = <String>{};
    final groupedLayerIds = <String>{};

    for (final group in groups) {
      nestedGroupIds.addAll(group.childGroupIds);
      groupedLayerIds.addAll(group.childLayerIds);
    }

    return <String>[
      for (final group in groups)
        if (!nestedGroupIds.contains(group.id)) 'group:${group.id}',
      for (final layer in layers)
        if (!groupedLayerIds.contains(layer.id)) 'layer:${layer.id}',
    ];
  }

  static List<List<VectorStroke>> _readLegacyFrames(dynamic rawFrames) {
    if (rawFrames is! List) {
      return <List<VectorStroke>>[];
    }

    return rawFrames
        .map(
          (frame) => (frame as List)
              .map(
                (stroke) => VectorStroke.fromJson(
                  Map<String, dynamic>.from(stroke as Map),
                ),
              )
              .toList(),
        )
        .toList();
  }

  static List<ReferenceLayer> _referenceLayersFromLegacy({
    required String? referenceMediaPath,
    required String? referenceMediaType,
    required bool referenceVisible,
    required double referenceOpacity,
    required List<int> referenceFrameTimesMs,
  }) {
    if (referenceMediaPath == null ||
        referenceMediaPath.isEmpty ||
        referenceMediaType == null ||
        referenceMediaType.isEmpty) {
      return <ReferenceLayer>[];
    }

    return <ReferenceLayer>[
      ReferenceLayer(
        id: 'reference_legacy',
        name: referenceMediaType == 'video'
            ? 'Video Reference'
            : 'Image Reference',
        mediaPath: referenceMediaPath,
        mediaType: referenceMediaType,
        visible: referenceVisible,
        opacity: referenceOpacity,
        frameTimesMs: List<int>.from(referenceFrameTimesMs),
      ),
    ];
  }

  static List<DrawingLayer> _layersFromLegacyFrames(
    List<List<VectorStroke>> frames,
  ) {
    final safeFrames = frames.isEmpty
        ? <List<VectorStroke>>[<VectorStroke>[]]
        : frames
              .map((frame) => frame.map((stroke) => stroke.copy()).toList())
              .toList();

    return [DrawingLayer(id: 'linework', name: 'Linework', frames: safeFrames)];
  }

  static List<List<VectorStroke>> _legacyFramesFromLayers(
    List<DrawingLayer> layers,
    int frameCount,
  ) {
    return List.generate(frameCount, (frameIndex) {
      final strokes = <VectorStroke>[];

      for (final layer in layers) {
        if (!layer.visible || frameIndex >= layer.frames.length) {
          continue;
        }

        strokes.addAll(layer.frames[frameIndex].map((stroke) => stroke.copy()));
      }

      return strokes;
    });
  }
}
