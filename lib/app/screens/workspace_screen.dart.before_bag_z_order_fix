import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';
import '../models/bag_item.dart';
import '../models/brush_preset.dart';
import '../models/drawing_layer.dart';
import '../models/inkdframes_project.dart';
import '../models/layer_group.dart';
import '../models/reference_layer.dart';
import '../models/vector_point.dart';
import '../models/vector_stroke.dart';
import '../painters/animation_canvas_painter.dart';
import '../painters/frame_thumbnail_painter.dart';
import '../services/animation_export_service.dart';
import '../services/brush_preset_service.dart';
import '../services/bag_service.dart';
import 'bag_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _ShapeToolType {
  line,
  rectangle,
  filledRectangle,
  perspectiveRectangle,
  square,
  filledSquare,
  circle,
  filledCircle,
}

typedef FrameHistorySnapshot = Map<String, List<VectorStroke>>;

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    this.projectId,
    this.projectName,
    this.initialCanvasWidth = 1920,
    this.initialCanvasHeight = 1080,
    this.initialReferenceMediaPath,
    this.initialReferenceMediaType,
    this.initialFps = 8,
    this.initialGenerateVideoTimeline = false,
  });

  final String? projectId;
  final String? projectName;
  final double initialCanvasWidth;
  final double initialCanvasHeight;
  final String? initialReferenceMediaPath;
  final String? initialReferenceMediaType;
  final double initialFps;

  /// True only when creating a brand-new project directly from video.
  final bool initialGenerateVideoTimeline;

  static const routeName = '/workspace';

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final List<List<VectorStroke>> _frames = [<VectorStroke>[]];
  final List<DrawingLayer> _layers = [
    DrawingLayer(id: 'linework', name: 'Linework', frames: [<VectorStroke>[]]),
  ];
  int _activeLayerIndex = 0;
  final List<LayerGroup> _layerGroups = <LayerGroup>[];
  final List<String> _rootLayerOrder = <String>['layer:linework'];
  String? _activeLayerGroupId;

  // Persistent reference-media layers.
  //
  // During the V1 migration the existing singular reference fields remain as
  // a compatibility bridge for playback/scrubbing. They represent whichever
  // ReferenceLayer is currently active.
  final List<ReferenceLayer> _referenceLayers = <ReferenceLayer>[];
  String? _activeReferenceLayerId;

  // Group context used when creating new drawing layers.
  String? _layerInsertionGroupId;

  // Drawing layers currently marked for a merge operation.
  final Set<String> _mergeSelectedLayerIds = <String>{};

  final List<int> _frameDurations = [1];
  final List<int> _referenceFrameTimesMs = <int>[];
  int _selectedFrameIndex = 0;
  int _activePointerCount = 0;
  List<VectorPoint> _draftStroke = const <VectorPoint>[];
  Timer? _playbackTimer;
  Timer? _autosaveTimer;
  bool _isPlaying = false;
  bool _showOnionSkin = true;
  bool _isEraserActive = false;
  bool _isFillToolActive = false;

  // Vector Tint Brush.
  //
  // Tint does not create new geometry. It blends the colour of existing
  // strokes on the active drawing layer toward the current brush colour.
  bool _isTintToolActive = false;

  // Tint tool modes:
  // false = gradually blend toward the selected colour.
  // true = replace the entire touched stroke colour.
  bool _isSolidRecolourMode = false;

  final Set<int> _tintTouchedStrokeIndices = <int>{};
  bool _tintGestureChanged = false;
  bool _tintGestureUndoCaptured = false;
  List<VectorPoint> _fillLassoPoints = const <VectorPoint>[];
  Offset? _fillStabilizerTrailingPosition;

  bool _isShapeToolActive = false;
  _ShapeToolType _shapeToolType = _ShapeToolType.line;
  Offset? _shapeStartPosition;
  List<VectorStroke> _draftShapeStrokes = const <VectorStroke>[];

  // Temporary four-corner editing state for Perspective Rectangle.
  bool _perspectiveShapeEditing = false;
  List<Offset> _perspectiveShapeCorners = const <Offset>[];
  int? _perspectiveDraggingCorner;

  // Precision Loupe.
  //
  // A canvas snapshot is captured when a Perspective corner is grabbed.
  // During the drag we only move the magnified crop, keeping S Pen/touch
  // interaction lightweight.
  ui.Image? _perspectiveLoupeImage;
  Offset? _perspectiveLoupeCanvasPosition;
  Offset? _perspectiveLoupeScreenPosition;
  final GlobalKey _workspaceStackKey = GlobalKey();

  bool _isTransformActive = false;
  bool _isTransformDragging = false;
  bool _isTransformScaling = false;
  bool _isTransformRotating = false;
  bool _isTransformPivotDragging = false;
  bool _transformScaleHorizontalOnly = false;
  bool _transformScaleVerticalOnly = false;

  Offset? _transformPivot;

  List<VectorPoint> _lassoPoints = const <VectorPoint>[];
  Map<String, Set<int>> _selectedTransformStrokes = <String, Set<int>>{};

  String? _transformReferenceLayerId;
  ReferenceLayer? _referenceTransformSnapshot;

  /// Temporary in-memory clipboard used by Transform copy/paste.
  final Map<String, List<VectorStroke>> _strokeClipboard =
      <String, List<VectorStroke>>{};

  Offset? _transformLastPosition;
  Offset? _transformScaleAnchor;
  double? _transformScaleStartDistance;
  Map<String, List<VectorStroke>>? _transformScaleSnapshot;

  Offset? _transformRotationCenter;
  double? _transformRotationStartAngle;
  Map<String, List<VectorStroke>>? _transformRotationSnapshot;
  bool _timingExpanded = false;
  bool _drawingExpanded = false;
  bool _timelineExpanded = false;
  bool? _editToolbarExpanded = false;
  bool _drawingMode = false;
  bool _blendExpanded = false;
  bool _blendSamplingArmed = false;
  bool _brushEyedropperArmed = false;

  bool _textureExpanded = false;
  bool _textureActive = false;
  String _texturePattern = 'stipple';
  double _textureScale = 8.0;
  double _textureDensity = 0.5;
  double _textureScatter = 18.0;
  List<VectorStroke> _draftTextureStrokes = <VectorStroke>[];
  final math.Random _textureRandom = math.Random();

  bool _stampBrushActive = false;
  bool _stampBrushPanelExpanded = true;
  BagItem? _stampBrushItem;
  double _stampBrushScale = 1.0;
  double _stampBrushSpacing = 120.0;
  double _stampBrushRotation = 0.0;
  double _stampBrushRandomRotation = 0.0;
  double _stampBrushScatter = 0.0;
  Offset? _stampBrushLastPosition;
  List<VectorStroke> _draftStampStrokes = <VectorStroke>[];
  final math.Random _stampBrushRandom = math.Random();

  Color _blendBaseColor = Colors.white;
  Color _blendSampleColor = Colors.black;
  double _blendAmount = 0.5;
  final GlobalKey _canvasSampleKey = GlobalKey();
  bool _isExporting = false;
  double _fps = 8;
  double _brushSize = 4.0;
  StrokeBrushType _brushType = StrokeBrushType.solid;
  double _brushOpacity = 1.0;
  double _stabilizerStrength = 0.55;
  double _stabilizerPullDistance = 14.0;
  Offset? _stabilizerTrailingPosition;
  double _canvasWidth = 1920;
  double _canvasHeight = 1080;
  Color _brushColor = Colors.white;
  Color _canvasBackgroundColor = const Color(0xFF1F1B24);
  final List<Color> _recentColors = <Color>[];
  final List<List<FrameHistorySnapshot>> _undoStacks = [[]];
  final List<List<FrameHistorySnapshot>> _redoStacks = [[]];

  final TransformationController _transformationController =
      TransformationController();

  // View-only canvas rotation.
  //
  // This never changes stroke/frame coordinates. Two touch pointers rotate
  // the visual canvas while drawing/export data remains untouched.
  double _canvasRotation = 0.0;
  final Map<int, Offset> _canvasTouchPointers = <int, Offset>{};
  double? _canvasRotationGestureStartAngle;
  double _canvasRotationGestureStartValue = 0.0;

  final ScrollController _timelineScrollController = ScrollController();
  final LayerLink _timingButtonLink = LayerLink();

  String _projectId = '';
  String _projectName = 'Untitled Animation';
  String? _referenceMediaPath;
  String? _referenceMediaType;
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  double _videoScrubPositionMs = 0.0;
  bool _isVideoScrubbing = false;
  double _videoScrubDragStartMs = 0.0;
  double _videoScrubDragStartSliderMs = 0.0;
  bool _referenceVisible = true;
  double _referenceOpacity = 1.0;
  bool _layersPanelExpanded = false;
  bool _transformToolbarExpanded = false;

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _autosaveTimer?.cancel();
    _videoController?.pause();
    _videoController?.dispose();
    _transformationController.dispose();
    _timelineScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    if (widget.projectId != null) {
      _projectId = widget.projectId!;
      _loadProject();
    } else {
      _projectId = _generateProjectId();
      _projectName = widget.projectName ?? 'Untitled Animation';
      _fps = widget.initialFps;
      _canvasWidth = widget.initialCanvasWidth;
      _canvasHeight = widget.initialCanvasHeight;
      _referenceMediaPath = widget.initialReferenceMediaPath;
      _referenceMediaType = widget.initialReferenceMediaType;

      if (_referenceMediaPath != null && _referenceMediaType != null) {
        final initialReference = ReferenceLayer(
          id: 'reference_${DateTime.now().microsecondsSinceEpoch}',
          name: _referenceMediaType == 'video'
              ? 'Video Reference'
              : 'Image Reference',
          mediaPath: _referenceMediaPath!,
          mediaType: _referenceMediaType!,
          visible: _referenceVisible,
          opacity: _referenceOpacity,
          frameTimesMs: List<int>.from(_referenceFrameTimesMs),
        );

        _referenceLayers.add(initialReference);
        _activeReferenceLayerId = initialReference.id;
      }

      if (_referenceMediaType == 'video') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _initializeVideoReference();
          }
        });
      }
    }
  }

  Future<void> _openBrushPresets() async {
    final presets = await BrushPresetService().loadPresets();

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.brush_outlined),
              SizedBox(width: 10),
              Text('Brush Presets'),
            ],
          ),
          content: SizedBox(
            width: 380,
            height: 360,
            child: presets.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.brush_outlined,
                          size: 42,
                          color: Colors.white38,
                        ),
                        SizedBox(height: 10),
                        Text('No saved brushes yet'),
                        SizedBox(height: 5),
                        Text(
                          'Save your current brush setup to start.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: presets.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final preset = presets[index];

                      return ListTile(
                        leading: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Color(preset.brushColor),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                        ),
                        title: Text(preset.name),
                        subtitle: Text(
                          preset.textureEnabled
                              ? 'Texture · ${preset.texturePattern} · '
                                    '${preset.brushSize.round()} px'
                              : '${preset.brushType.name} · '
                                    '${preset.brushSize.round()} px',
                        ),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _applyBrushPreset(preset);
                        },
                        trailing: IconButton(
                          tooltip: 'Delete Preset',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            Navigator.pop(dialogContext);

                            await _deleteBrushPreset(preset);

                            if (mounted) {
                              _openBrushPresets();
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveCurrentBrushPreset() async {
    var name = '';

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Save Brush Preset'),
          content: TextField(
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Preset name',
              hintText: 'e.g. Dust Cloud',
            ),
            onChanged: (value) {
              name = value;
            },
            onSubmitted: (value) {
              final trimmed = value.trim();

              if (trimmed.isNotEmpty) {
                Navigator.pop(dialogContext, trimmed);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = name.trim();

                if (trimmed.isNotEmpty) {
                  Navigator.pop(dialogContext, trimmed);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    final preset = BrushPreset(
      id: 'brush_${DateTime.now().microsecondsSinceEpoch}',
      name: result,
      createdAt: DateTime.now(),
      brushType: _brushType,
      brushSize: _brushSize,
      brushOpacity: _brushOpacity,
      stabilizerStrength: _stabilizerStrength,
      stabilizerPullDistance: _stabilizerPullDistance,
      brushColor: _brushColor.toARGB32(),
      textureEnabled: _textureActive,
      texturePattern: _texturePattern,
      textureScale: _textureScale,
      textureDensity: _textureDensity,
      textureScatter: _textureScatter,
    );

    await BrushPresetService().addPreset(preset);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${preset.name} saved to Brush Presets')),
    );
  }

  void _applyBrushPreset(BrushPreset preset) {
    setState(() {
      _brushType = preset.brushType;
      _brushSize = preset.brushSize.clamp(1.0, 20.0);
      _brushOpacity = preset.brushOpacity.clamp(0.05, 1.0);
      _stabilizerStrength = preset.stabilizerStrength.clamp(0.0, 0.9);
      _stabilizerPullDistance = preset.stabilizerPullDistance.clamp(0.0, 40.0);

      _brushColor = Color(preset.brushColor);
      _rememberRecentColor(_brushColor);

      _textureActive = preset.textureEnabled;
      _textureExpanded = preset.textureEnabled;
      _texturePattern = preset.texturePattern;
      _textureScale = preset.textureScale.clamp(2.0, 30.0);
      _textureDensity = preset.textureDensity.clamp(0.05, 1.0);
      _textureScatter = preset.textureScatter.clamp(0.0, 60.0);

      _draftTextureStrokes = <VectorStroke>[];

      if (_textureActive) {
        _blendSamplingArmed = false;
      }
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${preset.name} loaded')));
  }

  Future<void> _deleteBrushPreset(BrushPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Brush Preset?'),
          content: Text('Remove "${preset.name}" from your Brush Presets?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await BrushPresetService().deletePreset(preset.id);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${preset.name} deleted')));
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();

    _autosaveTimer = Timer(const Duration(seconds: 2), _saveProject);
  }

  Future<void> _saveProject() async {
    _rebuildCompositeFrames();
    _syncActiveReferenceLayerFromLegacyState();

    final project = InkdFramesProject(
      id: _projectId,
      name: _projectName,
      fps: _fps,
      frames: _frames,
      layers: _layers,
      layerGroups: _layerGroups,
      rootOrder: _rootLayerOrder,
      referenceLayers: _referenceLayers,
      activeReferenceLayerId: _activeReferenceLayerId,
      frameDurations: _frameDurations,
      canvasWidth: _canvasWidth,
      canvasHeight: _canvasHeight,
      canvasBackgroundColor: _canvasBackgroundColor.toARGB32(),
      referenceMediaPath: _referenceMediaPath,
      referenceMediaType: _referenceMediaType,
      referenceVisible: _referenceVisible,
      referenceOpacity: _referenceOpacity,
      referenceFrameTimesMs: _referenceFrameTimesMs,
    );

    final jsonString = jsonEncode(project.toJson());

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('project_${project.id}', jsonString);

    final projectIds = prefs.getStringList('project_ids') ?? [];

    if (!projectIds.contains(project.id)) {
      projectIds.add(project.id);
      await prefs.setStringList('project_ids', projectIds);
    }

    if (!mounted) return;
  }

  String _generateProjectId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  ReferenceLayer? get _activeReferenceLayer {
    if (_referenceLayers.isEmpty) {
      return null;
    }

    final activeId = _activeReferenceLayerId;

    if (activeId != null) {
      final index = _referenceLayers.indexWhere(
        (reference) => reference.id == activeId,
      );

      if (index != -1) {
        return _referenceLayers[index];
      }
    }

    return _referenceLayers.first;
  }

  void _syncActiveReferenceLayerFromLegacyState() {
    final path = _referenceMediaPath;
    final type = _referenceMediaType;

    if (path == null || path.isEmpty || type == null || type.isEmpty) {
      return;
    }

    var activeId = _activeReferenceLayerId;

    if (activeId == null) {
      activeId = 'reference_${DateTime.now().microsecondsSinceEpoch}';
      _activeReferenceLayerId = activeId;
    }

    final updated = ReferenceLayer(
      id: activeId,
      name: type == 'video' ? 'Video Reference' : 'Image Reference',
      mediaPath: path,
      mediaType: type,
      visible: _referenceVisible,
      opacity: _referenceOpacity,
      frameTimesMs: List<int>.from(_referenceFrameTimesMs),
    );

    final index = _referenceLayers.indexWhere(
      (reference) => reference.id == activeId,
    );

    if (index == -1) {
      _referenceLayers.add(updated);
      return;
    }

    final existing = _referenceLayers[index];

    _referenceLayers[index] = existing.copyWith(
      mediaPath: path,
      mediaType: type,
      visible: _referenceVisible,
      opacity: _referenceOpacity,
      frameTimesMs: List<int>.from(_referenceFrameTimesMs),
    );
  }

  void _loadLegacyReferenceStateFromActiveLayer() {
    final reference = _activeReferenceLayer;

    if (reference == null) {
      _referenceMediaPath = null;
      _referenceMediaType = null;
      _referenceVisible = true;
      _referenceOpacity = 1.0;
      _referenceFrameTimesMs.clear();
      return;
    }

    _activeReferenceLayerId = reference.id;
    _referenceMediaPath = reference.mediaPath;
    _referenceMediaType = reference.mediaType;
    _referenceVisible = reference.visible;
    _referenceOpacity = reference.opacity;

    _referenceFrameTimesMs
      ..clear()
      ..addAll(reference.frameTimesMs);
  }

  DrawingLayer get _activeLayer => _layers[_activeLayerIndex];

  List<List<VectorStroke>> _copyLayerFrames(List<List<VectorStroke>> frames) {
    return frames
        .map((frame) => frame.map((stroke) => stroke.copy()).toList())
        .toList();
  }

  DrawingLayer _copyLayer(DrawingLayer layer) {
    return DrawingLayer(
      id: layer.id,
      name: layer.name,
      visible: layer.visible,
      opacity: layer.opacity,
      frames: _copyLayerFrames(layer.frames),
    );
  }

  void _ensureLayerFrameCount() {
    final frameCount = _frameDurations.length;

    for (var layerIndex = 0; layerIndex < _layers.length; layerIndex++) {
      final layer = _layers[layerIndex];
      final frames = _copyLayerFrames(layer.frames);

      while (frames.length < frameCount) {
        frames.add(<VectorStroke>[]);
      }

      if (frames.length > frameCount) {
        frames.removeRange(frameCount, frames.length);
      }

      _layers[layerIndex] = layer.copyWith(frames: frames);
    }
  }

  VectorStroke _strokeWithOpacity(VectorStroke stroke, double opacity) {
    final sourceAlpha = stroke.color.a;

    return VectorStroke(
      points: List<VectorPoint>.from(stroke.points),
      strokeWidth: stroke.strokeWidth,
      filled: stroke.filled,
      brushType: stroke.brushType,
      color: stroke.color.withValues(
        alpha: (sourceAlpha * opacity).clamp(0.0, 1.0),
      ),
    );
  }

  List<DrawingLayer> _orderedDrawingLayers() {
    final ordered = <DrawingLayer>[];
    final visitedLayerIds = <String>{};
    final visitedGroupIds = <String>{};

    void addEntry(String entry) {
      if (entry.startsWith('layer:')) {
        final layerId = entry.substring(6);

        if (!visitedLayerIds.add(layerId)) {
          return;
        }

        final layerIndex = _layers.indexWhere((layer) => layer.id == layerId);

        if (layerIndex != -1) {
          ordered.add(_layers[layerIndex]);
        }

        return;
      }

      if (entry.startsWith('group:')) {
        final groupId = entry.substring(6);

        // Defensive cycle guard.
        if (!visitedGroupIds.add(groupId)) {
          return;
        }

        final groupIndex = _layerGroups.indexWhere(
          (group) => group.id == groupId,
        );

        if (groupIndex == -1) {
          return;
        }

        for (final childEntry in _layerGroups[groupIndex].childOrder) {
          addEntry(childEntry);
        }
      }
    }

    for (final entry in _rootLayerOrder) {
      addEntry(entry);
    }

    // Safety net for legacy or temporarily inconsistent project data.
    // Any valid drawing layer missing from the hierarchy remains visible
    // at the bottom rather than disappearing completely.
    for (final layer in _layers) {
      if (visitedLayerIds.add(layer.id)) {
        ordered.add(layer);
      }
    }

    return ordered;
  }

  List<VectorStroke> _compositeFrame(int frameIndex) {
    final strokes = <VectorStroke>[];
    final orderedLayers = _orderedDrawingLayers();

    // Hierarchy order is displayed top-to-bottom.
    // Paint bottom entries first so the top entry remains visually in front.
    for (final layer in orderedLayers.reversed) {
      if (!_isLayerEffectivelyVisible(layer) ||
          frameIndex < 0 ||
          frameIndex >= layer.frames.length) {
        continue;
      }

      for (final stroke in layer.frames[frameIndex]) {
        strokes.add(_strokeWithOpacity(stroke, layer.opacity));
      }
    }

    return strokes;
  }

  void _rebuildCompositeFrames() {
    _ensureLayerFrameCount();

    _frames
      ..clear()
      ..addAll(List.generate(_frameDurations.length, _compositeFrame));
  }

  void _resetUndoRedo() {
    _undoStacks
      ..clear()
      ..addAll(
        List.generate(_frameDurations.length, (_) => <FrameHistorySnapshot>[]),
      );

    _redoStacks
      ..clear()
      ..addAll(
        List.generate(_frameDurations.length, (_) => <FrameHistorySnapshot>[]),
      );
  }

  void _selectLayer(int index) {
    if (index < 0 || index >= _layers.length) return;

    final containingGroup = _groupContainingLayer(_layers[index].id);

    setState(() {
      _activeLayerIndex = index;
      _activeLayerGroupId = null;
      _layerInsertionGroupId = containingGroup?.id;
      _draftStroke = const <VectorPoint>[];
      _clearTransformSelection();
    });
  }

  LayerGroup? get _activeLayerGroup {
    final groupId = _activeLayerGroupId;

    if (groupId == null) return null;

    for (final group in _layerGroups) {
      if (group.id == groupId) return group;
    }

    return null;
  }

  LayerGroup? _groupContainingLayer(String layerId) {
    for (final group in _layerGroups) {
      if (group.childLayerIds.contains(layerId)) {
        return group;
      }
    }

    return null;
  }

  LayerGroup? _groupContainingGroup(String groupId) {
    for (final group in _layerGroups) {
      if (group.childGroupIds.contains(groupId)) {
        return group;
      }
    }

    return null;
  }

  bool _isGroupEffectivelyVisible(String groupId, {Set<String>? visited}) {
    final seen = visited ?? <String>{};

    // Defensive cycle guard for future drag-and-drop nesting.
    if (!seen.add(groupId)) {
      return false;
    }

    final groupIndex = _layerGroups.indexWhere((group) => group.id == groupId);

    if (groupIndex == -1) {
      return true;
    }

    final group = _layerGroups[groupIndex];

    if (!group.visible) {
      return false;
    }

    final parent = _groupContainingGroup(groupId);

    if (parent == null) {
      return true;
    }

    return _isGroupEffectivelyVisible(parent.id, visited: seen);
  }

  bool _isLayerEffectivelyVisible(DrawingLayer layer) {
    if (!layer.visible) {
      return false;
    }

    final group = _groupContainingLayer(layer.id);

    if (group == null) {
      return true;
    }

    return _isGroupEffectivelyVisible(group.id);
  }

  void _selectLayerGroup(String groupId) {
    final exists = _layerGroups.any((group) => group.id == groupId);

    if (!exists) return;

    setState(() {
      _activeLayerGroupId = groupId;
      _layerInsertionGroupId = groupId;
      _draftStroke = const <VectorPoint>[];
      _clearTransformSelection();
    });
  }

  void _insertBagItem(BagItem item) {
    if (item.layers.isEmpty) {
      return;
    }

    final frameCount = _frameDurations.length;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final parentGroupId = _activeLayerGroupId;

    final newLayers = <DrawingLayer>[];
    final newLayerIds = <String>[];

    for (var index = 0; index < item.layers.length; index++) {
      final bagLayer = item.layers[index];

      final layerId = 'bag_layer_${stamp}_$index';
      final frames = List.generate(frameCount, (_) => <VectorStroke>[]);

      if (_selectedFrameIndex >= 0 && _selectedFrameIndex < frames.length) {
        frames[_selectedFrameIndex] = bagLayer.strokes
            .map((stroke) => stroke.copy())
            .toList();
      }

      newLayerIds.add(layerId);

      newLayers.add(
        DrawingLayer(
          id: layerId,
          name: bagLayer.name,
          visible: bagLayer.visible,
          opacity: bagLayer.opacity,
          frames: frames,
        ),
      );
    }

    if (newLayers.isEmpty) {
      return;
    }

    final newGroup = LayerGroup(
      id: 'bag_group_$stamp',
      name: item.name,
      childLayerIds: newLayerIds,
      childOrder: <String>[for (final layerId in newLayerIds) 'layer:$layerId'],
      visible: true,
      expanded: true,
    );

    setState(() {
      _layers.insertAll(0, newLayers);
      _layerGroups.add(newGroup);

      final groupEntry = 'group:${newGroup.id}';

      if (parentGroupId != null) {
        final parentIndex = _layerGroups.indexWhere(
          (group) => group.id == parentGroupId,
        );

        if (parentIndex != -1) {
          final parent = _layerGroups[parentIndex];

          final childGroupIds = List<String>.from(parent.childGroupIds)
            ..remove(newGroup.id)
            ..insert(0, newGroup.id);

          final childOrder = List<String>.from(parent.childOrder)
            ..remove(groupEntry)
            ..insert(0, groupEntry);

          _layerGroups[parentIndex] = parent.copyWith(
            childGroupIds: childGroupIds,
            childOrder: childOrder,
            expanded: true,
          );
        } else {
          _rootLayerOrder
            ..remove(groupEntry)
            ..insert(0, groupEntry);
        }
      } else {
        _rootLayerOrder
          ..remove(groupEntry)
          ..insert(0, groupEntry);
      }

      // Select the newly unpacked group.
      _activeLayerGroupId = newGroup.id;
      _layerInsertionGroupId = newGroup.id;
      _activeLayerIndex = 0;

      _draftStroke = const <VectorPoint>[];
      _draftTextureStrokes = <VectorStroke>[];

      _clearFillLasso();
      _clearShapeDraft();
      _clearTransformSelection();

      // Bag items arrive ready to transform.
      _isEraserActive = false;
      _isFillToolActive = false;
      _isShapeToolActive = false;

      _stampBrushActive = false;
      _stampBrushItem = null;

      _isTransformActive = true;
      _transformToolbarExpanded = true;

      // Automatically select every stroke in the newly unpacked group.
      _selectedTransformStrokes = <String, Set<int>>{
        for (final layer in newLayers)
          if (_selectedFrameIndex >= 0 &&
              _selectedFrameIndex < layer.frames.length &&
              layer.frames[_selectedFrameIndex].isNotEmpty)
            layer.id: Set<int>.from(
              List<int>.generate(
                layer.frames[_selectedFrameIndex].length,
                (index) => index,
              ),
            ),
      };

      _resetUndoRedo();
      _rebuildCompositeFrames();
    });

    _scheduleAutosave();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.name} unpacked from your Bag 🎒')),
    );
  }

  Future<void> _openBag() async {
    final item = await Navigator.of(context).push<BagItem>(
      MaterialPageRoute<BagItem>(builder: (_) => const BagScreen()),
    );

    if (!mounted || item == null) {
      return;
    }

    _insertBagItem(item);
  }

  Future<void> _exportLayerGroupPng(String groupId) async {
    final groupIndex = _layerGroups.indexWhere((group) => group.id == groupId);

    if (groupIndex == -1) {
      return;
    }

    final group = _layerGroups[groupIndex];
    final exportStrokes = <VectorStroke>[];

    for (final layerId in group.childLayerIds) {
      final layerIndex = _layers.indexWhere((layer) => layer.id == layerId);

      if (layerIndex == -1) {
        continue;
      }

      final layer = _layers[layerIndex];

      if (!layer.visible ||
          _selectedFrameIndex < 0 ||
          _selectedFrameIndex >= layer.frames.length) {
        continue;
      }

      for (final stroke in layer.frames[_selectedFrameIndex]) {
        exportStrokes.add(_strokeWithOpacity(stroke, layer.opacity));
      }
    }

    if (exportStrokes.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This group has no visible artwork to export.'),
        ),
      );

      return;
    }

    try {
      final outputPath = await const AnimationExportService().exportPngAsset(
        assetName: group.name,
        strokes: exportStrokes,
        canvasWidth: _canvasWidth,
        canvasHeight: _canvasHeight,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${group.name} exported as PNG\n$outputPath'),
          duration: const Duration(seconds: 6),
        ),
      );
    } on UnsupportedError catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? error.toString())),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PNG export failed: $error')));
    }
  }

  Future<void> _addLayerGroupToBag(String groupId) async {
    final groupIndex = _layerGroups.indexWhere((group) => group.id == groupId);

    if (groupIndex == -1) {
      return;
    }

    final group = _layerGroups[groupIndex];

    final bagLayers = <BagLayer>[];

    for (final layerId in group.childLayerIds) {
      final layerIndex = _layers.indexWhere((layer) => layer.id == layerId);

      if (layerIndex == -1) {
        continue;
      }

      final layer = _layers[layerIndex];

      if (_selectedFrameIndex < 0 ||
          _selectedFrameIndex >= layer.frames.length) {
        continue;
      }

      bagLayers.add(
        BagLayer(
          name: layer.name,
          opacity: layer.opacity,
          visible: layer.visible,
          strokes: layer.frames[_selectedFrameIndex]
              .map((stroke) => stroke.copy())
              .toList(),
        ),
      );
    }

    if (bagLayers.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This group has nothing to add to the Bag.'),
        ),
      );

      return;
    }

    var itemName = group.name;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add to Bag'),
          content: TextFormField(
            initialValue: itemName,
            autofocus: true,
            onChanged: (value) => itemName = value,
            decoration: const InputDecoration(labelText: 'Item name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final trimmed = itemName.trim();

                if (trimmed.isNotEmpty) {
                  Navigator.pop(dialogContext, trimmed);
                }
              },
              icon: const Icon(Icons.backpack_outlined),
              label: const Text('Add to Bag'),
            ),
          ],
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    const pockets = <String>[
      'Sketches',
      'Characters',
      'Textures',
      'Props',
      'Brushes',
      'Misc.',
    ];

    final selectedPocket = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF21160F),
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(
                  'Put "$result" in which Pocket?',
                  style: const TextStyle(
                    color: Color(0xFFF1D3A2),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final pocket in pockets)
                ListTile(
                  leading: const Icon(
                    Icons.inventory_2_outlined,
                    color: Color(0xFFF1D3A2),
                  ),
                  title: Text(
                    pocket,
                    style: const TextStyle(color: Color(0xFFF4E5CF)),
                  ),
                  onTap: () => Navigator.pop(sheetContext, pocket),
                ),
            ],
          ),
        );
      },
    );

    if (selectedPocket == null || !mounted) {
      return;
    }

    final item = BagItem(
      id: 'bag_${DateTime.now().microsecondsSinceEpoch}',
      name: result,
      sourceGroupName: group.name,
      layers: bagLayers,
      createdAt: DateTime.now(),
    );

    await BagService().addItem(item);

    final prefs = await SharedPreferences.getInstance();

    const pocketAssignmentsKey = 'inkdframes_bag_pocket_assignments_v1';

    Map<String, String> pocketAssignments = <String, String>{};

    final rawAssignments = prefs.getString(pocketAssignmentsKey);

    if (rawAssignments != null && rawAssignments.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAssignments);

        if (decoded is Map) {
          pocketAssignments = decoded.map<String, String>(
            (key, value) => MapEntry(key.toString(), value.toString()),
          );
        }
      } catch (_) {
        pocketAssignments = <String, String>{};
      }
    }

    const builtInPocketIds = <String, String>{
      'Sketches': 'built_in_sketches',
      'Characters': 'built_in_characters',
      'Textures': 'built_in_textures',
      'Props': 'built_in_props',
      'Brushes': 'built_in_brushes',
      'Misc.': 'built_in_misc',
    };

    pocketAssignments[item.id] =
        builtInPocketIds[selectedPocket] ?? selectedPocket;

    await prefs.setString(pocketAssignmentsKey, jsonEncode(pocketAssignments));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.name} tucked into $selectedPocket 🎒')),
    );
  }

  Future<void> _exportDrawingLayerPng(int index) async {
    if (index < 0 || index >= _layers.length) {
      return;
    }

    final layer = _layers[index];

    if (!layer.visible ||
        _selectedFrameIndex < 0 ||
        _selectedFrameIndex >= layer.frames.length) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This layer has no visible artwork to export.'),
        ),
      );
      return;
    }

    final exportStrokes = layer.frames[_selectedFrameIndex]
        .map((stroke) => _strokeWithOpacity(stroke, layer.opacity))
        .toList();

    if (exportStrokes.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This layer has no artwork to export.')),
      );
      return;
    }

    try {
      final outputPath = await const AnimationExportService().exportPngAsset(
        assetName: layer.name,
        strokes: exportStrokes,
        canvasWidth: _canvasWidth,
        canvasHeight: _canvasHeight,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${layer.name} exported as PNG\n$outputPath'),
          duration: const Duration(seconds: 6),
        ),
      );
    } on UnsupportedError catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? error.toString())),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PNG export failed: $error')));
    }
  }

  Future<void> _addDrawingLayerToBag(int index) async {
    if (index < 0 || index >= _layers.length) {
      return;
    }

    final layer = _layers[index];

    if (_selectedFrameIndex < 0 ||
        _selectedFrameIndex >= layer.frames.length ||
        layer.frames[_selectedFrameIndex].isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This layer has nothing to add to the Bag.'),
        ),
      );
      return;
    }

    var itemName = layer.name;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add to Bag'),
          content: TextFormField(
            initialValue: itemName,
            autofocus: true,
            onChanged: (value) => itemName = value,
            decoration: const InputDecoration(labelText: 'Item name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final trimmed = itemName.trim();

                if (trimmed.isNotEmpty) {
                  Navigator.pop(dialogContext, trimmed);
                }
              },
              icon: const Icon(Icons.backpack_outlined),
              label: const Text('Add to Bag'),
            ),
          ],
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    const pockets = <String>[
      'Sketches',
      'Characters',
      'Textures',
      'Props',
      'Brushes',
      'Misc.',
    ];

    final selectedPocket = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF21160F),
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(
                  'Put "$result" in which Pocket?',
                  style: const TextStyle(
                    color: Color(0xFFF1D3A2),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final pocket in pockets)
                ListTile(
                  leading: const Icon(
                    Icons.inventory_2_outlined,
                    color: Color(0xFFF1D3A2),
                  ),
                  title: Text(
                    pocket,
                    style: const TextStyle(color: Color(0xFFF4E5CF)),
                  ),
                  onTap: () => Navigator.pop(sheetContext, pocket),
                ),
            ],
          ),
        );
      },
    );

    if (selectedPocket == null || !mounted) {
      return;
    }

    final item = BagItem(
      id: 'bag_${DateTime.now().microsecondsSinceEpoch}',
      name: result,
      sourceGroupName: layer.name,
      layers: [
        BagLayer(
          name: layer.name,
          opacity: layer.opacity,
          visible: layer.visible,
          strokes: layer.frames[_selectedFrameIndex]
              .map((stroke) => stroke.copy())
              .toList(),
        ),
      ],
      createdAt: DateTime.now(),
    );

    await BagService().addItem(item);

    final prefs = await SharedPreferences.getInstance();
    const pocketAssignmentsKey = 'inkdframes_bag_pocket_assignments_v1';

    Map<String, String> pocketAssignments = <String, String>{};
    final rawAssignments = prefs.getString(pocketAssignmentsKey);

    if (rawAssignments != null && rawAssignments.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAssignments);

        if (decoded is Map) {
          pocketAssignments = decoded.map<String, String>(
            (key, value) => MapEntry(key.toString(), value.toString()),
          );
        }
      } catch (_) {
        pocketAssignments = <String, String>{};
      }
    }

    const builtInPocketIds = <String, String>{
      'Sketches': 'built_in_sketches',
      'Characters': 'built_in_characters',
      'Textures': 'built_in_textures',
      'Props': 'built_in_props',
      'Brushes': 'built_in_brushes',
      'Misc.': 'built_in_misc',
    };

    pocketAssignments[item.id] =
        builtInPocketIds[selectedPocket] ?? selectedPocket;

    await prefs.setString(pocketAssignmentsKey, jsonEncode(pocketAssignments));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.name} tucked into $selectedPocket 🎒')),
    );
  }

  void _toggleLayerMergeSelection(int index) {
    if (index < 0 || index >= _layers.length) {
      return;
    }

    final layerId = _layers[index].id;

    setState(() {
      if (_mergeSelectedLayerIds.contains(layerId)) {
        _mergeSelectedLayerIds.remove(layerId);
      } else {
        _mergeSelectedLayerIds.add(layerId);
      }
    });
  }

  Future<void> _mergeSelectedDrawingLayers() async {
    if (_mergeSelectedLayerIds.length < 2) {
      return;
    }

    final selectedIndices = <int>[];

    for (var index = 0; index < _layers.length; index++) {
      if (_mergeSelectedLayerIds.contains(_layers[index].id)) {
        selectedIndices.add(index);
      }
    }

    if (selectedIndices.length < 2) {
      setState(() {
        _mergeSelectedLayerIds.clear();
      });
      return;
    }

    selectedIndices.sort();

    final firstLayer = _layers[selectedIndices.first];
    final firstGroup = _groupContainingLayer(firstLayer.id);

    // V1 guardrail: every merged layer must live in the same stack context.
    for (final index in selectedIndices) {
      final layer = _layers[index];
      final group = _groupContainingLayer(layer.id);

      if (group?.id != firstGroup?.id) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Merge layers must all be inside the same group or all be root layers.',
            ),
          ),
        );
        return;
      }

      if (!layer.visible) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Show all selected layers before merging them.'),
          ),
        );
        return;
      }
    }

    // Merging non-adjacent layers can change the visual stacking around layers
    // left between them, so keep V1 merges contiguous.
    for (var i = 1; i < selectedIndices.length; i++) {
      if (selectedIndices[i] != selectedIndices[i - 1] + 1) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Selected layers must be adjacent before they can be merged.',
            ),
          ),
        );
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Merge selected layers?'),
          content: Text(
            'Combine ${selectedIndices.length} layers into one drawing layer?\n\n'
            'Their current appearance and opacity will be baked into the merged layer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.merge_type),
              label: const Text('Merge Layers'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final frameCount = _frameDurations.length;

    final mergedFrames = List.generate(frameCount, (_) => <VectorStroke>[]);

    // _layers is top-to-bottom. Build the merged layer bottom-to-top so its
    // internal stroke order reproduces the same visual stack.
    for (final index in selectedIndices.reversed) {
      final layer = _layers[index];

      for (var frameIndex = 0; frameIndex < frameCount; frameIndex++) {
        if (frameIndex >= layer.frames.length) {
          continue;
        }

        mergedFrames[frameIndex].addAll(
          layer.frames[frameIndex].map(
            (stroke) => _strokeWithOpacity(stroke, layer.opacity),
          ),
        );
      }
    }

    final topIndex = selectedIndices.first;

    final selectedIds = selectedIndices
        .map((index) => _layers[index].id)
        .toSet();

    final mergedLayer = DrawingLayer(
      id: 'merged_${DateTime.now().microsecondsSinceEpoch}',
      name: 'Merged Layer',
      visible: true,
      opacity: 1.0,
      frames: mergedFrames,
    );

    setState(() {
      _layers.removeWhere((layer) => selectedIds.contains(layer.id));

      _layers.insert(topIndex, mergedLayer);

      if (firstGroup != null) {
        final groupIndex = _layerGroups.indexWhere(
          (group) => group.id == firstGroup.id,
        );

        if (groupIndex != -1) {
          final group = _layerGroups[groupIndex];

          final updatedIds = <String>[];
          var mergedInserted = false;

          for (final id in group.childLayerIds) {
            if (selectedIds.contains(id)) {
              if (!mergedInserted) {
                updatedIds.add(mergedLayer.id);
                mergedInserted = true;
              }
              continue;
            }

            updatedIds.add(id);
          }

          if (!mergedInserted) {
            updatedIds.insert(0, mergedLayer.id);
          }

          _layerGroups[groupIndex] = group.copyWith(childLayerIds: updatedIds);

          _layerInsertionGroupId = firstGroup.id;
        }
      } else {
        _layerInsertionGroupId = null;
      }

      _activeLayerGroupId = null;
      _activeLayerIndex = _layers.indexWhere(
        (layer) => layer.id == mergedLayer.id,
      );

      _mergeSelectedLayerIds.clear();

      _clearTransformSelection();
      _resetUndoRedo();
      _rebuildCompositeFrames();
    });

    _scheduleAutosave();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Layers merged into Merged Layer 🎨')),
    );
  }

  void _addLayerGroup() {
    final parentGroupId = _activeLayerGroupId;

    setState(() {
      final group = LayerGroup(
        id: 'group_${DateTime.now().microsecondsSinceEpoch}',
        name: 'Group ${_layerGroups.length + 1}',
        childLayerIds: <String>[],
        childGroupIds: <String>[],
        childOrder: <String>[],
      );

      _layerGroups.add(group);

      final groupEntry = 'group:${group.id}';

      // Selected group becomes the parent.
      if (parentGroupId != null) {
        final parentIndex = _layerGroups.indexWhere(
          (candidate) => candidate.id == parentGroupId,
        );

        if (parentIndex != -1) {
          final parent = _layerGroups[parentIndex];

          final childGroupIds = List<String>.from(parent.childGroupIds)
            ..remove(group.id)
            ..insert(0, group.id);

          final childOrder = List<String>.from(parent.childOrder)
            ..remove(groupEntry)
            ..insert(0, groupEntry);

          _layerGroups[parentIndex] = parent.copyWith(
            childGroupIds: childGroupIds,
            childOrder: childOrder,
            expanded: true,
          );
        } else {
          _rootLayerOrder
            ..remove(groupEntry)
            ..insert(0, groupEntry);
        }
      } else {
        _rootLayerOrder
          ..remove(groupEntry)
          ..insert(0, groupEntry);
      }

      _activeLayerGroupId = group.id;
      _layerInsertionGroupId = group.id;
      _clearTransformSelection();
    });

    _scheduleAutosave();
  }

  void _toggleLayerGroupExpanded(String groupId) {
    final index = _layerGroups.indexWhere((group) => group.id == groupId);

    if (index == -1) return;

    setState(() {
      final group = _layerGroups[index];

      _layerGroups[index] = group.copyWith(expanded: !group.expanded);
    });

    _scheduleAutosave();
  }

  void _setLayerGroupVisible(String groupId, bool visible) {
    final index = _layerGroups.indexWhere((group) => group.id == groupId);

    if (index == -1) return;

    setState(() {
      _layerGroups[index] = _layerGroups[index].copyWith(visible: visible);

      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
  }

  Future<void> _renameLayerGroup(String groupId) async {
    final index = _layerGroups.indexWhere((group) => group.id == groupId);

    if (index == -1) return;

    var name = _layerGroups[index].name;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename group'),
          content: TextFormField(
            initialValue: name,
            autofocus: true,
            onChanged: (value) => name = value,
            decoration: const InputDecoration(labelText: 'Group name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = name.trim();

                if (trimmed.isNotEmpty) {
                  Navigator.pop(dialogContext, trimmed);
                }
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    if (result == null || !mounted) return;

    setState(() {
      _layerGroups[index] = _layerGroups[index].copyWith(name: result);
    });

    _scheduleAutosave();
  }

  void _deleteLayerGroup(String groupId) {
    final rootIndex = _layerGroups.indexWhere((group) => group.id == groupId);

    if (rootIndex == -1) return;

    final groupIdsToDelete = <String>{};

    void collectGroupTree(String id) {
      if (!groupIdsToDelete.add(id)) {
        return;
      }

      final index = _layerGroups.indexWhere((group) => group.id == id);

      if (index == -1) {
        return;
      }

      for (final childGroupId in _layerGroups[index].childGroupIds) {
        collectGroupTree(childGroupId);
      }
    }

    collectGroupTree(groupId);

    final layerIdsToDelete = <String>{};

    for (final group in _layerGroups) {
      if (groupIdsToDelete.contains(group.id)) {
        layerIdsToDelete.addAll(group.childLayerIds);
      }
    }

    setState(() {
      _layers.removeWhere((layer) => layerIdsToDelete.contains(layer.id));

      _layerGroups.removeWhere((group) => groupIdsToDelete.contains(group.id));

      // Remove deleted branches from root ordering.
      _rootLayerOrder.removeWhere((entry) {
        if (entry.startsWith('group:')) {
          return groupIdsToDelete.contains(entry.substring(6));
        }

        if (entry.startsWith('layer:')) {
          return layerIdsToDelete.contains(entry.substring(6));
        }

        return false;
      });

      // Remove deleted branches from every surviving group.
      for (var i = 0; i < _layerGroups.length; i++) {
        final group = _layerGroups[i];

        final childGroupIds = List<String>.from(group.childGroupIds)
          ..removeWhere(groupIdsToDelete.contains);

        final childLayerIds = List<String>.from(group.childLayerIds)
          ..removeWhere(layerIdsToDelete.contains);

        final childOrder = List<String>.from(group.childOrder)
          ..removeWhere((entry) {
            if (entry.startsWith('group:')) {
              return groupIdsToDelete.contains(entry.substring(6));
            }

            if (entry.startsWith('layer:')) {
              return layerIdsToDelete.contains(entry.substring(6));
            }

            return false;
          });

        _layerGroups[i] = group.copyWith(
          childGroupIds: childGroupIds,
          childLayerIds: childLayerIds,
          childOrder: childOrder,
        );
      }

      // Never allow a project to contain zero drawing layers.
      if (_layers.isEmpty) {
        final fallbackId = 'linework_${DateTime.now().microsecondsSinceEpoch}';

        _layers.add(
          DrawingLayer(
            id: fallbackId,
            name: 'Linework',
            frames: List.generate(
              _frameDurations.length,
              (_) => <VectorStroke>[],
            ),
          ),
        );

        _rootLayerOrder
          ..clear()
          ..add('layer:$fallbackId');
      }

      if (_activeLayerGroupId != null &&
          groupIdsToDelete.contains(_activeLayerGroupId)) {
        _activeLayerGroupId = null;
      }

      if (_layerInsertionGroupId != null &&
          groupIdsToDelete.contains(_layerInsertionGroupId)) {
        _layerInsertionGroupId = null;
      }

      _activeLayerIndex = _activeLayerIndex.clamp(0, _layers.length - 1);

      _clearTransformSelection();
      _resetUndoRedo();
      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
  }

  Set<String> _groupDescendantIds(String groupId) {
    final descendants = <String>{};

    void collect(String parentId) {
      final parentIndex = _layerGroups.indexWhere(
        (group) => group.id == parentId,
      );

      if (parentIndex == -1) {
        return;
      }

      for (final childId in _layerGroups[parentIndex].childGroupIds) {
        if (descendants.add(childId)) {
          collect(childId);
        }
      }
    }

    collect(groupId);
    return descendants;
  }

  void _assignGroupToGroup(String groupId, String? parentGroupId) {
    if (parentGroupId == groupId) {
      return;
    }

    if (parentGroupId != null) {
      final descendants = _groupDescendantIds(groupId);

      // Prevent cycles such as:
      // A contains B, then attempting to move A inside B.
      if (descendants.contains(parentGroupId)) {
        return;
      }
    }

    final groupExists = _layerGroups.any((group) => group.id == groupId);

    if (!groupExists) {
      return;
    }

    final groupEntry = 'group:$groupId';

    setState(() {
      // Remove the group from its previous hierarchy location.
      _rootLayerOrder.remove(groupEntry);

      for (var i = 0; i < _layerGroups.length; i++) {
        final group = _layerGroups[i];

        if (group.id == groupId) {
          continue;
        }

        final childGroupIds = List<String>.from(group.childGroupIds)
          ..remove(groupId);

        final childOrder = List<String>.from(group.childOrder)
          ..remove(groupEntry);

        _layerGroups[i] = group.copyWith(
          childGroupIds: childGroupIds,
          childOrder: childOrder,
        );
      }

      // Insert into the new parent.
      if (parentGroupId != null) {
        final parentIndex = _layerGroups.indexWhere(
          (group) => group.id == parentGroupId,
        );

        if (parentIndex != -1) {
          final parent = _layerGroups[parentIndex];

          final childGroupIds = List<String>.from(parent.childGroupIds)
            ..remove(groupId)
            ..insert(0, groupId);

          final childOrder = List<String>.from(parent.childOrder)
            ..remove(groupEntry)
            ..insert(0, groupEntry);

          _layerGroups[parentIndex] = parent.copyWith(
            childGroupIds: childGroupIds,
            childOrder: childOrder,
            expanded: true,
          );
        } else {
          _rootLayerOrder
            ..remove(groupEntry)
            ..insert(0, groupEntry);
        }
      } else {
        _rootLayerOrder
          ..remove(groupEntry)
          ..insert(0, groupEntry);
      }

      _rebuildCompositeFrames();
      _clearTransformSelection();
    });

    _scheduleAutosave();
  }

  Future<void> _showMoveGroupDialog(String groupId) async {
    final groupIndex = _layerGroups.indexWhere((group) => group.id == groupId);

    if (groupIndex == -1 || !mounted) {
      return;
    }

    final movingGroup = _layerGroups[groupIndex];
    final descendants = _groupDescendantIds(groupId);
    final currentParent = _groupContainingGroup(groupId);

    final validParents = _layerGroups.where((group) {
      if (group.id == groupId) {
        return false;
      }

      if (descendants.contains(group.id)) {
        return false;
      }

      return true;
    }).toList();

    final selectedParentId = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Move "${movingGroup.name}"'),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: const Text('Root'),
                  trailing: currentParent == null
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop('__root__'),
                ),
                for (final group in validParents)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(group.name),
                    trailing: currentParent?.id == group.id
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.of(context).pop(group.id),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (!mounted || selectedParentId == null) {
      return;
    }

    if (selectedParentId == '__root__') {
      _assignGroupToGroup(groupId, null);
    } else {
      _assignGroupToGroup(groupId, selectedParentId);
    }
  }

  void _assignLayerToGroup(String layerId, String? groupId) {
    setState(() {
      final layerEntry = 'layer:$layerId';

      // Remove the layer from its previous hierarchy location.
      _rootLayerOrder.remove(layerEntry);

      for (var i = 0; i < _layerGroups.length; i++) {
        final group = _layerGroups[i];

        final childLayerIds = List<String>.from(group.childLayerIds)
          ..remove(layerId);

        final childOrder = List<String>.from(group.childOrder)
          ..remove(layerEntry);

        _layerGroups[i] = group.copyWith(
          childLayerIds: childLayerIds,
          childOrder: childOrder,
        );
      }

      // Insert into its new hierarchy location.
      if (groupId != null) {
        final groupIndex = _layerGroups.indexWhere(
          (group) => group.id == groupId,
        );

        if (groupIndex != -1) {
          final group = _layerGroups[groupIndex];

          final childLayerIds = List<String>.from(group.childLayerIds)
            ..remove(layerId)
            ..insert(0, layerId);

          final childOrder = List<String>.from(group.childOrder)
            ..remove(layerEntry)
            ..insert(0, layerEntry);

          _layerGroups[groupIndex] = group.copyWith(
            childLayerIds: childLayerIds,
            childOrder: childOrder,
            expanded: true,
          );
        } else {
          _rootLayerOrder.insert(0, layerEntry);
        }
      } else {
        _rootLayerOrder.insert(0, layerEntry);
      }

      _rebuildCompositeFrames();
      _clearTransformSelection();
    });

    _scheduleAutosave();
  }

  void _setLayerVisible(int index, bool visible) {
    if (index < 0 || index >= _layers.length) return;

    setState(() {
      _layers[index] = _layers[index].copyWith(visible: visible);
      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
  }

  void _setLayerOpacity(int index, double opacity) {
    if (index < 0 || index >= _layers.length) return;

    setState(() {
      _layers[index] = _layers[index].copyWith(
        opacity: opacity.clamp(0.0, 1.0),
      );

      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
  }

  void _addDrawingLayer() {
    final frameCount = _frameDurations.length;
    final newLayerId = 'layer_${DateTime.now().microsecondsSinceEpoch}';

    setState(() {
      _layers.insert(
        0,
        DrawingLayer(
          id: newLayerId,
          name: 'Layer ${_layers.length + 1}',
          frames: List.generate(frameCount, (_) => <VectorStroke>[]),
        ),
      );

      final layerEntry = 'layer:$newLayerId';
      final insertionGroupId = _layerInsertionGroupId;

      if (insertionGroupId != null) {
        final groupIndex = _layerGroups.indexWhere(
          (group) => group.id == insertionGroupId,
        );

        if (groupIndex != -1) {
          final group = _layerGroups[groupIndex];

          final childLayerIds = List<String>.from(group.childLayerIds)
            ..remove(newLayerId)
            ..insert(0, newLayerId);

          final childOrder = List<String>.from(group.childOrder)
            ..remove(layerEntry)
            ..insert(0, layerEntry);

          _layerGroups[groupIndex] = group.copyWith(
            childLayerIds: childLayerIds,
            childOrder: childOrder,
            expanded: true,
          );
        } else {
          _layerInsertionGroupId = null;

          _rootLayerOrder
            ..remove(layerEntry)
            ..insert(0, layerEntry);
        }
      } else {
        _rootLayerOrder
          ..remove(layerEntry)
          ..insert(0, layerEntry);
      }

      _activeLayerIndex = 0;
      _activeLayerGroupId = null;
      _mergeSelectedLayerIds.clear();

      _resetUndoRedo();
      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
  }

  void _deleteDrawingLayer(int index) {
    if (_layers.length <= 1 || index < 0 || index >= _layers.length) {
      return;
    }

    setState(() {
      final deletedLayerId = _layers[index].id;
      final deletedEntry = 'layer:$deletedLayerId';

      _layers.removeAt(index);
      _rootLayerOrder.remove(deletedEntry);

      for (var groupIndex = 0; groupIndex < _layerGroups.length; groupIndex++) {
        final group = _layerGroups[groupIndex];

        final childLayerIds = List<String>.from(group.childLayerIds)
          ..remove(deletedLayerId);

        final childOrder = List<String>.from(group.childOrder)
          ..remove(deletedEntry);

        _layerGroups[groupIndex] = group.copyWith(
          childLayerIds: childLayerIds,
          childOrder: childOrder,
        );
      }

      if (_activeLayerIndex >= _layers.length) {
        _activeLayerIndex = _layers.length - 1;
      } else if (index < _activeLayerIndex) {
        _activeLayerIndex -= 1;
      }

      _resetUndoRedo();
      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
  }

  Future<void> _renameDrawingLayer(int index) async {
    if (index < 0 || index >= _layers.length) return;

    var name = _layers[index].name;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename layer'),
          content: TextFormField(
            initialValue: name,
            autofocus: true,
            onChanged: (value) => name = value,
            decoration: const InputDecoration(labelText: 'Layer name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = name.trim();

                if (trimmed.isNotEmpty) {
                  Navigator.pop(dialogContext, trimmed);
                }
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    if (result == null || !mounted) return;

    setState(() {
      _layers[index] = _layers[index].copyWith(name: result);
    });

    _scheduleAutosave();
  }

  Future<void> _loadProject() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('project_$_projectId');

    if (jsonString == null) {
      return;
    }

    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    final project = InkdFramesProject.fromJson(json);

    if (!mounted) return;

    _projectId = project.id;
    _projectName = project.name;

    setState(() {
      _frameDurations
        ..clear()
        ..addAll(project.frameDurations);

      _layers
        ..clear()
        ..addAll(project.layers.map(_copyLayer));

      _layerGroups
        ..clear()
        ..addAll(
          project.layerGroups.map(
            (group) => LayerGroup(
              id: group.id,
              name: group.name,
              visible: group.visible,
              expanded: group.expanded,
              childLayerIds: List<String>.from(group.childLayerIds),
              childGroupIds: List<String>.from(group.childGroupIds),
              childOrder: List<String>.from(group.childOrder),
            ),
          ),
        );

      _rootLayerOrder
        ..clear()
        ..addAll(project.rootOrder);

      _activeLayerGroupId = null;

      if (_layers.isEmpty) {
        _layers.add(
          DrawingLayer(
            id: 'linework',
            name: 'Linework',
            frames: List.generate(
              _frameDurations.length,
              (_) => <VectorStroke>[],
            ),
          ),
        );

        _rootLayerOrder
          ..clear()
          ..add('layer:linework');
      }

      _activeLayerIndex = 0;
      _ensureLayerFrameCount();
      _rebuildCompositeFrames();
      _resetUndoRedo();

      _fps = project.fps;
      _canvasWidth = project.canvasWidth;
      _canvasHeight = project.canvasHeight;
      _canvasBackgroundColor = Color(project.canvasBackgroundColor);
      _referenceLayers
        ..clear()
        ..addAll(
          project.referenceLayers.map(
            (reference) => reference.copyWith(
              frameTimesMs: List<int>.from(reference.frameTimesMs),
            ),
          ),
        );

      _activeReferenceLayerId = project.activeReferenceLayerId;

      _loadLegacyReferenceStateFromActiveLayer();

      _selectedFrameIndex = 0;
      _draftStroke = const <VectorPoint>[];
    });

    if (_referenceMediaType == 'video') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initializeVideoReference();
        }
      });
    }
  }

  Future<void> _initializeVideoReference() async {
    if (_referenceMediaType != 'video' || _referenceMediaPath == null) {
      final oldController = _videoController;

      if (mounted) {
        setState(() {
          _videoController = null;
          _videoReady = false;
        });
      }

      await oldController?.dispose();
      return;
    }

    final newController = VideoPlayerController.file(
      File(_referenceMediaPath!),
    );

    try {
      await newController.initialize();
      await newController.setLooping(true);

      if (!mounted) {
        await newController.dispose();
        return;
      }

      final oldController = _videoController;

      setState(() {
        _videoController = newController;
        _videoReady = true;
        _videoScrubPositionMs = newController.value.position.inMilliseconds
            .toDouble();
      });

      // Video references now start with the existing animation timeline.
      // Users manually create only the poses/frames they actually want.
      _syncVideoToSelectedFrame();

      if (oldController != null && oldController != newController) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          oldController.dispose();
        });
      }
    } catch (error, stackTrace) {
      debugPrint('❌ Video reference initialization failed: $error');
      debugPrint(stackTrace.toString());

      await newController.dispose();

      if (!mounted) return;

      setState(() {
        _videoReady = false;
      });
    }
  }

  String _formatVideoTime(Duration position) {
    final totalMilliseconds = position.inMilliseconds;
    final minutes = totalMilliseconds ~/ 60000;
    final seconds = (totalMilliseconds ~/ 1000) % 60;
    final milliseconds = totalMilliseconds % 1000;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${milliseconds.toString().padLeft(3, '0')}';
  }

  Future<void> _seekReferenceVideoToMs(double milliseconds) async {
    final controller = _videoController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final durationMs = controller.value.duration.inMilliseconds;

    if (durationMs <= 0) {
      return;
    }

    final safeMs = milliseconds.clamp(
      0.0,
      math.max(0, durationMs - 1).toDouble(),
    );

    await controller.seekTo(Duration(milliseconds: safeMs.round()));

    if (!mounted) {
      return;
    }

    setState(() {
      _videoScrubPositionMs = safeMs;
    });
  }

  Future<void> _stepReferenceVideo(int direction) async {
    final controller = _videoController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (controller.value.isPlaying) {
      await controller.pause();
    }

    final durationMs = controller.value.duration.inMilliseconds;

    if (durationMs <= 0) {
      return;
    }

    // Step by one source-video frame.
    // 30 fps is used as a practical default where the source FPS
    // is not exposed by video_player.
    const frameDurationMs = 1000.0 / 30.0;

    final currentMs = controller.value.position.inMilliseconds.toDouble();

    final targetMs = (currentMs + (frameDurationMs * direction)).clamp(
      0.0,
      (durationMs - 1).toDouble(),
    );

    await _seekReferenceVideoToMs(targetMs);
  }

  void _resetCanvasView() {
    _transformationController.value = Matrix4.identity();

    setState(() {
      _canvasRotation = 0.0;
      _canvasTouchPointers.clear();
      _canvasRotationGestureStartAngle = null;
      _canvasRotationGestureStartValue = 0.0;
    });
  }

  void _findNextReferencePose() {
    final controller = _videoController;

    if (_referenceMediaType != 'video' ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    setState(() {
      // Return from drawing to pose hunting.
      _drawingMode = false;
      _drawingExpanded = false;

      // Reopen the reference controls.
      _layersPanelExpanded = true;
      _referenceVisible = true;

      // Keep the current animation frame and video position intact.
      _isVideoScrubbing = false;
      _videoScrubPositionMs = controller.value.position.inMilliseconds
          .toDouble();

      _blendExpanded = false;
      _blendSamplingArmed = false;
      _textureExpanded = false;
      _textureActive = false;
      _stampBrushPanelExpanded = false;

      _isEraserActive = false;
      _isFillToolActive = false;
      _isShapeToolActive = false;
      _isTransformActive = false;
      _transformToolbarExpanded = false;

      _draftStroke = const <VectorPoint>[];
      _draftTextureStrokes = <VectorStroke>[];
      _draftStampStrokes = <VectorStroke>[];

      _clearFillLasso();
      _clearShapeDraft();
      _clearTransformSelection();
    });
  }

  void _captureReferencePose() {
    final controller = _videoController;

    if (_referenceMediaType != 'video' ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    _addFrame();

    setState(() {
      // Leave pose-hunting mode and clear the canvas for drawing.
      _isVideoScrubbing = false;
      _layersPanelExpanded = false;

      // Open the drawing tools ready for the captured frame.
      _drawingMode = true;
      _drawingExpanded = true;

      _timingExpanded = false;
      _timelineExpanded = false;
      _transformToolbarExpanded = false;

      _isEraserActive = false;
      _isFillToolActive = false;
      _isShapeToolActive = false;
      _isTransformActive = false;

      _draftStroke = const <VectorPoint>[];
      _clearFillLasso();
      _clearShapeDraft();
      _clearTransformSelection();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pose captured at ${_formatVideoTime(controller.value.position)}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addFrame() {
    final controller = _videoController;

    final capturedReferenceTimeMs =
        controller != null &&
            controller.value.isInitialized &&
            _referenceMediaType == 'video'
        ? controller.value.position.inMilliseconds
        : null;

    final insertIndex = (_selectedFrameIndex + 1).clamp(
      0,
      _frameDurations.length,
    );

    setState(() {
      _frameDurations.insert(insertIndex, 1);

      if (capturedReferenceTimeMs != null) {
        final safeReferenceIndex = insertIndex.clamp(
          0,
          _referenceFrameTimesMs.length,
        );

        _referenceFrameTimesMs.insert(
          safeReferenceIndex,
          capturedReferenceTimeMs,
        );
      } else if (_referenceFrameTimesMs.isNotEmpty) {
        final fallbackIndex = _selectedFrameIndex.clamp(
          0,
          _referenceFrameTimesMs.length - 1,
        );

        final safeReferenceIndex = insertIndex.clamp(
          0,
          _referenceFrameTimesMs.length,
        );

        _referenceFrameTimesMs.insert(
          safeReferenceIndex,
          _referenceFrameTimesMs[fallbackIndex],
        );
      }

      for (var i = 0; i < _layers.length; i++) {
        final layer = _layers[i];
        final frames = _copyLayerFrames(layer.frames);

        frames.insert(insertIndex, <VectorStroke>[]);

        _layers[i] = layer.copyWith(frames: frames);
      }

      _selectedFrameIndex = insertIndex;
      _draftStroke = const <VectorPoint>[];

      _resetUndoRedo();
      _rebuildCompositeFrames();
    });

    _scheduleAutosave();

    if (capturedReferenceTimeMs != null) {
      _videoScrubPositionMs = capturedReferenceTimeMs.toDouble();
    }
  }

  void _duplicateFrame() {
    setState(() {
      for (var i = 0; i < _layers.length; i++) {
        final layer = _layers[i];
        final frames = _copyLayerFrames(layer.frames);

        frames.add(
          layer.frames[_selectedFrameIndex]
              .map((stroke) => stroke.copy())
              .toList(),
        );

        _layers[i] = layer.copyWith(frames: frames);
      }

      _frameDurations.add(_frameDurations[_selectedFrameIndex]);

      if (_referenceFrameTimesMs.isNotEmpty &&
          _selectedFrameIndex < _referenceFrameTimesMs.length) {
        _referenceFrameTimesMs.add(_referenceFrameTimesMs[_selectedFrameIndex]);
      }

      _selectedFrameIndex = _frameDurations.length - 1;
      _draftStroke = const <VectorPoint>[];

      _resetUndoRedo();
      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
  }

  void _deleteFrame() {
    if (_frameDurations.length <= 1) return;

    setState(() {
      for (var i = 0; i < _layers.length; i++) {
        final layer = _layers[i];
        final frames = _copyLayerFrames(layer.frames)
          ..removeAt(_selectedFrameIndex);

        _layers[i] = layer.copyWith(frames: frames);
      }

      _frameDurations.removeAt(_selectedFrameIndex);

      if (_selectedFrameIndex < _referenceFrameTimesMs.length) {
        _referenceFrameTimesMs.removeAt(_selectedFrameIndex);
      }

      if (_selectedFrameIndex >= _frameDurations.length) {
        _selectedFrameIndex = _frameDurations.length - 1;
      }

      _draftStroke = const <VectorPoint>[];

      _resetUndoRedo();
      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
  }

  void _toggleOnionSkin() {
    setState(() {
      _showOnionSkin = !_showOnionSkin;
    });
  }

  void _reorderFrame(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;

    setState(() {
      for (var i = 0; i < _layers.length; i++) {
        final layer = _layers[i];
        final frames = _copyLayerFrames(layer.frames);
        final frame = frames.removeAt(oldIndex);
        frames.insert(newIndex, frame);
        _layers[i] = layer.copyWith(frames: frames);
      }

      final duration = _frameDurations.removeAt(oldIndex);
      _frameDurations.insert(newIndex, duration);

      if (oldIndex < _referenceFrameTimesMs.length) {
        final referenceTime = _referenceFrameTimesMs.removeAt(oldIndex);

        final safeNewIndex = newIndex.clamp(0, _referenceFrameTimesMs.length);

        _referenceFrameTimesMs.insert(safeNewIndex, referenceTime);
      }

      if (_selectedFrameIndex == oldIndex) {
        _selectedFrameIndex = newIndex;
      } else if (oldIndex < _selectedFrameIndex &&
          _selectedFrameIndex <= newIndex) {
        _selectedFrameIndex -= 1;
      } else if (newIndex <= _selectedFrameIndex &&
          _selectedFrameIndex < oldIndex) {
        _selectedFrameIndex += 1;
      }

      _resetUndoRedo();
      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
  }

  String _referenceTimestampForFrame(int index) {
    final position = _videoPositionForFrame(index);

    final totalMilliseconds = position.inMilliseconds;
    final minutes = totalMilliseconds ~/ 60000;
    final seconds = (totalMilliseconds ~/ 1000) % 60;
    final milliseconds = totalMilliseconds % 1000;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${milliseconds.toString().padLeft(3, '0')}';
  }

  void _scrollTimelineToFrame(int index) {
    if (!_timelineScrollController.hasClients) return;

    const itemExtent = 70.0;

    final target =
        (index * itemExtent) -
        (_timelineScrollController.position.viewportDimension / 2) +
        (itemExtent / 2);

    final clamped = target.clamp(
      0.0,
      _timelineScrollController.position.maxScrollExtent,
    );

    _timelineScrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _stopPlaybackForNavigation() {
    if (!_isPlaying) return;

    _playbackTimer?.cancel();

    final controller = _videoController;

    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isPlaying) {
      unawaited(controller.pause());
    }

    _isPlaying = false;
  }

  void _navigateToFrame(int index) {
    if (_frames.isEmpty) return;

    final safeIndex = index.clamp(0, _frames.length - 1);

    _stopPlaybackForNavigation();
    _selectFrame(safeIndex);
  }

  void _previousFrame() {
    _navigateToFrame(_selectedFrameIndex - 1);
  }

  void _nextFrame() {
    _navigateToFrame(_selectedFrameIndex + 1);
  }

  void _selectFrame(int index) {
    if (index < 0 || index >= _frames.length) {
      return;
    }

    setState(() {
      _selectedFrameIndex = index;
      _draftStroke = const <VectorPoint>[];
      _clearTransformSelection();
    });

    _syncVideoToSelectedFrame();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollTimelineToFrame(index);
      }
    });
  }

  void _clearCurrentFrame() {
    _saveUndoState();

    setState(() {
      final layer = _activeLayer;
      final frames = _copyLayerFrames(layer.frames);

      frames[_selectedFrameIndex] = <VectorStroke>[];

      _layers[_activeLayerIndex] = layer.copyWith(frames: frames);

      _draftStroke = const <VectorPoint>[];
      _stabilizerTrailingPosition = null;
      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
  }

  FrameHistorySnapshot _frameHistorySnapshot() {
    final snapshot = <String, List<VectorStroke>>{};

    if (_selectedFrameIndex < 0 ||
        _selectedFrameIndex >= _frameDurations.length) {
      return snapshot;
    }

    for (final layer in _layers) {
      if (_selectedFrameIndex >= layer.frames.length) {
        continue;
      }

      snapshot[layer.id] = layer.frames[_selectedFrameIndex]
          .map((stroke) => stroke.copy())
          .toList();
    }

    return snapshot;
  }

  void _restoreFrameHistorySnapshot(FrameHistorySnapshot snapshot) {
    if (_selectedFrameIndex < 0 ||
        _selectedFrameIndex >= _frameDurations.length) {
      return;
    }

    for (var layerIndex = 0; layerIndex < _layers.length; layerIndex++) {
      final layer = _layers[layerIndex];

      if (_selectedFrameIndex >= layer.frames.length) {
        continue;
      }

      final savedStrokes = snapshot[layer.id];

      if (savedStrokes == null) {
        continue;
      }

      final frames = _copyLayerFrames(layer.frames);

      frames[_selectedFrameIndex] = savedStrokes
          .map((stroke) => stroke.copy())
          .toList();

      _layers[layerIndex] = layer.copyWith(frames: frames);
    }

    _rebuildCompositeFrames();
  }

  void _saveUndoState() {
    if (_selectedFrameIndex < 0 || _selectedFrameIndex >= _undoStacks.length) {
      return;
    }

    _undoStacks[_selectedFrameIndex].add(_frameHistorySnapshot());
    _redoStacks[_selectedFrameIndex].clear();
  }

  Duration _videoPositionForFrame(int index) {
    if (index >= 0 && index < _referenceFrameTimesMs.length) {
      return Duration(milliseconds: _referenceFrameTimesMs[index]);
    }

    // Legacy fallback for older projects created before
    // permanent reference timestamps existed.
    var timelineUnits = 0;

    for (var i = 0; i < index && i < _frameDurations.length; i++) {
      timelineUnits += _frameDurations[i];
    }

    final microseconds = ((timelineUnits / _fps) * 1000000).round();

    return Duration(microseconds: microseconds);
  }

  Future<void> _syncVideoToFrame(int index) async {
    final controller = _videoController;

    if (controller == null ||
        !controller.value.isInitialized ||
        index < 0 ||
        index >= _frames.length) {
      return;
    }

    var target = _videoPositionForFrame(index);
    final videoDuration = controller.value.duration;

    if (videoDuration > Duration.zero && target > videoDuration) {
      target = videoDuration;
    }

    await controller.seekTo(target);
  }

  void _syncVideoToSelectedFrame() {
    unawaited(_syncVideoToFrame(_selectedFrameIndex));
  }

  Future<void> _syncVideoToSelectedFrameDuringPlayback() async {
    final controller = _videoController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    await _syncVideoToFrame(_selectedFrameIndex);

    // Reference video stays frame-locked to the animation timeline.
    // It must not free-run between drawing frames.
    if (controller.value.isPlaying) {
      await controller.pause();
    }
  }

  void _startPlaybackTimer() {
    _playbackTimer?.cancel();

    final baseFrameMilliseconds = (1000 / _fps).round().clamp(40, 1000);
    final frameMilliseconds =
        (baseFrameMilliseconds * _frameDurations[_selectedFrameIndex]).round();

    _playbackTimer = Timer(Duration(milliseconds: frameMilliseconds), () {
      if (!mounted || !_isPlaying) return;

      setState(() {
        if (_selectedFrameIndex < _frames.length - 1) {
          _selectedFrameIndex += 1;
        } else {
          _selectedFrameIndex = 0;
        }
      });

      final controller = _videoController;

      if (controller != null && controller.value.isInitialized) {
        unawaited(_syncVideoToSelectedFrameDuringPlayback());
      }

      _scrollTimelineToFrame(_selectedFrameIndex);
      _startPlaybackTimer();
    });
  }

  Future<void> _togglePlayback() async {
    if (_frames.length < 2) {
      return;
    }

    final controller = _videoController;
    final hasVideo = controller != null && controller.value.isInitialized;

    if (_isPlaying) {
      _playbackTimer?.cancel();

      if (hasVideo && controller.value.isPlaying) {
        await controller.pause();
      }

      if (!mounted) return;

      setState(() => _isPlaying = false);
      return;
    }

    if (hasVideo) {
      await controller.pause();
      await _syncVideoToFrame(_selectedFrameIndex);
    }

    if (!mounted) return;

    setState(() {
      _isPlaying = true;
      _draftStroke = const <VectorPoint>[];
    });

    _startPlaybackTimer();
  }

  ReferenceLayer? get _referenceTransformTarget {
    final referenceId = _transformReferenceLayerId;

    if (referenceId == null) {
      return null;
    }

    final index = _referenceLayers.indexWhere(
      (reference) => reference.id == referenceId,
    );

    if (index == -1) {
      return null;
    }

    return _referenceLayers[index];
  }

  Offset get _referenceCanvasCenter {
    return Offset(_canvasWidth / 2, _canvasHeight / 2);
  }

  Rect get _referenceBaseTransformBounds {
    final shortestSide = math.min(_canvasWidth, _canvasHeight);

    // Keep transform handles comfortably inside the canvas.
    final inset = shortestSide * 0.06;

    return Rect.fromLTWH(0, 0, _canvasWidth, _canvasHeight).deflate(inset);
  }

  Offset _referenceDisplayedCenter(ReferenceLayer reference) {
    return _referenceCanvasCenter +
        Offset(reference.offsetX, reference.offsetY);
  }

  Rect _referenceTransformBounds(ReferenceLayer reference) {
    final baseBounds = _referenceBaseTransformBounds;
    final baseCenter = _referenceCanvasCenter;

    final cosAngle = math.cos(reference.rotation);
    final sinAngle = math.sin(reference.rotation);

    Offset transformPoint(Offset point) {
      final localX = (point.dx - baseCenter.dx) * reference.scaleX;
      final localY = (point.dy - baseCenter.dy) * reference.scaleY;

      final rotatedX = (localX * cosAngle) - (localY * sinAngle);
      final rotatedY = (localX * sinAngle) + (localY * cosAngle);

      return Offset(
        baseCenter.dx + reference.offsetX + rotatedX,
        baseCenter.dy + reference.offsetY + rotatedY,
      );
    }

    final points = <Offset>[
      transformPoint(baseBounds.topLeft),
      transformPoint(baseBounds.topRight),
      transformPoint(baseBounds.bottomLeft),
      transformPoint(baseBounds.bottomRight),
    ];

    final minX = points.map((point) => point.dx).reduce(math.min);
    final minY = points.map((point) => point.dy).reduce(math.min);
    final maxX = points.map((point) => point.dx).reduce(math.max);
    final maxY = points.map((point) => point.dy).reduce(math.max);

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Rect? _transformSelectionBounds() {
    final reference = _referenceTransformTarget;

    if (reference != null) {
      return _referenceTransformBounds(reference);
    }

    return _selectedStrokeBounds();
  }

  void _replaceReferenceTransform(ReferenceLayer updated) {
    final index = _referenceLayers.indexWhere(
      (reference) => reference.id == updated.id,
    );

    if (index == -1) {
      return;
    }

    _referenceLayers[index] = updated;
  }

  void _moveReferenceTransform(Offset delta) {
    final reference = _referenceTransformTarget;

    if (reference == null) {
      return;
    }

    final hasStoredPivot = reference.pivotX != null && reference.pivotY != null;

    _replaceReferenceTransform(
      reference.copyWith(
        offsetX: reference.offsetX + delta.dx,
        offsetY: reference.offsetY + delta.dy,
        pivotX: hasStoredPivot
            ? reference.pivotX! + delta.dx
            : reference.pivotX,
        pivotY: hasStoredPivot
            ? reference.pivotY! + delta.dy
            : reference.pivotY,
      ),
    );
  }

  void _setReferenceTransformPivot(Offset pivot) {
    final reference = _referenceTransformTarget;

    if (reference == null) {
      return;
    }

    _replaceReferenceTransform(
      reference.copyWith(pivotX: pivot.dx, pivotY: pivot.dy),
    );
  }

  void _rotateReferenceTransform(
    double angle,
    Offset pivot,
    ReferenceLayer snapshot,
  ) {
    final startCenter = _referenceDisplayedCenter(snapshot);

    final relative = startCenter - pivot;
    final cosAngle = math.cos(angle);
    final sinAngle = math.sin(angle);

    final rotatedCenter = Offset(
      pivot.dx + (relative.dx * cosAngle) - (relative.dy * sinAngle),
      pivot.dy + (relative.dx * sinAngle) + (relative.dy * cosAngle),
    );

    final newOffset = rotatedCenter - _referenceCanvasCenter;

    _replaceReferenceTransform(
      snapshot.copyWith(
        offsetX: newOffset.dx,
        offsetY: newOffset.dy,
        rotation: snapshot.rotation + angle,
      ),
    );
  }

  void _scaleReferenceTransform(
    double scaleX,
    double scaleY,
    Offset anchor,
    ReferenceLayer snapshot,
  ) {
    final safeScaleX = scaleX.clamp(0.05, 20.0);
    final safeScaleY = scaleY.clamp(0.05, 20.0);

    final startCenter = _referenceDisplayedCenter(snapshot);

    final newCenter = Offset(
      anchor.dx + ((startCenter.dx - anchor.dx) * safeScaleX),
      anchor.dy + ((startCenter.dy - anchor.dy) * safeScaleY),
    );

    final newOffset = newCenter - _referenceCanvasCenter;

    _replaceReferenceTransform(
      snapshot.copyWith(
        offsetX: newOffset.dx,
        offsetY: newOffset.dy,
        scaleX: snapshot.scaleX * safeScaleX,
        scaleY: snapshot.scaleY * safeScaleY,
      ),
    );
  }

  Future<void> _enterReferenceTransform(String referenceId) async {
    await _selectReferenceLayer(referenceId);

    if (!mounted) {
      return;
    }

    final index = _referenceLayers.indexWhere(
      (reference) => reference.id == referenceId,
    );

    if (index == -1) {
      return;
    }

    final reference = _referenceLayers[index];

    setState(() {
      _draftStroke = const <VectorPoint>[];
      _draftTextureStrokes = <VectorStroke>[];
      _draftStampStrokes = <VectorStroke>[];

      _clearFillLasso();
      _clearShapeDraft();
      _clearTransformSelection();

      _activeLayerGroupId = null;

      _isEraserActive = false;
      _isFillToolActive = false;
      _isShapeToolActive = false;

      _stampBrushActive = false;
      _stampBrushItem = null;

      _isTransformActive = true;
      _transformToolbarExpanded = true;

      _transformReferenceLayerId = referenceId;

      final bounds = _referenceTransformBounds(reference);

      if (reference.pivotX != null && reference.pivotY != null) {
        _transformPivot = Offset(reference.pivotX!, reference.pivotY!);
      } else {
        _transformPivot = bounds.center;
      }

      _isTransformPivotDragging = false;
    });

    HapticFeedback.mediumImpact();
  }

  void _flipReferenceTransformHorizontally() {
    final reference = _referenceTransformTarget;

    if (reference == null) {
      return;
    }

    final bounds = _referenceTransformBounds(reference);
    final pivot = _effectiveTransformPivot(bounds);

    final center = _referenceDisplayedCenter(reference);

    final mirroredCenter = Offset(pivot.dx - (center.dx - pivot.dx), center.dy);

    final newOffset = mirroredCenter - _referenceCanvasCenter;

    setState(() {
      _replaceReferenceTransform(
        reference.copyWith(
          offsetX: newOffset.dx,
          offsetY: newOffset.dy,
          scaleX: -reference.scaleX,
        ),
      );
    });

    _scheduleAutosave();
    HapticFeedback.lightImpact();
  }

  void _clearTransformSelection() {
    _lassoPoints = const <VectorPoint>[];
    _selectedTransformStrokes = <String, Set<int>>{};
    _transformReferenceLayerId = null;
    _referenceTransformSnapshot = null;
    _transformLastPosition = null;
    _transformScaleAnchor = null;
    _transformScaleStartDistance = null;
    _transformScaleSnapshot = null;
    _transformRotationCenter = null;
    _transformRotationStartAngle = null;
    _transformRotationSnapshot = null;
    _isTransformDragging = false;
    _isTransformScaling = false;
    _isTransformRotating = false;
  }

  bool _pointInsidePolygon(Offset point, List<VectorPoint> polygon) {
    if (polygon.length < 3) return false;

    var inside = false;

    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].dx;
      final yi = polygon[i].dy;
      final xj = polygon[j].dx;
      final yj = polygon[j].dy;

      final denominator = (yj - yi).abs() < 0.000001 ? 0.000001 : (yj - yi);

      final crosses =
          ((yi > point.dy) != (yj > point.dy)) &&
          (point.dx < (xj - xi) * (point.dy - yi) / denominator + xi);

      if (crosses) inside = !inside;
    }

    return inside;
  }

  List<int> _transformLayerIndices() {
    final group = _activeLayerGroup;

    if (group == null) {
      return <int>[_activeLayerIndex];
    }

    final indices = <int>[];

    for (var index = 0; index < _layers.length; index++) {
      if (group.childLayerIds.contains(_layers[index].id)) {
        indices.add(index);
      }
    }

    return indices;
  }

  int _layerIndexForId(String layerId) {
    return _layers.indexWhere((layer) => layer.id == layerId);
  }

  void _enterTransformForLayerIndices(
    List<int> layerIndices, {
    String? groupId,
  }) {
    final selected = <String, Set<int>>{};

    for (final layerIndex in layerIndices) {
      if (layerIndex < 0 || layerIndex >= _layers.length) {
        continue;
      }

      final layer = _layers[layerIndex];

      if (_selectedFrameIndex < 0 ||
          _selectedFrameIndex >= layer.frames.length) {
        continue;
      }

      final strokes = layer.frames[_selectedFrameIndex];

      if (strokes.isEmpty) {
        continue;
      }

      selected[layer.id] = Set<int>.from(
        List<int>.generate(strokes.length, (index) => index),
      );
    }

    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to transform on this frame')),
      );
      return;
    }

    setState(() {
      if (groupId != null) {
        _activeLayerGroupId = groupId;
      } else {
        _activeLayerGroupId = null;

        if (layerIndices.isNotEmpty) {
          _activeLayerIndex = layerIndices.first;
        }
      }

      _draftStroke = const <VectorPoint>[];
      _draftTextureStrokes = <VectorStroke>[];
      _draftStampStrokes = <VectorStroke>[];

      _clearFillLasso();
      _clearShapeDraft();
      _clearTransformSelection();

      _isEraserActive = false;
      _isFillToolActive = false;
      _isShapeToolActive = false;

      _stampBrushActive = false;
      _stampBrushItem = null;

      _isTransformActive = true;
      _transformToolbarExpanded = true;

      _transformPivot = null;
      _isTransformPivotDragging = false;

      _selectedTransformStrokes = selected;
    });

    HapticFeedback.mediumImpact();
  }

  void _enterLayerTransform(int layerIndex) {
    _enterTransformForLayerIndices(<int>[layerIndex]);
  }

  void _enterLayerGroupTransform(String groupId) {
    final groupIndex = _layerGroups.indexWhere((group) => group.id == groupId);

    if (groupIndex == -1) {
      return;
    }

    final group = _layerGroups[groupIndex];
    final layerIndices = <int>[];

    for (var index = 0; index < _layers.length; index++) {
      if (group.childLayerIds.contains(_layers[index].id)) {
        layerIndices.add(index);
      }
    }

    _enterTransformForLayerIndices(layerIndices, groupId: group.id);
  }

  void _finishLassoSelection() {
    if (_lassoPoints.length < 3) {
      _clearTransformSelection();
      return;
    }

    final selected = <String, Set<int>>{};

    for (final layerIndex in _transformLayerIndices()) {
      if (layerIndex < 0 || layerIndex >= _layers.length) {
        continue;
      }

      final layer = _layers[layerIndex];

      if (_selectedFrameIndex >= layer.frames.length) {
        continue;
      }

      final strokes = layer.frames[_selectedFrameIndex];
      final strokeIndices = <int>{};

      for (var strokeIndex = 0; strokeIndex < strokes.length; strokeIndex++) {
        final stroke = strokes[strokeIndex];

        if (stroke.points.any(
          (point) =>
              _pointInsidePolygon(Offset(point.dx, point.dy), _lassoPoints),
        )) {
          strokeIndices.add(strokeIndex);
        }
      }

      if (strokeIndices.isNotEmpty) {
        selected[layer.id] = strokeIndices;
      }
    }

    _selectedTransformStrokes = selected;
    _lassoPoints = const <VectorPoint>[];
  }

  Rect? _selectedStrokeBounds() {
    if (_selectedTransformStrokes.isEmpty) {
      return null;
    }

    double? minX;
    double? minY;
    double? maxX;
    double? maxY;

    for (final entry in _selectedTransformStrokes.entries) {
      final layerIndex = _layerIndexForId(entry.key);

      if (layerIndex == -1) continue;

      final layer = _layers[layerIndex];

      if (_selectedFrameIndex >= layer.frames.length) {
        continue;
      }

      final strokes = layer.frames[_selectedFrameIndex];

      for (final strokeIndex in entry.value) {
        if (strokeIndex < 0 || strokeIndex >= strokes.length) {
          continue;
        }

        for (final point in strokes[strokeIndex].points) {
          minX = minX == null ? point.dx : (point.dx < minX ? point.dx : minX);

          minY = minY == null ? point.dy : (point.dy < minY ? point.dy : minY);

          maxX = maxX == null ? point.dx : (point.dx > maxX ? point.dx : maxX);

          maxY = maxY == null ? point.dy : (point.dy > maxY ? point.dy : maxY);
        }
      }
    }

    if (minX == null || minY == null || maxX == null || maxY == null) {
      return null;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _moveSelectedStrokes(Offset delta) {
    if (_selectedTransformStrokes.isEmpty) {
      return;
    }

    for (final entry in _selectedTransformStrokes.entries) {
      final layerIndex = _layerIndexForId(entry.key);

      if (layerIndex == -1) continue;

      final layer = _layers[layerIndex];

      if (_selectedFrameIndex >= layer.frames.length) {
        continue;
      }

      final frames = _copyLayerFrames(layer.frames);
      final strokes = frames[_selectedFrameIndex];

      for (final strokeIndex in entry.value) {
        if (strokeIndex < 0 || strokeIndex >= strokes.length) {
          continue;
        }

        final stroke = strokes[strokeIndex];

        strokes[strokeIndex] = VectorStroke(
          points: stroke.points
              .map(
                (point) => VectorPoint(
                  dx: point.dx + delta.dx,
                  dy: point.dy + delta.dy,
                  pressure: point.pressure,
                ),
              )
              .toList(),
          strokeWidth: stroke.strokeWidth,
          color: stroke.color,
          filled: stroke.filled,
          brushType: stroke.brushType,
        );
      }

      _layers[layerIndex] = layer.copyWith(frames: frames);
    }

    _rebuildCompositeFrames();
  }

  void _flipSelectedStrokesHorizontally() {
    if (_transformReferenceLayerId != null) {
      _flipReferenceTransformHorizontally();
      return;
    }

    if (_selectedTransformStrokes.isEmpty) {
      return;
    }

    final bounds = _selectedStrokeBounds();

    if (bounds == null) {
      return;
    }

    if (_activeLayerGroup == null) {
      _saveUndoState();
    } else {
      _saveGroupUndoState();
    }

    final pivot = _effectiveTransformPivot(bounds);
    final mirrorX = pivot.dx;

    setState(() {
      for (final entry in _selectedTransformStrokes.entries) {
        final layerIndex = _layerIndexForId(entry.key);

        if (layerIndex == -1) {
          continue;
        }

        final layer = _layers[layerIndex];

        if (_selectedFrameIndex < 0 ||
            _selectedFrameIndex >= layer.frames.length) {
          continue;
        }

        final frames = _copyLayerFrames(layer.frames);
        final strokes = frames[_selectedFrameIndex];

        for (final strokeIndex in entry.value) {
          if (strokeIndex < 0 || strokeIndex >= strokes.length) {
            continue;
          }

          final source = strokes[strokeIndex];

          strokes[strokeIndex] = VectorStroke(
            points: source.points
                .map(
                  (point) => VectorPoint(
                    dx: mirrorX - (point.dx - mirrorX),
                    dy: point.dy,
                    pressure: point.pressure,
                  ),
                )
                .toList(),
            strokeWidth: source.strokeWidth,
            color: source.color,
            filled: source.filled,
            brushType: source.brushType,
          );
        }

        _layers[layerIndex] = layer.copyWith(frames: frames);
      }

      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
    HapticFeedback.lightImpact();
  }

  Offset _transformRotationHandle(Rect bounds) {
    return bounds.topCenter + const Offset(0, -34);
  }

  bool _transformRotationHandleHit(Offset position, Rect bounds) {
    const hitRadius = 24.0;

    return (position - _transformRotationHandle(bounds)).distance <= hitRadius;
  }

  Offset _effectiveTransformPivot(Rect bounds) {
    return _transformPivot ?? bounds.center;
  }

  bool _transformPivotHit(Offset position, Rect bounds) {
    const hitRadius = 24.0;

    return (position - _effectiveTransformPivot(bounds)).distance <= hitRadius;
  }

  double _angleFromCenter(Offset point, Offset center) {
    return math.atan2(point.dy - center.dy, point.dx - center.dx);
  }

  void _rotateSelectedStrokes(
    double angle,
    Offset center,
    Map<String, List<VectorStroke>> snapshot,
  ) {
    if (_selectedTransformStrokes.isEmpty) return;

    final cosAngle = math.cos(angle);
    final sinAngle = math.sin(angle);

    for (final entry in _selectedTransformStrokes.entries) {
      final layerIndex = _layerIndexForId(entry.key);

      if (layerIndex == -1) continue;

      final sourceStrokes = snapshot[entry.key];

      if (sourceStrokes == null) continue;

      final layer = _layers[layerIndex];

      if (_selectedFrameIndex >= layer.frames.length) {
        continue;
      }

      final frames = _copyLayerFrames(layer.frames);
      final strokes = frames[_selectedFrameIndex];

      for (final strokeIndex in entry.value) {
        if (strokeIndex < 0 ||
            strokeIndex >= strokes.length ||
            strokeIndex >= sourceStrokes.length) {
          continue;
        }

        final source = sourceStrokes[strokeIndex];

        strokes[strokeIndex] = VectorStroke(
          points: source.points.map((point) {
            final x = point.dx - center.dx;
            final y = point.dy - center.dy;

            return VectorPoint(
              dx: center.dx + (x * cosAngle) - (y * sinAngle),
              dy: center.dy + (x * sinAngle) + (y * cosAngle),
              pressure: point.pressure,
            );
          }).toList(),
          strokeWidth: source.strokeWidth,
          color: source.color,
          filled: source.filled,
          brushType: source.brushType,
        );
      }

      _layers[layerIndex] = layer.copyWith(frames: frames);
    }

    _rebuildCompositeFrames();
  }

  Offset? _transformCornerHit(Offset position, Rect bounds) {
    const hitRadius = 22.0;

    for (final corner in <Offset>[
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight,
    ]) {
      if ((position - corner).distance <= hitRadius) {
        return corner;
      }
    }

    return null;
  }

  Offset _oppositeTransformCorner(Offset corner, Rect bounds) {
    if (corner == bounds.topLeft) {
      return bounds.bottomRight;
    }

    if (corner == bounds.topRight) {
      return bounds.bottomLeft;
    }

    if (corner == bounds.bottomLeft) {
      return bounds.topRight;
    }

    return bounds.topLeft;
  }

  Offset? _transformEdgeHandleHit(Offset position, Rect bounds) {
    const hitRadius = 22.0;

    for (final handle in <Offset>[
      bounds.centerLeft,
      bounds.centerRight,
      bounds.topCenter,
      bounds.bottomCenter,
    ]) {
      if ((position - handle).distance <= hitRadius) {
        return handle;
      }
    }

    return null;
  }

  bool _transformHandleIsHorizontal(Offset handle, Rect bounds) {
    return handle == bounds.centerLeft || handle == bounds.centerRight;
  }

  Offset _oppositeTransformEdge(Offset handle, Rect bounds) {
    if (handle == bounds.centerLeft) {
      return bounds.centerRight;
    }

    if (handle == bounds.centerRight) {
      return bounds.centerLeft;
    }

    if (handle == bounds.topCenter) {
      return bounds.bottomCenter;
    }

    return bounds.topCenter;
  }

  void _copySelectedStrokes() {
    if (_selectedTransformStrokes.isEmpty) return;

    final copied = <String, List<VectorStroke>>{};

    for (final entry in _selectedTransformStrokes.entries) {
      final layerIndex = _layerIndexForId(entry.key);

      if (layerIndex == -1) continue;

      final layer = _layers[layerIndex];

      if (_selectedFrameIndex < 0 ||
          _selectedFrameIndex >= layer.frames.length) {
        continue;
      }

      final sourceStrokes = layer.frames[_selectedFrameIndex];
      final selected = <VectorStroke>[];

      final sortedIndices = entry.value.toList()..sort();

      for (final strokeIndex in sortedIndices) {
        if (strokeIndex < 0 || strokeIndex >= sourceStrokes.length) {
          continue;
        }

        selected.add(sourceStrokes[strokeIndex].copy());
      }

      if (selected.isNotEmpty) {
        copied[layer.id] = selected;
      }
    }

    if (copied.isEmpty) return;

    setState(() {
      _strokeClipboard
        ..clear()
        ..addAll(copied);
    });
  }

  void _pasteCopiedStrokes() {
    if (_strokeClipboard.isEmpty || _frames.isEmpty) return;

    // Save undo before modifying the destination frame.
    if (_activeLayerGroup != null) {
      _saveGroupUndoState();
    } else {
      _saveUndoState();
    }

    const pasteOffset = Offset(18, 18);
    final pastedSelection = <String, Set<int>>{};

    for (final clipboardEntry in _strokeClipboard.entries) {
      var layerIndex = _layerIndexForId(clipboardEntry.key);

      // If the original source layer no longer exists, paste into
      // the currently active drawing layer instead.
      if (layerIndex == -1) {
        layerIndex = _activeLayerIndex;
      }

      if (layerIndex < 0 || layerIndex >= _layers.length) {
        continue;
      }

      final layer = _layers[layerIndex];

      if (_selectedFrameIndex < 0 ||
          _selectedFrameIndex >= layer.frames.length) {
        continue;
      }

      final frames = _copyLayerFrames(layer.frames);
      final destination = frames[_selectedFrameIndex];
      final firstPastedIndex = destination.length;

      for (final source in clipboardEntry.value) {
        destination.add(
          VectorStroke(
            points: source.points
                .map(
                  (point) => VectorPoint(
                    dx: point.dx + pasteOffset.dx,
                    dy: point.dy + pasteOffset.dy,
                    pressure: point.pressure,
                  ),
                )
                .toList(),
            strokeWidth: source.strokeWidth,
            color: source.color,
            filled: source.filled,
            brushType: source.brushType,
          ),
        );
      }

      final layerId = layer.id;

      pastedSelection[layerId] = {
        for (var index = firstPastedIndex; index < destination.length; index++)
          index,
      };

      _layers[layerIndex] = layer.copyWith(frames: frames);
    }

    if (pastedSelection.isEmpty) return;

    setState(() {
      _isTransformActive = true;
      _isEraserActive = false;
      _isFillToolActive = false;
      _isShapeToolActive = false;

      _draftStroke = const <VectorPoint>[];
      _draftStampStrokes = <VectorStroke>[];
      _stampBrushLastPosition = null;
      _clearFillLasso();
      _clearShapeDraft();

      _selectedTransformStrokes = pastedSelection;
      _lassoPoints = const <VectorPoint>[];

      _isTransformDragging = false;
      _isTransformScaling = false;
      _isTransformRotating = false;
      _transformLastPosition = null;
    });

    _rebuildCompositeFrames();
    _scheduleAutosave();
  }

  Map<String, List<VectorStroke>> _selectedTransformSnapshot() {
    final snapshot = <String, List<VectorStroke>>{};

    for (final entry in _selectedTransformStrokes.entries) {
      final layerIndex = _layerIndexForId(entry.key);

      if (layerIndex == -1) continue;

      final layer = _layers[layerIndex];

      if (_selectedFrameIndex >= layer.frames.length) {
        continue;
      }

      snapshot[layer.id] = layer.frames[_selectedFrameIndex]
          .map((stroke) => stroke.copy())
          .toList();
    }

    return snapshot;
  }

  void _scaleSelectedStrokes(
    double scaleX,
    double scaleY,
    Offset anchor,
    Map<String, List<VectorStroke>> snapshot,
  ) {
    if (_selectedTransformStrokes.isEmpty) return;

    final safeScaleX = scaleX.clamp(0.05, 20.0);
    final safeScaleY = scaleY.clamp(0.05, 20.0);

    final nonUniformScale =
        _transformScaleHorizontalOnly || _transformScaleVerticalOnly;

    for (final entry in _selectedTransformStrokes.entries) {
      final layerIndex = _layerIndexForId(entry.key);

      if (layerIndex == -1) continue;

      final sourceStrokes = snapshot[entry.key];

      if (sourceStrokes == null) continue;

      final layer = _layers[layerIndex];
      final frames = _copyLayerFrames(layer.frames);
      final strokes = frames[_selectedFrameIndex];

      for (final strokeIndex in entry.value) {
        if (strokeIndex < 0 ||
            strokeIndex >= strokes.length ||
            strokeIndex >= sourceStrokes.length) {
          continue;
        }

        final source = sourceStrokes[strokeIndex];

        strokes[strokeIndex] = VectorStroke(
          points: source.points
              .map(
                (point) => VectorPoint(
                  dx: anchor.dx + ((point.dx - anchor.dx) * safeScaleX),
                  dy: anchor.dy + ((point.dy - anchor.dy) * safeScaleY),
                  pressure: point.pressure,
                ),
              )
              .toList(),
          strokeWidth: source.filled || nonUniformScale
              ? source.strokeWidth
              : (source.strokeWidth * safeScaleX).clamp(0.25, 500.0),
          color: source.color,
          filled: source.filled,
          brushType: source.brushType,
        );
      }

      _layers[layerIndex] = layer.copyWith(frames: frames);
    }

    _rebuildCompositeFrames();
  }

  void _clearFillLasso() {
    _fillLassoPoints = const <VectorPoint>[];
    _fillStabilizerTrailingPosition = null;
  }

  void _commitFillLasso() {
    if (_fillLassoPoints.length < 3) {
      _clearFillLasso();
      return;
    }

    _saveUndoState();

    final layer = _activeLayer;
    final frames = _copyLayerFrames(layer.frames);

    final fillStroke = VectorStroke(
      points: List<VectorPoint>.from(_fillLassoPoints),
      strokeWidth: 0,
      color: _brushColor.withValues(alpha: _brushOpacity),
      filled: true,
      brushType: StrokeBrushType.solid,
    );

    frames[_selectedFrameIndex] = <VectorStroke>[
      ...frames[_selectedFrameIndex],
      fillStroke,
    ];

    _layers[_activeLayerIndex] = layer.copyWith(frames: frames);

    _clearFillLasso();
    _rebuildCompositeFrames();
  }

  List<VectorStroke> _shapeStrokes(Offset start, Offset end) {
    VectorPoint point(Offset offset) {
      return VectorPoint(dx: offset.dx, dy: offset.dy, pressure: 1);
    }

    VectorStroke outlineStroke(List<Offset> points) {
      return VectorStroke(
        points: points.map(point).toList(),
        strokeWidth: _brushSize,
        color: Colors.black,
        filled: false,
        brushType: StrokeBrushType.solid,
      );
    }

    VectorStroke fillStroke(List<Offset> points) {
      return VectorStroke(
        points: points.map(point).toList(),
        strokeWidth: 0,
        color: _brushColor.withValues(alpha: _brushOpacity),
        filled: true,
        brushType: StrokeBrushType.solid,
      );
    }

    List<VectorStroke> rectangleStrokes(Rect rect, {required bool filled}) {
      // The outline is centred on the requested shape boundary.
      // Keep the colour inside the inner half of that black line so the
      // linework acts as the visible boundary of the filled shape.
      final fillInset = math.max(1.0, _brushSize / 2);

      final canInset =
          rect.width > (fillInset * 2) && rect.height > (fillInset * 2);

      final fillRect = canInset ? rect.deflate(fillInset) : rect;

      final fillCorners = <Offset>[
        fillRect.topLeft,
        fillRect.topRight,
        fillRect.bottomRight,
        fillRect.bottomLeft,
      ];

      return <VectorStroke>[
        if (filled) fillStroke(fillCorners),
        outlineStroke(<Offset>[rect.topLeft, rect.topRight]),
        outlineStroke(<Offset>[rect.topRight, rect.bottomRight]),
        outlineStroke(<Offset>[rect.bottomRight, rect.bottomLeft]),
        outlineStroke(<Offset>[rect.bottomLeft, rect.topLeft]),
      ];
    }

    List<Offset> ellipsePoints(Rect rect) {
      final center = rect.center;
      final radiusX = rect.width / 2;
      final radiusY = rect.height / 2;

      if (radiusX < 0.5 || radiusY < 0.5) {
        return const <Offset>[];
      }

      const segments = 64;
      final points = <Offset>[];

      for (var i = 0; i <= segments; i++) {
        final angle = (i / segments) * math.pi * 2;

        points.add(
          Offset(
            center.dx + math.cos(angle) * radiusX,
            center.dy + math.sin(angle) * radiusY,
          ),
        );
      }

      return points;
    }

    switch (_shapeToolType) {
      case _ShapeToolType.line:
        return <VectorStroke>[
          outlineStroke(<Offset>[start, end]),
        ];

      case _ShapeToolType.rectangle:
        return rectangleStrokes(Rect.fromPoints(start, end), filled: false);

      case _ShapeToolType.filledRectangle:
        return rectangleStrokes(Rect.fromPoints(start, end), filled: true);

      case _ShapeToolType.perspectiveRectangle:
        final rect = Rect.fromPoints(start, end);

        return _perspectiveRectangleStrokes(<Offset>[
          rect.topLeft,
          rect.topRight,
          rect.bottomRight,
          rect.bottomLeft,
        ]);

      case _ShapeToolType.square:
      case _ShapeToolType.filledSquare:
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;

        final side = math.max(dx.abs(), dy.abs());

        final squareEnd = Offset(
          start.dx + (dx < 0 ? -side : side),
          start.dy + (dy < 0 ? -side : side),
        );

        return rectangleStrokes(
          Rect.fromPoints(start, squareEnd),
          filled: _shapeToolType == _ShapeToolType.filledSquare,
        );

      case _ShapeToolType.circle:
      case _ShapeToolType.filledCircle:
        final points = ellipsePoints(Rect.fromPoints(start, end));

        if (points.isEmpty) {
          return const <VectorStroke>[];
        }

        final circleRect = Rect.fromPoints(start, end);
        final fillInset = math.max(1.0, _brushSize / 2);

        final canInset =
            circleRect.width > (fillInset * 2) &&
            circleRect.height > (fillInset * 2);

        final fillPoints = ellipsePoints(
          canInset ? circleRect.deflate(fillInset) : circleRect,
        );

        return <VectorStroke>[
          if (_shapeToolType == _ShapeToolType.filledCircle)
            fillStroke(fillPoints),
          outlineStroke(points),
        ];
    }
  }

  List<VectorStroke> _perspectiveRectangleStrokes(List<Offset> corners) {
    if (corners.length != 4) {
      return const <VectorStroke>[];
    }

    VectorPoint point(Offset offset) {
      return VectorPoint(dx: offset.dx, dy: offset.dy, pressure: 1);
    }

    VectorStroke edge(Offset start, Offset end) {
      return VectorStroke(
        points: <VectorPoint>[point(start), point(end)],
        strokeWidth: _brushSize,
        color: Colors.black,
        filled: false,
        brushType: StrokeBrushType.solid,
      );
    }

    final center = Offset(
      corners.fold<double>(0, (sum, corner) => sum + corner.dx) / 4,
      corners.fold<double>(0, (sum, corner) => sum + corner.dy) / 4,
    );

    final fillInset = math.max(1.0, _brushSize / 2);

    final fillCorners = corners.map((corner) {
      final direction = center - corner;
      final distance = direction.distance;

      if (distance <= 0.001 || distance <= fillInset) {
        return corner;
      }

      return corner + ((direction / distance) * fillInset);
    }).toList();

    return <VectorStroke>[
      VectorStroke(
        points: fillCorners.map(point).toList(),
        strokeWidth: 0,
        color: _brushColor.withValues(alpha: _brushOpacity),
        filled: true,
        brushType: StrokeBrushType.solid,
      ),
      edge(corners[0], corners[1]),
      edge(corners[1], corners[2]),
      edge(corners[2], corners[3]),
      edge(corners[3], corners[0]),
    ];
  }

  Future<void> _capturePerspectiveLoupe(
    Offset canvasPosition,
    Offset globalPosition,
  ) async {
    final renderObject = _canvasSampleKey.currentContext?.findRenderObject();

    final stackObject = _workspaceStackKey.currentContext?.findRenderObject();

    if (renderObject is! RenderRepaintBoundary || stackObject is! RenderBox) {
      return;
    }

    try {
      final image = await renderObject.toImage(pixelRatio: 1);

      if (!mounted || _perspectiveDraggingCorner == null) {
        image.dispose();
        return;
      }

      final localScreenPosition = stackObject.globalToLocal(globalPosition);

      setState(() {
        _perspectiveLoupeImage?.dispose();

        _perspectiveLoupeImage = image;
        _perspectiveLoupeCanvasPosition = canvasPosition;
        _perspectiveLoupeScreenPosition = localScreenPosition;
      });
    } catch (_) {
      // Corner editing must continue even if the
      // optional Precision Loupe cannot be captured.
    }
  }

  void _updatePerspectiveLoupe(Offset canvasPosition, Offset globalPosition) {
    final stackObject = _workspaceStackKey.currentContext?.findRenderObject();

    if (stackObject is! RenderBox) {
      return;
    }

    _perspectiveLoupeCanvasPosition = canvasPosition;

    _perspectiveLoupeScreenPosition = stackObject.globalToLocal(globalPosition);
  }

  void _clearPerspectiveLoupe() {
    _perspectiveLoupeImage?.dispose();
    _perspectiveLoupeImage = null;
    _perspectiveLoupeCanvasPosition = null;
    _perspectiveLoupeScreenPosition = null;
  }

  int? _perspectiveCornerHit(Offset position) {
    if (!_perspectiveShapeEditing || _perspectiveShapeCorners.length != 4) {
      return null;
    }

    final currentScale = _transformationController.value.getMaxScaleOnAxis();

    // Roughly constant finger-friendly hit size regardless of canvas zoom.
    final hitRadius = 24.0 / math.max(0.1, currentScale);

    for (var index = 0; index < _perspectiveShapeCorners.length; index++) {
      if ((position - _perspectiveShapeCorners[index]).distance <= hitRadius) {
        return index;
      }
    }

    return null;
  }

  void _updatePerspectiveCorner(int index, Offset position) {
    if (index < 0 || index >= _perspectiveShapeCorners.length) {
      return;
    }

    final corners = List<Offset>.from(_perspectiveShapeCorners);

    corners[index] = position;

    _perspectiveShapeCorners = corners;
    _draftShapeStrokes = _perspectiveRectangleStrokes(corners);
  }

  void _updateShapePreview(Offset position) {
    final start = _shapeStartPosition;

    if (start == null) return;

    if (_shapeToolType == _ShapeToolType.perspectiveRectangle) {
      final rect = Rect.fromPoints(start, position);

      _perspectiveShapeCorners = <Offset>[
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ];

      _draftShapeStrokes = _perspectiveRectangleStrokes(
        _perspectiveShapeCorners,
      );

      return;
    }

    _draftShapeStrokes = _shapeStrokes(start, position);
  }

  void _clearShapeDraft() {
    _shapeStartPosition = null;
    _draftShapeStrokes = const <VectorStroke>[];

    _perspectiveShapeEditing = false;
    _perspectiveShapeCorners = const <Offset>[];
    _perspectiveDraggingCorner = null;
  }

  void _confirmPerspectiveShape() {
    if (!_perspectiveShapeEditing || _draftShapeStrokes.isEmpty) {
      return;
    }

    setState(() {
      _commitShape();
    });

    _scheduleAutosave();
  }

  void _cancelPerspectiveShape() {
    setState(() {
      _clearShapeDraft();
    });
  }

  void _commitShape() {
    if (_draftShapeStrokes.isEmpty) {
      _clearShapeDraft();
      return;
    }

    _saveUndoState();

    final layer = _activeLayer;
    final frames = _copyLayerFrames(layer.frames);

    frames[_selectedFrameIndex] = <VectorStroke>[
      ...frames[_selectedFrameIndex],
      ..._draftShapeStrokes.map((stroke) => stroke.copy()),
    ];

    _layers[_activeLayerIndex] = layer.copyWith(frames: frames);

    _clearShapeDraft();
    _rebuildCompositeFrames();
  }

  double _distanceSquaredToSegment(Offset point, Offset start, Offset end) {
    final segmentDx = end.dx - start.dx;
    final segmentDy = end.dy - start.dy;
    final segmentLengthSquared =
        (segmentDx * segmentDx) + (segmentDy * segmentDy);

    if (segmentLengthSquared == 0) {
      final dx = point.dx - start.dx;
      final dy = point.dy - start.dy;
      return (dx * dx) + (dy * dy);
    }

    final projection =
        (((point.dx - start.dx) * segmentDx) +
            ((point.dy - start.dy) * segmentDy)) /
        segmentLengthSquared;

    final t = projection.clamp(0.0, 1.0);

    final closestX = start.dx + (segmentDx * t);
    final closestY = start.dy + (segmentDy * t);

    final dx = point.dx - closestX;
    final dy = point.dy - closestY;

    return (dx * dx) + (dy * dy);
  }

  void _eraseAt(Offset position) {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();

    final updatedStrokes = <VectorStroke>[];

    for (final stroke in _activeLayer.frames[_selectedFrameIndex]) {
      if (stroke.points.isEmpty) {
        continue;
      }

      final eraserRadius = (10 + (stroke.strokeWidth / 2)) / currentScale;

      final eraserRadiusSquared = eraserRadius * eraserRadius;

      var currentChunk = <VectorPoint>[];

      void saveCurrentChunk() {
        if (currentChunk.isEmpty) return;

        updatedStrokes.add(
          VectorStroke(
            points: currentChunk,
            strokeWidth: stroke.strokeWidth,
            color: stroke.color,
            filled: stroke.filled,
            brushType: stroke.brushType,
          ),
        );

        currentChunk = <VectorPoint>[];
      }

      if (stroke.points.length == 1) {
        final point = stroke.points.first;
        final dx = point.dx - position.dx;
        final dy = point.dy - position.dy;

        if ((dx * dx) + (dy * dy) > eraserRadiusSquared) {
          updatedStrokes.add(stroke);
        }

        continue;
      }

      currentChunk.add(stroke.points.first);

      for (var i = 1; i < stroke.points.length; i++) {
        final previous = stroke.points[i - 1];
        final current = stroke.points[i];

        final segmentDistanceSquared = _distanceSquaredToSegment(
          position,
          Offset(previous.dx, previous.dy),
          Offset(current.dx, current.dy),
        );

        if (segmentDistanceSquared <= eraserRadiusSquared) {
          saveCurrentChunk();
        } else {
          currentChunk.add(current);
        }
      }

      saveCurrentChunk();
    }

    final layer = _activeLayer;
    final frames = _copyLayerFrames(layer.frames);

    frames[_selectedFrameIndex] = updatedStrokes;

    _layers[_activeLayerIndex] = layer.copyWith(frames: frames);

    _rebuildCompositeFrames();
  }

  Offset _stabilizeFillPosition(Offset rawPosition) {
    if (_stabilizerStrength <= 0 || _fillLassoPoints.isEmpty) {
      _fillStabilizerTrailingPosition = rawPosition;
      return rawPosition;
    }

    final previous =
        _fillStabilizerTrailingPosition ??
        Offset(_fillLassoPoints.last.dx, _fillLassoPoints.last.dy);

    final delta = rawPosition - previous;
    final distance = delta.distance;

    if (distance <= 0.001) {
      return previous;
    }

    final pullDistance = _stabilizerPullDistance.clamp(0.0, 120.0);

    final allowedDistance = math.max(0.0, distance - pullDistance);

    final target = allowedDistance <= 0
        ? previous
        : previous + (delta / distance) * allowedDistance;

    final response = (1.0 - _stabilizerStrength).clamp(0.08, 1.0);

    final stabilized = Offset(
      previous.dx + ((target.dx - previous.dx) * response),
      previous.dy + ((target.dy - previous.dy) * response),
    );

    _fillStabilizerTrailingPosition = stabilized;
    return stabilized;
  }

  Offset _stabilizePosition(Offset rawPosition) {
    if (_stabilizerStrength <= 0 || _draftStroke.isEmpty) {
      _stabilizerTrailingPosition = rawPosition;
      return rawPosition;
    }

    final previous =
        _stabilizerTrailingPosition ??
        Offset(_draftStroke.last.dx, _draftStroke.last.dy);

    final delta = rawPosition - previous;
    final distance = delta.distance;

    if (distance <= 0.001) {
      return previous;
    }

    final pullDistance = _stabilizerPullDistance.clamp(0.0, 120.0);

    // Hold the rendered point slightly behind the real pen tip.
    final allowedDistance = math.max(0.0, distance - pullDistance);

    final target = allowedDistance <= 0
        ? previous
        : previous + (delta / distance) * allowedDistance;

    // Blend toward the pulled target.
    final response = (1.0 - _stabilizerStrength).clamp(0.08, 1.0);

    final stabilized = Offset(
      previous.dx + ((target.dx - previous.dx) * response),
      previous.dy + ((target.dy - previous.dy) * response),
    );

    _stabilizerTrailingPosition = stabilized;
    return stabilized;
  }

  Color _currentBlendColor() {
    return Color.lerp(_blendBaseColor, _blendSampleColor, _blendAmount) ??
        _blendBaseColor;
  }

  void _applyCurrentBlend() {
    final mixedColor = _currentBlendColor();

    _brushColor = mixedColor;
    _rememberRecentColor(mixedColor);
  }

  Future<void> _sampleBlendColour(Offset canvasPosition) async {
    final boundary =
        _canvasSampleKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;

    if (boundary == null) {
      return;
    }

    try {
      final image = await boundary.toImage(pixelRatio: 1.0);

      try {
        final x = canvasPosition.dx.round().clamp(0, image.width - 1);

        final y = canvasPosition.dy.round().clamp(0, image.height - 1);

        final byteData = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );

        if (byteData == null || !mounted) {
          return;
        }

        final offset = ((y * image.width) + x) * 4;

        final r = byteData.getUint8(offset);
        final g = byteData.getUint8(offset + 1);
        final b = byteData.getUint8(offset + 2);
        final a = byteData.getUint8(offset + 3);

        final sampled = Color.fromARGB(a, r, g, b);

        setState(() {
          _blendSampleColor = sampled;
          _blendSamplingArmed = false;
          _applyCurrentBlend();
        });
      } finally {
        image.dispose();
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _blendSamplingArmed = false;
      });
    }
  }

  List<VectorStroke> _bagStampSourceStrokes(BagItem item) {
    final strokes = <VectorStroke>[];

    for (final layer in item.layers) {
      if (!layer.visible) {
        continue;
      }

      for (final stroke in layer.strokes) {
        strokes.add(_strokeWithOpacity(stroke, layer.opacity));
      }
    }

    return strokes;
  }

  Rect? _bagStampBounds(List<VectorStroke> strokes) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var foundPoint = false;

    for (final stroke in strokes) {
      for (final point in stroke.points) {
        foundPoint = true;

        minX = math.min(minX, point.dx);
        minY = math.min(minY, point.dy);
        maxX = math.max(maxX, point.dx);
        maxY = math.max(maxY, point.dy);
      }
    }

    if (!foundPoint) {
      return null;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  List<VectorStroke> _buildBagStamp(
    BagItem item,
    Offset position,
    double pressure,
  ) {
    final sourceStrokes = _bagStampSourceStrokes(item);
    final bounds = _bagStampBounds(sourceStrokes);

    if (bounds == null) {
      return const <VectorStroke>[];
    }

    final sourceCenter = bounds.center;

    final normalizedPressure = pressure.clamp(0.0, 1.0);

    // Keep very light contact visible while allowing full pressure
    // to reach the Scale slider's selected size.
    final pressureScale = 0.25 + (normalizedPressure * 0.75);
    final effectiveScale = _stampBrushScale * pressureScale;

    // Each copy gets one coherent random rotation.
    final randomRotation =
        ((_stampBrushRandom.nextDouble() * 2.0) - 1.0) *
        _stampBrushRandomRotation;

    final rotationDegrees = _stampBrushRotation + randomRotation;
    final rotationRadians = rotationDegrees * math.pi / 180.0;

    final cosRotation = math.cos(rotationRadians);
    final sinRotation = math.sin(rotationRadians);

    // Scatter moves the entire asset away from the exact pointer path.
    var stampCenter = position;

    if (_stampBrushScatter > 0) {
      final scatterAngle = _stampBrushRandom.nextDouble() * math.pi * 2.0;

      final scatterRadius =
          math.sqrt(_stampBrushRandom.nextDouble()) * _stampBrushScatter;

      stampCenter += Offset(
        math.cos(scatterAngle) * scatterRadius,
        math.sin(scatterAngle) * scatterRadius,
      );
    }

    return sourceStrokes.map((stroke) {
      return VectorStroke(
        points: stroke.points.map((point) {
          final sourceOffset = Offset(
            point.dx - sourceCenter.dx,
            point.dy - sourceCenter.dy,
          );

          final scaledX = sourceOffset.dx * effectiveScale;
          final scaledY = sourceOffset.dy * effectiveScale;

          final rotatedOffset = Offset(
            (scaledX * cosRotation) - (scaledY * sinRotation),
            (scaledX * sinRotation) + (scaledY * cosRotation),
          );

          final transformed = stampCenter + rotatedOffset;

          return VectorPoint(
            dx: transformed.dx,
            dy: transformed.dy,
            pressure: point.pressure,
          );
        }).toList(),
        strokeWidth: stroke.strokeWidth * effectiveScale,
        color: stroke.color,
        filled: stroke.filled,
        brushType: stroke.brushType,
      );
    }).toList();
  }

  void _addBagStampToDraft(Offset position, double pressure) {
    final item = _stampBrushItem;

    if (!_stampBrushActive || item == null) {
      return;
    }

    final stampedStrokes = _buildBagStamp(item, position, pressure);

    if (stampedStrokes.isEmpty) {
      return;
    }

    _draftStampStrokes.addAll(stampedStrokes);
  }

  void _addBagStampsAlongPath(Offset position, double pressure) {
    final lastPosition = _stampBrushLastPosition;

    if (lastPosition == null) {
      _stampBrushLastPosition = position;
      _addBagStampToDraft(position, pressure);
      return;
    }

    final delta = position - lastPosition;
    final distance = delta.distance;

    if (distance < _stampBrushSpacing) {
      return;
    }

    final direction = delta / distance;
    final stampCount = (distance / _stampBrushSpacing).floor();

    for (var index = 1; index <= stampCount; index++) {
      final stampPosition =
          lastPosition + direction * (_stampBrushSpacing * index);

      _addBagStampToDraft(stampPosition, pressure);
    }

    _stampBrushLastPosition =
        lastPosition + direction * (_stampBrushSpacing * stampCount);
  }

  void _commitStampBrushStroke() {
    if (_draftStampStrokes.isEmpty) {
      _stampBrushLastPosition = null;
      return;
    }

    _saveUndoState();

    setState(() {
      final layer = _activeLayer;
      final frames = _copyLayerFrames(layer.frames);

      frames[_selectedFrameIndex] = <VectorStroke>[
        ...frames[_selectedFrameIndex],
        ..._draftStampStrokes,
      ];

      _layers[_activeLayerIndex] = layer.copyWith(frames: frames);

      _draftStampStrokes = <VectorStroke>[];
      _stampBrushLastPosition = null;

      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
  }

  void _activateStampBrush(BagItem item) {
    final sourceStrokes = _bagStampSourceStrokes(item);

    if (sourceStrokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This Bag item has no visible strokes to stamp.'),
        ),
      );

      return;
    }

    setState(() {
      _drawingMode = true;

      _stampBrushItem = item;
      _stampBrushActive = true;
      _stampBrushPanelExpanded = true;

      _textureActive = false;
      _textureExpanded = false;
      _draftTextureStrokes = <VectorStroke>[];

      _blendSamplingArmed = false;

      _isEraserActive = false;
      _isFillToolActive = false;
      _isShapeToolActive = false;
      _isTransformActive = false;
      _transformToolbarExpanded = false;

      _activeLayerGroupId = null;

      _draftStroke = const <VectorPoint>[];

      _clearFillLasso();
      _clearShapeDraft();
      _clearTransformSelection();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.name} loaded as Stamp Brush 🖌️')),
    );
  }

  Future<void> _openStampBrushPicker() async {
    final items = await BagService().loadItems();

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.content_copy),
              SizedBox(width: 10),
              Text('Stamp Brush'),
            ],
          ),
          content: SizedBox(
            width: 420,
            height: 420,
            child: items.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.backpack_outlined,
                          size: 48,
                          color: Colors.white38,
                        ),
                        SizedBox(height: 12),
                        Text('Your Bag is empty.'),
                        SizedBox(height: 6),
                        Text(
                          'Save some artwork to the Bag first.',
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];

                      final strokeCount = item.layers.fold<int>(
                        0,
                        (total, layer) => total + layer.strokes.length,
                      );

                      final selected =
                          _stampBrushActive && _stampBrushItem?.id == item.id;

                      return ListTile(
                        selected: selected,
                        leading: Icon(
                          Icons.content_copy,
                          color: selected
                              ? Colors.deepPurpleAccent
                              : Colors.white70,
                        ),
                        title: Text(item.name),
                        subtitle: Text(
                          '${item.layers.length} layers · '
                          '$strokeCount strokes',
                        ),
                        trailing: selected
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.deepPurpleAccent,
                              )
                            : const Icon(Icons.touch_app_outlined),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _activateStampBrush(item);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            if (_stampBrushActive)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);

                  setState(() {
                    _stampBrushActive = false;
                    _stampBrushItem = null;
                  });
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Return to Pen'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sampleBrushColour(Offset canvasPosition) async {
    final boundary =
        _canvasSampleKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;

    if (boundary == null) {
      return;
    }

    try {
      final image = await boundary.toImage(pixelRatio: 1.0);

      try {
        final x = canvasPosition.dx.round().clamp(0, image.width - 1);
        final y = canvasPosition.dy.round().clamp(0, image.height - 1);

        final byteData = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );

        if (byteData == null || !mounted) {
          return;
        }

        final offset = ((y * image.width) + x) * 4;

        final sampled = Color.fromARGB(
          byteData.getUint8(offset + 3),
          byteData.getUint8(offset),
          byteData.getUint8(offset + 1),
          byteData.getUint8(offset + 2),
        );

        setState(() {
          _brushColor = sampled;
          _brushEyedropperArmed = false;
          _rememberRecentColor(sampled);
        });
      } finally {
        image.dispose();
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _brushEyedropperArmed = false;
      });
    }
  }

  void _addTextureStamp(Offset position, double pressure) {
    final count = (1 + (_textureDensity * 7)).round().clamp(1, 8);

    final generated = <VectorStroke>[];

    for (var i = 0; i < count; i++) {
      final angle = _textureRandom.nextDouble() * math.pi * 2;

      final radius = _textureRandom.nextDouble() * _textureScatter;

      final center = Offset(
        position.dx + math.cos(angle) * radius,
        position.dy + math.sin(angle) * radius,
      );

      final size = _textureScale * (0.65 + (_textureRandom.nextDouble() * 0.7));

      switch (_texturePattern) {
        case 'hatch':
          final hatchAngle =
              (-math.pi / 4) + ((_textureRandom.nextDouble() - 0.5) * 0.25);

          final delta = Offset(
            math.cos(hatchAngle) * size,
            math.sin(hatchAngle) * size,
          );

          generated.add(
            VectorStroke(
              points: [
                VectorPoint(
                  dx: center.dx - delta.dx / 2,
                  dy: center.dy - delta.dy / 2,
                  pressure: pressure,
                ),
                VectorPoint(
                  dx: center.dx + delta.dx / 2,
                  dy: center.dy + delta.dy / 2,
                  pressure: pressure,
                ),
              ],
              strokeWidth: math.max(0.8, _brushSize * 0.35),
              color: _brushColor.withValues(alpha: _brushOpacity),
              brushType: StrokeBrushType.solid,
            ),
          );
          break;

        case 'grain':
          final grainAngle = _textureRandom.nextDouble() * math.pi * 2;

          final grainLength =
              size * (0.15 + _textureRandom.nextDouble() * 0.35);

          final delta = Offset(
            math.cos(grainAngle) * grainLength,
            math.sin(grainAngle) * grainLength,
          );

          generated.add(
            VectorStroke(
              points: [
                VectorPoint(dx: center.dx, dy: center.dy, pressure: pressure),
                VectorPoint(
                  dx: center.dx + delta.dx,
                  dy: center.dy + delta.dy,
                  pressure: pressure,
                ),
              ],
              strokeWidth: math.max(0.5, _brushSize * 0.18),
              color: _brushColor.withValues(alpha: _brushOpacity * 0.75),
              brushType: StrokeBrushType.solid,
            ),
          );
          break;

        case 'stipple':
        default:
          generated.add(
            VectorStroke(
              points: [
                VectorPoint(dx: center.dx, dy: center.dy, pressure: pressure),
              ],
              strokeWidth: math.max(1.0, size * 0.45),
              color: _brushColor.withValues(alpha: _brushOpacity),
              brushType: StrokeBrushType.solid,
            ),
          );
          break;
      }
    }

    _draftTextureStrokes.addAll(generated);
  }

  void _commitTextureStroke() {
    if (_draftTextureStrokes.isEmpty) {
      return;
    }

    _saveUndoState();

    final layer = _activeLayer;
    final frames = _copyLayerFrames(layer.frames);

    frames[_selectedFrameIndex] = <VectorStroke>[
      ...frames[_selectedFrameIndex],
      ..._draftTextureStrokes,
    ];

    _layers[_activeLayerIndex] = layer.copyWith(frames: frames);

    _draftTextureStrokes = <VectorStroke>[];
    _rebuildCompositeFrames();
    _scheduleAutosave();
  }

  double _canvasTouchAngle() {
    if (_canvasTouchPointers.length < 2) {
      return 0.0;
    }

    final points = _canvasTouchPointers.values.take(2).toList();
    final delta = points[1] - points[0];

    return math.atan2(delta.dy, delta.dx);
  }

  void _updateCanvasRotationPointerDown(PointerDownEvent event) {
    if (event.kind != ui.PointerDeviceKind.touch) {
      return;
    }

    _canvasTouchPointers[event.pointer] = event.position;

    if (_canvasTouchPointers.length == 2) {
      _canvasRotationGestureStartAngle = _canvasTouchAngle();
      _canvasRotationGestureStartValue = _canvasRotation;
    }
  }

  void _updateCanvasRotationPointerMove(PointerMoveEvent event) {
    if (event.kind != ui.PointerDeviceKind.touch ||
        !_canvasTouchPointers.containsKey(event.pointer)) {
      return;
    }

    _canvasTouchPointers[event.pointer] = event.position;

    if (_canvasTouchPointers.length < 2 ||
        _canvasRotationGestureStartAngle == null) {
      return;
    }

    final currentAngle = _canvasTouchAngle();
    final angleDelta = currentAngle - _canvasRotationGestureStartAngle!;

    setState(() {
      _canvasRotation = _canvasRotationGestureStartValue + angleDelta;
    });
  }

  void _updateCanvasRotationPointerEnd(PointerEvent event) {
    if (event.kind != ui.PointerDeviceKind.touch) {
      return;
    }

    _canvasTouchPointers.remove(event.pointer);

    if (_canvasTouchPointers.length < 2) {
      _canvasRotationGestureStartAngle = null;
      _canvasRotationGestureStartValue = _canvasRotation;
    }
  }

  double _distanceFromPointToSegment(Offset point, Offset start, Offset end) {
    final segment = end - start;
    final lengthSquared = (segment.dx * segment.dx) + (segment.dy * segment.dy);

    if (lengthSquared <= 0.000001) {
      return (point - start).distance;
    }

    final fromStart = point - start;

    final projection =
        ((fromStart.dx * segment.dx) + (fromStart.dy * segment.dy)) /
        lengthSquared;

    final t = projection.clamp(0.0, 1.0);

    final closest = Offset(
      start.dx + (segment.dx * t),
      start.dy + (segment.dy * t),
    );

    return (point - closest).distance;
  }

  bool _pointInsideTintFill(Offset point, List<VectorPoint> points) {
    if (points.length < 3) {
      return false;
    }

    var inside = false;
    var previousIndex = points.length - 1;

    for (var index = 0; index < points.length; index++) {
      final current = points[index];
      final previous = points[previousIndex];

      final crossesY = (current.dy > point.dy) != (previous.dy > point.dy);

      if (crossesY) {
        final intersectionX =
            ((previous.dx - current.dx) *
                (point.dy - current.dy) /
                (previous.dy - current.dy)) +
            current.dx;

        if (point.dx < intersectionX) {
          inside = !inside;
        }
      }

      previousIndex = index;
    }

    return inside;
  }

  bool _tintStrokeHit(VectorStroke stroke, Offset position, double radius) {
    if (stroke.points.isEmpty) {
      return false;
    }

    if (stroke.filled && _pointInsideTintFill(position, stroke.points)) {
      return true;
    }

    final hitRadius = radius + (stroke.strokeWidth / 2);

    if (stroke.points.length == 1) {
      final point = stroke.points.first;

      return (position - Offset(point.dx, point.dy)).distance <= hitRadius;
    }

    for (var index = 1; index < stroke.points.length; index++) {
      final previous = stroke.points[index - 1];
      final current = stroke.points[index];

      final distance = _distanceFromPointToSegment(
        position,
        Offset(previous.dx, previous.dy),
        Offset(current.dx, current.dy),
      );

      if (distance <= hitRadius) {
        return true;
      }
    }

    return false;
  }

  VectorStroke _tintedStroke(VectorStroke stroke) {
    // Preserve the original alpha. Tint/Recolour changes pigment,
    // never the transparency of the existing artwork.
    final targetColor = _brushColor.withValues(alpha: stroke.color.a);

    final resultColor = _isSolidRecolourMode
        ? targetColor
        : (Color.lerp(
                stroke.color,
                targetColor,
                _brushOpacity.clamp(0.0, 1.0),
              ) ??
              stroke.color);

    return VectorStroke(
      points: stroke.points.map((point) => point.copy()).toList(),
      strokeWidth: stroke.strokeWidth,
      color: resultColor,
      filled: stroke.filled,
      brushType: stroke.brushType,
    );
  }

  void _applyTintAt(Offset position, double pressure) {
    if (_activeLayerIndex < 0 || _activeLayerIndex >= _layers.length) {
      return;
    }

    final layer = _activeLayer;

    if (_selectedFrameIndex < 0 || _selectedFrameIndex >= layer.frames.length) {
      return;
    }

    final sourceStrokes = layer.frames[_selectedFrameIndex];

    if (sourceStrokes.isEmpty) {
      return;
    }

    // S Pen pressure affects the Tint Brush's reach without modifying
    // the pressure data stored in the artwork itself.
    final safePressure = pressure.clamp(0.0, 1.0);
    final pressureFactor = 0.5 + safePressure;

    final radius = math.max(4.0, _brushSize * 2.0 * pressureFactor);

    final hitIndices = <int>[];

    for (var index = 0; index < sourceStrokes.length; index++) {
      // A stroke is tinted only once during a single gesture.
      // Lift the pen/finger and paint over it again to build more tint.
      if (_tintTouchedStrokeIndices.contains(index)) {
        continue;
      }

      if (_tintStrokeHit(sourceStrokes[index], position, radius)) {
        hitIndices.add(index);
      }
    }

    if (hitIndices.isEmpty) {
      return;
    }

    // Capture exactly one undo state for the entire Tint gesture.
    if (!_tintGestureUndoCaptured) {
      _saveUndoState();
      _tintGestureUndoCaptured = true;
    }

    final frames = _copyLayerFrames(layer.frames);
    final updatedStrokes = frames[_selectedFrameIndex];

    for (final index in hitIndices) {
      updatedStrokes[index] = _tintedStroke(updatedStrokes[index]);
    }

    setState(() {
      _layers[_activeLayerIndex] = layer.copyWith(frames: frames);

      _tintTouchedStrokeIndices.addAll(hitIndices);
      _tintGestureChanged = true;

      _rebuildCompositeFrames();
    });
  }

  void _handlePointerDown(PointerDownEvent event, BuildContext canvasContext) {
    _updateCanvasRotationPointerDown(event);
    _activePointerCount += 1;
    if (_activePointerCount > 1) {
      setState(() {
        _draftStroke = const <VectorPoint>[];
        _draftStampStrokes = <VectorStroke>[];
        _stampBrushLastPosition = null;
      });
      return;
    }
    if (_isPlaying) {
      return;
    }

    final renderBox = canvasContext.findRenderObject() as RenderBox;
    final canvasPosition = renderBox.globalToLocal(event.position);

    if (_brushEyedropperArmed) {
      unawaited(_sampleBrushColour(canvasPosition));
      return;
    }

    if (_drawingMode && _blendSamplingArmed) {
      _blendBaseColor = _brushColor;

      unawaited(_sampleBlendColour(canvasPosition));

      return;
    }

    if (_drawingMode && _stampBrushActive && _stampBrushItem != null) {
      setState(() {
        _draftStampStrokes = <VectorStroke>[];
        _stampBrushLastPosition = canvasPosition;
        _addBagStampToDraft(canvasPosition, event.pressure);
      });

      return;
    }

    if (_drawingMode && _textureActive) {
      _draftTextureStrokes = <VectorStroke>[];

      setState(() {
        _addTextureStamp(canvasPosition, event.pressure);
      });

      return;
    }

    if (_isTransformActive) {
      final bounds = _transformSelectionBounds();

      if (bounds != null) {
        if (_transformPivotHit(canvasPosition, bounds)) {
          setState(() {
            _transformPivot = _effectiveTransformPivot(bounds);
            _isTransformPivotDragging = true;
            _isTransformRotating = false;
            _isTransformScaling = false;
            _isTransformDragging = false;
          });

          return;
        }

        if (_transformRotationHandleHit(canvasPosition, bounds)) {
          if (_transformReferenceLayerId == null) {
            if (_activeLayerGroup == null) {
              _saveUndoState();
            } else {
              _saveGroupUndoState();
            }
          }

          final pivot = _effectiveTransformPivot(bounds);

          setState(() {
            _transformPivot = pivot;
            _isTransformRotating = true;
            _isTransformScaling = false;
            _isTransformDragging = false;
            _isTransformPivotDragging = false;
            _transformRotationCenter = pivot;
            _transformRotationStartAngle = _angleFromCenter(
              canvasPosition,
              pivot,
            );
            if (_transformReferenceLayerId != null) {
              _referenceTransformSnapshot = _referenceTransformTarget;
              _transformRotationSnapshot = null;
            } else {
              _referenceTransformSnapshot = null;
              _transformRotationSnapshot = _selectedTransformSnapshot();
            }
          });

          return;
        }

        final corner = _transformCornerHit(canvasPosition, bounds);

        if (corner != null) {
          if (_transformReferenceLayerId == null) {
            if (_activeLayerGroup == null) {
              _saveUndoState();
            } else {
              _saveGroupUndoState();
            }
          }

          final anchor = _oppositeTransformCorner(corner, bounds);

          final startDistance = (corner - anchor).distance;

          setState(() {
            _isTransformScaling = true;
            _isTransformDragging = false;
            _isTransformRotating = false;
            _transformScaleHorizontalOnly = false;
            _transformScaleVerticalOnly = false;
            _transformScaleAnchor = anchor;
            _transformScaleStartDistance = startDistance < 0.001
                ? 0.001
                : startDistance;
            if (_transformReferenceLayerId != null) {
              _referenceTransformSnapshot = _referenceTransformTarget;
              _transformScaleSnapshot = null;
            } else {
              _referenceTransformSnapshot = null;
              _transformScaleSnapshot = _selectedTransformSnapshot();
            }
          });

          return;
        }

        final edgeHandle = _transformEdgeHandleHit(canvasPosition, bounds);

        if (edgeHandle != null) {
          if (_transformReferenceLayerId == null) {
            if (_activeLayerGroup == null) {
              _saveUndoState();
            } else {
              _saveGroupUndoState();
            }
          }

          final anchor = _oppositeTransformEdge(edgeHandle, bounds);
          final horizontal = _transformHandleIsHorizontal(edgeHandle, bounds);

          final startDistance = horizontal
              ? (edgeHandle.dx - anchor.dx).abs()
              : (edgeHandle.dy - anchor.dy).abs();

          setState(() {
            _isTransformScaling = true;
            _isTransformDragging = false;
            _isTransformRotating = false;

            _transformScaleHorizontalOnly = horizontal;
            _transformScaleVerticalOnly = !horizontal;

            _transformScaleAnchor = anchor;
            _transformScaleStartDistance = startDistance < 0.001
                ? 0.001
                : startDistance;

            if (_transformReferenceLayerId != null) {
              _referenceTransformSnapshot = _referenceTransformTarget;
              _transformScaleSnapshot = null;
            } else {
              _referenceTransformSnapshot = null;
              _transformScaleSnapshot = _selectedTransformSnapshot();
            }
          });

          return;
        }
      }

      if (bounds != null && bounds.inflate(16).contains(canvasPosition)) {
        if (_activeLayerGroup == null) {
          _saveUndoState();
        } else {
          _saveGroupUndoState();
        }

        setState(() {
          _isTransformDragging = true;
          _isTransformScaling = false;
          _isTransformRotating = false;
          _transformLastPosition = canvasPosition;
        });
      } else if (_transformReferenceLayerId == null) {
        setState(() {
          _selectedTransformStrokes = <String, Set<int>>{};
          _transformPivot = null;
          _isTransformPivotDragging = false;
          _lassoPoints = <VectorPoint>[
            VectorPoint(
              dx: canvasPosition.dx,
              dy: canvasPosition.dy,
              pressure: 1,
            ),
          ];
        });
      }

      return;
    }

    if (_isFillToolActive) {
      _fillStabilizerTrailingPosition = canvasPosition;

      setState(() {
        _fillLassoPoints = <VectorPoint>[
          VectorPoint(
            dx: canvasPosition.dx,
            dy: canvasPosition.dy,
            pressure: 1,
          ),
        ];
      });

      return;
    }

    if (_isShapeToolActive) {
      if (_shapeToolType == _ShapeToolType.perspectiveRectangle &&
          _perspectiveShapeEditing) {
        final corner = _perspectiveCornerHit(canvasPosition);

        setState(() {
          _perspectiveDraggingCorner = corner;

          if (corner == null) {
            _clearPerspectiveLoupe();
          }
        });

        if (corner != null) {
          unawaited(_capturePerspectiveLoupe(canvasPosition, event.position));
        }

        return;
      }

      setState(() {
        _shapeStartPosition = canvasPosition;
        _draftShapeStrokes = _shapeStrokes(canvasPosition, canvasPosition);
      });

      return;
    }

    if (_isTintToolActive) {
      _tintTouchedStrokeIndices.clear();
      _tintGestureChanged = false;
      _tintGestureUndoCaptured = false;

      _applyTintAt(canvasPosition, event.pressure);
      return;
    }

    if (_isEraserActive) {
      _saveUndoState();
      setState(() {
        _eraseAt(canvasPosition);
      });
      return;
    }

    _stabilizerTrailingPosition = canvasPosition;

    setState(() {
      _draftStroke = <VectorPoint>[
        VectorPoint(
          dx: canvasPosition.dx,
          dy: canvasPosition.dy,
          pressure: event.pressure,
        ),
      ];
    });
  }

  void _handlePointerMove(PointerMoveEvent event, BuildContext canvasContext) {
    _updateCanvasRotationPointerMove(event);

    if (_isPlaying) {
      return;
    }

    if (_activePointerCount != 1) {
      return;
    }

    final renderBox = canvasContext.findRenderObject() as RenderBox;
    final canvasPosition = renderBox.globalToLocal(event.position);

    if (_drawingMode && _stampBrushActive && _stampBrushItem != null) {
      setState(() {
        _addBagStampsAlongPath(canvasPosition, event.pressure);
      });

      return;
    }

    if (_drawingMode && _textureActive) {
      setState(() {
        _addTextureStamp(canvasPosition, event.pressure);
      });

      return;
    }

    if (_isTransformActive) {
      if (_isTransformPivotDragging) {
        setState(() {
          _transformPivot = canvasPosition;

          if (_transformReferenceLayerId != null) {
            _setReferenceTransformPivot(canvasPosition);
          }
        });

        return;
      }

      if (_isTransformRotating &&
          _transformRotationCenter != null &&
          _transformRotationStartAngle != null &&
          (_transformRotationSnapshot != null ||
              _referenceTransformSnapshot != null)) {
        final currentAngle = _angleFromCenter(
          canvasPosition,
          _transformRotationCenter!,
        );

        final angle = currentAngle - _transformRotationStartAngle!;

        setState(() {
          final referenceSnapshot = _referenceTransformSnapshot;

          if (_transformReferenceLayerId != null && referenceSnapshot != null) {
            _rotateReferenceTransform(
              angle,
              _transformRotationCenter!,
              referenceSnapshot,
            );
          } else if (_transformRotationSnapshot != null) {
            _rotateSelectedStrokes(
              angle,
              _transformRotationCenter!,
              _transformRotationSnapshot!,
            );
          }
        });

        return;
      }

      if (_isTransformScaling &&
          _transformScaleAnchor != null &&
          _transformScaleStartDistance != null &&
          (_transformScaleSnapshot != null ||
              _referenceTransformSnapshot != null)) {
        double scaleX = 1.0;
        double scaleY = 1.0;

        if (_transformScaleHorizontalOnly) {
          final currentDistance =
              (canvasPosition.dx - _transformScaleAnchor!.dx).abs();

          scaleX = currentDistance / _transformScaleStartDistance!;
        } else if (_transformScaleVerticalOnly) {
          final currentDistance =
              (canvasPosition.dy - _transformScaleAnchor!.dy).abs();

          scaleY = currentDistance / _transformScaleStartDistance!;
        } else {
          final currentDistance =
              (canvasPosition - _transformScaleAnchor!).distance;

          final scale = currentDistance / _transformScaleStartDistance!;

          scaleX = scale;
          scaleY = scale;
        }

        setState(() {
          final referenceSnapshot = _referenceTransformSnapshot;

          if (_transformReferenceLayerId != null && referenceSnapshot != null) {
            _scaleReferenceTransform(
              scaleX,
              scaleY,
              _transformScaleAnchor!,
              referenceSnapshot,
            );
          } else if (_transformScaleSnapshot != null) {
            _scaleSelectedStrokes(
              scaleX,
              scaleY,
              _transformScaleAnchor!,
              _transformScaleSnapshot!,
            );
          }
        });

        return;
      }

      if (_isTransformDragging && _transformLastPosition != null) {
        final delta = canvasPosition - _transformLastPosition!;

        setState(() {
          if (_transformReferenceLayerId != null) {
            _moveReferenceTransform(delta);
          } else {
            _moveSelectedStrokes(delta);
          }

          if (_transformPivot != null) {
            _transformPivot = _transformPivot! + delta;
          }

          _transformLastPosition = canvasPosition;
        });

        return;
      }

      if (_transformReferenceLayerId == null && _lassoPoints.isNotEmpty) {
        final last = _lassoPoints.last;
        final dx = canvasPosition.dx - last.dx;
        final dy = canvasPosition.dy - last.dy;

        if ((dx * dx) + (dy * dy) >= 4) {
          setState(() {
            _lassoPoints.add(
              VectorPoint(
                dx: canvasPosition.dx,
                dy: canvasPosition.dy,
                pressure: 1,
              ),
            );
          });
        }
      }

      return;
    }

    if (_isFillToolActive && _fillLassoPoints.isNotEmpty) {
      final stabilizedPosition = _stabilizeFillPosition(canvasPosition);

      final last = _fillLassoPoints.last;
      final dx = stabilizedPosition.dx - last.dx;
      final dy = stabilizedPosition.dy - last.dy;

      const minimumDistanceSquared = 2.25;

      if ((dx * dx) + (dy * dy) >= minimumDistanceSquared) {
        setState(() {
          _fillLassoPoints.add(
            VectorPoint(
              dx: stabilizedPosition.dx,
              dy: stabilizedPosition.dy,
              pressure: 1,
            ),
          );
        });
      }

      return;
    }

    if (_isShapeToolActive &&
        _shapeToolType == _ShapeToolType.perspectiveRectangle &&
        _perspectiveShapeEditing) {
      final corner = _perspectiveDraggingCorner;

      if (corner != null) {
        setState(() {
          _updatePerspectiveCorner(corner, canvasPosition);

          _updatePerspectiveLoupe(canvasPosition, event.position);
        });
      }

      return;
    }

    if (_isShapeToolActive && _shapeStartPosition != null) {
      setState(() {
        _updateShapePreview(canvasPosition);
      });

      return;
    }

    if (_isTintToolActive) {
      _applyTintAt(canvasPosition, event.pressure);
      return;
    }

    if (_isEraserActive) {
      setState(() {
        _eraseAt(canvasPosition);
      });
      return;
    }

    if (_draftStroke.isEmpty) {
      return;
    }

    final stabilizedPosition = _stabilizePosition(canvasPosition);

    final lastPoint = _draftStroke.last;
    final dx = stabilizedPosition.dx - lastPoint.dx;
    final dy = stabilizedPosition.dy - lastPoint.dy;
    final distanceSquared = (dx * dx) + (dy * dy);

    const minimumDistanceSquared = 2.25;

    if (distanceSquared < minimumDistanceSquared) {
      return;
    }

    setState(() {
      _draftStroke.add(
        VectorPoint(
          dx: stabilizedPosition.dx,
          dy: stabilizedPosition.dy,

          // Pressure remains completely untouched by stabilisation.
          pressure: event.pressure,
        ),
      );
    });
  }

  void _saveGroupUndoState() {
    // Groups and individual layers now share one chronological
    // frame-wide history.
    _saveUndoState();
  }

  void _undo() {
    if (_selectedFrameIndex < 0 || _selectedFrameIndex >= _undoStacks.length) {
      return;
    }

    final undoStack = _undoStacks[_selectedFrameIndex];
    final redoStack = _redoStacks[_selectedFrameIndex];

    if (undoStack.isEmpty) return;

    setState(() {
      redoStack.add(_frameHistorySnapshot());

      final snapshot = undoStack.removeLast();

      _restoreFrameHistorySnapshot(snapshot);
      _clearTransformSelection();
    });

    _scheduleAutosave();
  }

  void _redo() {
    if (_selectedFrameIndex < 0 || _selectedFrameIndex >= _redoStacks.length) {
      return;
    }

    final undoStack = _undoStacks[_selectedFrameIndex];
    final redoStack = _redoStacks[_selectedFrameIndex];

    if (redoStack.isEmpty) return;

    setState(() {
      undoStack.add(_frameHistorySnapshot());

      final snapshot = redoStack.removeLast();

      _restoreFrameHistorySnapshot(snapshot);
      _clearTransformSelection();
    });

    _scheduleAutosave();
  }

  void _handlePointerUp(PointerUpEvent event) {
    _updateCanvasRotationPointerEnd(event);

    if (_activePointerCount > 0) {
      _activePointerCount -= 1;
    }

    if (_drawingMode && _stampBrushActive && _draftStampStrokes.isNotEmpty) {
      _commitStampBrushStroke();
      return;
    }

    if (_drawingMode && _textureActive && _draftTextureStrokes.isNotEmpty) {
      setState(() {
        _commitTextureStroke();
      });

      return;
    }

    if (_isFillToolActive && _fillLassoPoints.isNotEmpty) {
      setState(() {
        _commitFillLasso();
      });

      _scheduleAutosave();
      return;
    }

    if (_isShapeToolActive &&
        _shapeToolType == _ShapeToolType.perspectiveRectangle &&
        _perspectiveShapeEditing) {
      setState(() {
        _perspectiveDraggingCorner = null;
        _clearPerspectiveLoupe();
      });

      return;
    }

    if (_isShapeToolActive && _shapeStartPosition != null) {
      if (_shapeToolType == _ShapeToolType.perspectiveRectangle) {
        setState(() {
          _shapeStartPosition = null;

          _perspectiveShapeEditing =
              _perspectiveShapeCorners.length == 4 &&
              _draftShapeStrokes.isNotEmpty;

          _perspectiveDraggingCorner = null;
        });

        return;
      }

      setState(() {
        _commitShape();
      });

      _scheduleAutosave();
      return;
    }

    if (_isTintToolActive) {
      final changed = _tintGestureChanged;

      _tintTouchedStrokeIndices.clear();
      _tintGestureChanged = false;
      _tintGestureUndoCaptured = false;

      if (changed) {
        _scheduleAutosave();
      }

      return;
    }

    if (_isTransformActive) {
      setState(() {
        if (_isTransformPivotDragging) {
          _isTransformPivotDragging = false;
        } else if (_isTransformRotating) {
          _isTransformRotating = false;
          _transformRotationCenter = null;
          _transformRotationStartAngle = null;
          _transformRotationSnapshot = null;
          _referenceTransformSnapshot = null;
        } else if (_isTransformScaling) {
          _isTransformScaling = false;
          _transformScaleAnchor = null;
          _transformScaleStartDistance = null;
          _transformScaleSnapshot = null;
          _referenceTransformSnapshot = null;
          _transformScaleHorizontalOnly = false;
          _transformScaleVerticalOnly = false;
        } else if (_isTransformDragging) {
          _isTransformDragging = false;
          _transformLastPosition = null;
        } else if (_transformReferenceLayerId == null) {
          _finishLassoSelection();
        }
      });

      _scheduleAutosave();
      return;
    }

    if (_isPlaying || _draftStroke.isEmpty) {
      return;
    }

    _saveUndoState();

    final stroke = VectorStroke(
      points: List<VectorPoint>.from(_draftStroke),
      strokeWidth: _brushSize,
      color: _brushColor.withValues(alpha: _brushOpacity),
      brushType: _brushType,
    );

    setState(() {
      final layer = _activeLayer;
      final frames = _copyLayerFrames(layer.frames);

      frames[_selectedFrameIndex] = <VectorStroke>[
        ...frames[_selectedFrameIndex],
        stroke,
      ];

      _layers[_activeLayerIndex] = layer.copyWith(frames: frames);

      _draftStroke = const <VectorPoint>[];
      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _updateCanvasRotationPointerEnd(event);

    if (_activePointerCount > 0) {
      _activePointerCount -= 1;
    }

    if (_isPlaying) {
      return;
    }

    if (_perspectiveShapeEditing) {
      setState(() {
        _perspectiveDraggingCorner = null;
        _clearPerspectiveLoupe();
      });

      return;
    }

    setState(() {
      _draftStroke = const <VectorPoint>[];
      _tintTouchedStrokeIndices.clear();
      _tintGestureChanged = false;
      _tintGestureUndoCaptured = false;
      _clearFillLasso();
      _clearShapeDraft();
    });
  }

  static const MethodChannel _shareChannel = MethodChannel(
    'com.inkdframes.app/share',
  );

  Future<void> _shareExportedVideo(String uri) async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _shareChannel.invokeMethod<void>('shareVideo', <String, dynamic>{
        'uri': uri,
      });
    } on PlatformException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not share animation: ${error.message ?? error.code}',
          ),
        ),
      );
    }
  }

  Future<void> _exportAnimation() async {
    if (_isExporting) {
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      _rebuildCompositeFrames();

      final outputPath = await const AnimationExportService().exportMp4(
        projectName: _projectName,
        frames: _frames,
        frameDurations: _frameDurations,
        fps: _fps,
        canvasWidth: _canvasWidth,
        canvasHeight: _canvasHeight,
        backgroundColor: _canvasBackgroundColor,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Platform.isAndroid
                ? 'Animation exported to Movies/InkdFrames'
                : 'Animation exported to $outputPath',
          ),
          duration: const Duration(seconds: 8),
          action: Platform.isAndroid
              ? SnackBarAction(
                  label: 'SHARE',
                  onPressed: () {
                    unawaited(_shareExportedVideo(outputPath));
                  },
                )
              : null,
        ),
      );
    } on UnsupportedError catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? error.toString())),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  List<VectorStroke> _getPreviousFrameStrokes() {
    if (_selectedFrameIndex == 0) {
      return const <VectorStroke>[];
    }

    return _frames[_selectedFrameIndex - 1];
  }

  List<VectorStroke> _getNextFrameStrokes() {
    if (_selectedFrameIndex >= _frames.length - 1) {
      return const <VectorStroke>[];
    }

    return _frames[_selectedFrameIndex + 1];
  }

  void _rememberRecentColor(Color color) {
    _recentColors.removeWhere(
      (existing) => existing.toARGB32() == color.toARGB32(),
    );

    _recentColors.insert(0, color);

    if (_recentColors.length > 8) {
      _recentColors.removeRange(8, _recentColors.length);
    }
  }

  String _colorHex(Color color) {
    return color
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
  }

  Color? _colorFromHex(String input) {
    final cleaned = input.trim().replaceAll('#', '').toUpperCase();

    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(cleaned)) {
      return null;
    }

    final value = int.tryParse('FF$cleaned', radix: 16);

    if (value == null) return null;

    return Color(value);
  }

  Future<Color?> _showRadialColourPicker(Color initialColor) async {
    var hsv = HSVColor.fromColor(initialColor);

    return showDialog<Color>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final selectedColor = hsv.toColor();

            void updateFromPosition(Offset position) {
              const center = Offset(130, 130);
              final delta = position - center;
              final radius = delta.distance;

              final angle = math.atan2(delta.dy, delta.dx);
              final hue = ((angle * 180 / math.pi) + 360) % 360;

              if (radius >= 92) {
                setDialogState(() {
                  hsv = hsv.withHue(hue);
                });
                return;
              }

              final saturation = (radius / 92).clamp(0.0, 1.0);

              setDialogState(() {
                hsv = hsv.withSaturation(saturation);
              });
            }

            return AlertDialog(
              title: const Text('Visual Colour Picker'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 260,
                      height: 260,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          updateFromPosition(details.localPosition);
                        },
                        onPanDown: (details) {
                          updateFromPosition(details.localPosition);
                        },
                        onPanUpdate: (details) {
                          updateFromPosition(details.localPosition);
                        },
                        child: CustomPaint(
                          painter: _RadialColourPickerPainter(hsv: hsv),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const SizedBox(width: 82, child: Text('Brightness')),
                        Expanded(
                          child: Slider(
                            value: hsv.value,
                            min: 0,
                            max: 1,
                            onChanged: (value) {
                              setDialogState(() {
                                hsv = hsv.withValue(value);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: selectedColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '#${_colorHex(selectedColor)}',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _brushEyedropperArmed = true;
                    });

                    Navigator.pop(dialogContext);
                  },
                  icon: const Icon(Icons.colorize),
                  label: const Text('Eyedropper'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, hsv.toColor());
                  },
                  child: const Text('Use Colour'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<Color?> _showColourPicker(
    Color initialColor, {
    required String title,
  }) async {
    var hsv = HSVColor.fromColor(initialColor);
    var hexInput = _colorHex(initialColor);

    return showDialog<Color>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final selectedColor = hsv.toColor();

            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: selectedColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text('Hue')),
                          Expanded(
                            child: Slider(
                              value: hsv.hue,
                              min: 0,
                              max: 360,
                              onChanged: (value) {
                                setDialogState(() {
                                  hsv = hsv.withHue(value);
                                  hexInput = _colorHex(hsv.toColor());
                                });
                              },
                            ),
                          ),
                        ],
                      ),

                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text('Saturation')),
                          Expanded(
                            child: Slider(
                              value: hsv.saturation,
                              min: 0,
                              max: 1,
                              onChanged: (value) {
                                setDialogState(() {
                                  hsv = hsv.withSaturation(value);
                                  hexInput = _colorHex(hsv.toColor());
                                });
                              },
                            ),
                          ),
                        ],
                      ),

                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text('Brightness')),
                          Expanded(
                            child: Slider(
                              value: hsv.value,
                              min: 0,
                              max: 1,
                              onChanged: (value) {
                                setDialogState(() {
                                  hsv = hsv.withValue(value);
                                  hexInput = _colorHex(hsv.toColor());
                                });
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      TextFormField(
                        initialValue: hexInput,
                        decoration: const InputDecoration(
                          labelText: 'HEX',
                          prefixText: '#',
                          hintText: 'FF5722',
                        ),
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (value) {
                          hexInput = value;

                          final parsed = _colorFromHex(value);

                          if (parsed != null) {
                            setDialogState(() {
                              hsv = HSVColor.fromColor(parsed);
                            });
                          }
                        },
                      ),

                      const SizedBox(height: 10),

                      Text(
                        '#${_colorHex(selectedColor)}',
                        style: Theme.of(dialogContext).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _brushEyedropperArmed = true;
                    });

                    Navigator.pop(dialogContext);
                  },
                  icon: const Icon(Icons.colorize),
                  label: const Text('Eyedropper'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, hsv.toColor());
                  },
                  child: const Text('Use Colour'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _selectReferenceLayer(String referenceId) async {
    final index = _referenceLayers.indexWhere(
      (reference) => reference.id == referenceId,
    );

    if (index == -1) {
      return;
    }

    if (_activeReferenceLayerId == referenceId) {
      return;
    }

    // Preserve any active video position/frame mapping/opacity changes before
    // handing the compatibility bridge to another ReferenceLayer.
    _syncActiveReferenceLayerFromLegacyState();

    final oldController = _videoController;

    if (oldController != null && oldController.value.isPlaying) {
      await oldController.pause();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _activeReferenceLayerId = referenceId;
      _loadLegacyReferenceStateFromActiveLayer();

      _activeLayerGroupId = null;
      _mergeSelectedLayerIds.clear();

      _isVideoScrubbing = false;
      _videoReady = false;
    });

    if (_referenceMediaType == 'video') {
      await _initializeVideoReference();
    } else {
      if (mounted) {
        setState(() {
          _videoController = null;
          _videoReady = false;
        });
      }

      await oldController?.dispose();
    }

    _scheduleAutosave();
  }

  void _setReferenceLayerVisible(String referenceId, bool visible) {
    final index = _referenceLayers.indexWhere(
      (reference) => reference.id == referenceId,
    );

    if (index == -1) {
      return;
    }

    setState(() {
      _referenceLayers[index] = _referenceLayers[index].copyWith(
        visible: visible,
      );

      if (_activeReferenceLayerId == referenceId) {
        _referenceVisible = visible;
      }
    });

    _scheduleAutosave();
  }

  void _setReferenceLayerOpacity(String referenceId, double opacity) {
    final index = _referenceLayers.indexWhere(
      (reference) => reference.id == referenceId,
    );

    if (index == -1) {
      return;
    }

    final safeOpacity = opacity.clamp(0.0, 1.0);

    setState(() {
      _referenceLayers[index] = _referenceLayers[index].copyWith(
        opacity: safeOpacity,
      );

      if (_activeReferenceLayerId == referenceId) {
        _referenceOpacity = safeOpacity;
      }
    });

    _scheduleAutosave();
  }

  Future<void> _addReferenceLayer(String mediaType) async {
    final pickedFile = await FilePicker.pickFile(
      type: mediaType == 'image' ? FileType.image : FileType.video,
    );

    if (pickedFile == null || !mounted) {
      return;
    }

    final sourcePath = pickedFile.path;

    if (sourcePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not access that file.')),
      );
      return;
    }

    try {
      final referenceDirectory = Platform.isLinux
          ? Directory('/tmp/inkdframes_reference_media')
          : Directory('/data/user/0/com.inkdframes.app/files/reference_media');

      if (!await referenceDirectory.exists()) {
        await referenceDirectory.create(recursive: true);
      }

      final sourceName = pickedFile.name;
      final extension = sourceName.contains('.')
          ? '.${sourceName.split('.').last}'
          : '';

      final storedPath =
          '${referenceDirectory.path}/'
          '${DateTime.now().microsecondsSinceEpoch}$extension';

      await File(sourcePath).copy(storedPath);

      if (!mounted) {
        return;
      }

      // Preserve the current active reference before switching.
      _syncActiveReferenceLayerFromLegacyState();

      final reference = ReferenceLayer(
        id: 'reference_${DateTime.now().microsecondsSinceEpoch}',
        name: sourceName.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        mediaPath: storedPath,
        mediaType: mediaType,
      );

      setState(() {
        // References are currently their own stack inside the reference area.
        // New references are placed at the top of that stack.
        _referenceLayers.insert(0, reference);

        _activeReferenceLayerId = reference.id;
        _loadLegacyReferenceStateFromActiveLayer();

        _activeLayerGroupId = null;
        _mergeSelectedLayerIds.clear();

        _isVideoScrubbing = false;
        _videoReady = false;
      });

      if (mediaType == 'video') {
        await _initializeVideoReference();
      } else {
        final oldController = _videoController;

        if (mounted) {
          setState(() {
            _videoController = null;
            _videoReady = false;
          });
        }

        await oldController?.dispose();
      }

      _scheduleAutosave();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mediaType == 'video'
                ? 'Video reference added 🎞️'
                : 'Image reference added 🖼️',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('❌ Reference import failed: $error');
      debugPrint(stackTrace.toString());

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add that reference.')),
      );
    }
  }

  Future<void> _renameReferenceLayer(ReferenceLayer reference) async {
    final controller = TextEditingController(text: reference.name);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename Reference'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Reference name'),
            onSubmitted: (value) {
              final trimmed = value.trim();

              if (trimmed.isNotEmpty) {
                Navigator.pop(dialogContext, trimmed);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = controller.text.trim();

                if (trimmed.isNotEmpty) {
                  Navigator.pop(dialogContext, trimmed);
                }
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null || !mounted) {
      return;
    }

    final index = _referenceLayers.indexWhere(
      (item) => item.id == reference.id,
    );

    if (index == -1) {
      return;
    }

    setState(() {
      _referenceLayers[index] = _referenceLayers[index].copyWith(name: result);
    });

    _scheduleAutosave();
  }

  Future<void> _deleteReferenceLayer(ReferenceLayer reference) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Reference?'),
          content: Text(
            'Remove "${reference.name}" from this project?\n\n'
            'The original media file will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final index = _referenceLayers.indexWhere(
      (item) => item.id == reference.id,
    );

    if (index == -1) {
      return;
    }

    final deletingActive = _activeReferenceLayerId == reference.id;

    if (!deletingActive) {
      setState(() {
        _referenceLayers.removeAt(index);
      });

      _scheduleAutosave();
      return;
    }

    // Preserve the active compatibility state before removing its layer.
    _syncActiveReferenceLayerFromLegacyState();

    final oldController = _videoController;

    if (oldController != null && oldController.value.isPlaying) {
      await oldController.pause();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _referenceLayers.removeWhere((item) => item.id == reference.id);

      _activeReferenceLayerId = _referenceLayers.isEmpty
          ? null
          : _referenceLayers.first.id;

      _loadLegacyReferenceStateFromActiveLayer();

      _isVideoScrubbing = false;
      _videoReady = false;
    });

    if (_referenceMediaType == 'video') {
      await _initializeVideoReference();
    } else {
      if (mounted) {
        setState(() {
          _videoController = null;
          _videoReady = false;
        });
      }

      await oldController?.dispose();
    }

    _scheduleAutosave();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${reference.name} removed')));
  }

  Widget _buildReferenceLayerCard(ReferenceLayer reference) {
    final selected = _activeReferenceLayerId == reference.id;

    return Container(
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      decoration: BoxDecoration(
        color: selected
            ? Colors.amberAccent.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? Colors.amberAccent : Colors.white12,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _isPlaying
            ? null
            : () {
                unawaited(_selectReferenceLayer(reference.id));
              },
        onLongPress: _isPlaying
            ? null
            : () {
                unawaited(_enterReferenceTransform(reference.id));
              },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: reference.visible
                      ? 'Hide Reference'
                      : 'Show Reference',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _setReferenceLayerVisible(reference.id, !reference.visible);
                  },
                  icon: Icon(
                    reference.visible ? Icons.visibility : Icons.visibility_off,
                    size: 20,
                  ),
                ),
                Icon(
                  reference.mediaType == 'video'
                      ? Icons.movie_outlined
                      : Icons.image_outlined,
                  size: 19,
                  color: selected ? Colors.amberAccent : Colors.white70,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(reference.name, overflow: TextOverflow.ellipsis),
                ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.adjust,
                      size: 16,
                      color: Colors.amberAccent,
                    ),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Reference Options',
                  enabled: !_isPlaying,
                  onSelected: (value) {
                    if (value == 'rename') {
                      unawaited(_renameReferenceLayer(reference));
                    } else if (value == 'delete') {
                      unawaited(_deleteReferenceLayer(reference));
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'rename',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Rename'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 10, 2),
              child: Row(
                children: [
                  const SizedBox(
                    width: 50,
                    child: Text('Opacity', style: TextStyle(fontSize: 11)),
                  ),
                  Expanded(
                    child: Slider(
                      value: reference.opacity,
                      min: 0,
                      max: 1,
                      onChanged: (value) {
                        _setReferenceLayerOpacity(reference.id, value);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${(reference.opacity * 100).round()}%',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _hierarchyParentGroupId(String entry) {
    if (entry.startsWith('group:')) {
      final groupId = entry.substring(6);
      return _groupContainingGroup(groupId)?.id;
    }

    if (entry.startsWith('layer:')) {
      final layerId = entry.substring(6);
      return _groupContainingLayer(layerId)?.id;
    }

    return null;
  }

  bool _canReorderHierarchyEntries(String draggedEntry, String targetEntry) {
    if (draggedEntry == targetEntry) {
      return false;
    }

    final draggedParent = _hierarchyParentGroupId(draggedEntry);
    final targetParent = _hierarchyParentGroupId(targetEntry);

    if (draggedParent != targetParent) {
      return false;
    }

    if (draggedParent == null) {
      return _rootLayerOrder.contains(draggedEntry) &&
          _rootLayerOrder.contains(targetEntry);
    }

    final parentIndex = _layerGroups.indexWhere(
      (group) => group.id == draggedParent,
    );

    if (parentIndex == -1) {
      return false;
    }

    final order = _layerGroups[parentIndex].childOrder;

    return order.contains(draggedEntry) && order.contains(targetEntry);
  }

  void _moveHierarchyEntryToTarget(String draggedEntry, String targetEntry) {
    if (!_canReorderHierarchyEntries(draggedEntry, targetEntry)) {
      return;
    }

    final parentGroupId = _hierarchyParentGroupId(draggedEntry);
    var changed = false;

    setState(() {
      if (parentGroupId == null) {
        final oldIndex = _rootLayerOrder.indexOf(draggedEntry);
        final oldTargetIndex = _rootLayerOrder.indexOf(targetEntry);

        if (oldIndex == -1 || oldTargetIndex == -1) {
          return;
        }

        _rootLayerOrder.removeAt(oldIndex);

        var targetIndex = _rootLayerOrder.indexOf(targetEntry);

        if (oldIndex < oldTargetIndex) {
          targetIndex += 1;
        }

        _rootLayerOrder.insert(targetIndex, draggedEntry);
        changed = true;
      } else {
        final parentIndex = _layerGroups.indexWhere(
          (group) => group.id == parentGroupId,
        );

        if (parentIndex == -1) {
          return;
        }

        final parent = _layerGroups[parentIndex];
        final updatedOrder = List<String>.from(parent.childOrder);

        final oldIndex = updatedOrder.indexOf(draggedEntry);
        final oldTargetIndex = updatedOrder.indexOf(targetEntry);

        if (oldIndex == -1 || oldTargetIndex == -1) {
          return;
        }

        updatedOrder.removeAt(oldIndex);

        var targetIndex = updatedOrder.indexOf(targetEntry);

        if (oldIndex < oldTargetIndex) {
          targetIndex += 1;
        }

        updatedOrder.insert(targetIndex, draggedEntry);

        _layerGroups[parentIndex] = parent.copyWith(childOrder: updatedOrder);

        changed = true;
      }

      if (changed) {
        _rebuildCompositeFrames();
      }
    });

    if (changed) {
      _scheduleAutosave();
    }
  }

  Widget _buildHierarchyDragHandle(String entry) {
    return Draggable<String>(
      data: entry,
      axis: Axis.vertical,
      maxSimultaneousDrags: _isPlaying ? 0 : 1,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: const Icon(
            Icons.drag_indicator,
            size: 22,
            color: Colors.white,
          ),
        ),
      ),
      childWhenDragging: const SizedBox(
        width: 30,
        height: 30,
        child: Opacity(
          opacity: 0.25,
          child: Icon(Icons.drag_indicator, size: 20),
        ),
      ),
      child: const SizedBox(
        width: 30,
        height: 30,
        child: Icon(Icons.drag_indicator, size: 20),
      ),
    );
  }

  Widget _buildHierarchyDropTarget({
    required String entry,
    required Widget child,
  }) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        return _canReorderHierarchyEntries(details.data, entry);
      },
      onAcceptWithDetails: (details) {
        _moveHierarchyEntryToTarget(details.data, entry);
      },
      builder: (context, candidateData, rejectedData) {
        final accepting = candidateData.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: accepting
                ? Colors.deepPurpleAccent.withValues(alpha: 0.10)
                : Colors.transparent,
          ),
          child: child,
        );
      },
    );
  }

  Widget? _buildHierarchyEntry(String entry, {required int depth}) {
    if (entry.startsWith('group:')) {
      final groupId = entry.substring(6);
      final groupIndex = _layerGroups.indexWhere(
        (group) => group.id == groupId,
      );

      if (groupIndex == -1) {
        return null;
      }

      return _buildHierarchyDropTarget(
        entry: entry,
        child: _buildLayerGroupCard(_layerGroups[groupIndex], depth: depth),
      );
    }

    if (entry.startsWith('layer:')) {
      final layerId = entry.substring(6);
      final layerIndex = _layers.indexWhere((layer) => layer.id == layerId);

      if (layerIndex == -1) {
        return null;
      }

      return _buildHierarchyDropTarget(
        entry: entry,
        child: _buildDrawingLayerCard(
          layerIndex,
          indented: depth > 0,
          hierarchyDepth: depth,
        ),
      );
    }

    return null;
  }

  List<Widget> _buildOrderedChildEntries(
    LayerGroup parent, {
    required int depth,
  }) {
    final widgets = <Widget>[];

    for (final entry in parent.childOrder) {
      final widget = _buildHierarchyEntry(entry, depth: depth);

      if (widget != null) {
        widgets.add(widget);
      }
    }

    return widgets;
  }

  List<Widget> _buildLayerPanelEntries() {
    final widgets = <Widget>[];

    for (final entry in _rootLayerOrder) {
      final widget = _buildHierarchyEntry(entry, depth: 0);

      if (widget != null) {
        widgets.add(widget);
      }
    }

    if (_referenceLayers.isNotEmpty) {
      widgets.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 5),
          child: Divider(height: 1),
        ),
      );

      for (final reference in _referenceLayers) {
        widgets.add(_buildReferenceLayerCard(reference));
      }
    }

    return widgets;
  }

  Widget _buildLayerGroupCard(LayerGroup group, {int depth = 0}) {
    final selected = _activeLayerGroupId == group.id;

    final childIndices = <int>[];

    for (var index = 0; index < _layers.length; index++) {
      if (group.childLayerIds.contains(_layers[index].id)) {
        childIndices.add(index);
      }
    }

    return Container(
      margin: EdgeInsets.fromLTRB(6.0 + (depth * 16.0), 4, 6, 0),
      decoration: BoxDecoration(
        color: selected
            ? Colors.deepPurpleAccent.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? Colors.deepPurpleAccent : Colors.white12,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _selectLayerGroup(group.id),
            onLongPress: _isPlaying
                ? null
                : () => _enterLayerGroupTransform(group.id),
            onDoubleTap: _isPlaying ? null : () => _renameLayerGroup(group.id),
            child: Row(
              children: [
                _buildHierarchyDragHandle('group:${group.id}'),
                IconButton(
                  tooltip: group.expanded ? 'Collapse Group' : 'Expand Group',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _toggleLayerGroupExpanded(group.id);
                  },
                  icon: Icon(
                    group.expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 20,
                  ),
                ),
                IconButton(
                  tooltip: group.visible ? 'Hide Group' : 'Show Group',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _setLayerGroupVisible(group.id, !group.visible);
                  },
                  icon: Icon(
                    group.visible ? Icons.visibility : Icons.visibility_off,
                    size: 20,
                  ),
                ),
                const Icon(Icons.folder_outlined, size: 19),
                const SizedBox(width: 6),
                Expanded(
                  child: Tooltip(
                    message: group.name,
                    preferBelow: false,
                    child: Text(
                      group.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
                Text(
                  '${childIndices.length}',
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Group Options',
                  onSelected: (value) {
                    if (value == 'bag') {
                      _addLayerGroupToBag(group.id);
                    } else if (value == 'png') {
                      _exportLayerGroupPng(group.id);
                    } else if (value == 'move-group') {
                      _showMoveGroupDialog(group.id);
                    } else if (value == 'rename') {
                      _renameLayerGroup(group.id);
                    } else if (value == 'delete') {
                      _deleteLayerGroup(group.id);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'bag',
                      child: ListTile(
                        leading: Icon(Icons.backpack_outlined),
                        title: Text('Add to Bag'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'png',
                      child: ListTile(
                        leading: Icon(Icons.image_outlined),
                        title: Text('Export PNG'),
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'move-group',
                      child: ListTile(
                        leading: Icon(Icons.drive_file_move_outline),
                        title: Text('Move to Group'),
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete Group')),
                  ],
                ),
              ],
            ),
          ),
          if (group.expanded)
            ..._buildOrderedChildEntries(group, depth: depth + 1),
        ],
      ),
    );
  }

  Widget _buildDrawingLayerCard(
    int index, {
    required bool indented,
    int hierarchyDepth = 0,
  }) {
    final layer = _layers[index];
    final selected = _activeLayerGroupId == null && index == _activeLayerIndex;
    final selectedForMerge = _mergeSelectedLayerIds.contains(layer.id);

    final currentGroup = _groupContainingLayer(layer.id);

    return Container(
      margin: EdgeInsets.fromLTRB(
        hierarchyDepth > 0
            ? 6.0 + (hierarchyDepth * 16.0)
            : (indented ? 22.0 : 6.0),
        4,
        6,
        0,
      ),
      decoration: BoxDecoration(
        color: selectedForMerge
            ? Colors.tealAccent.withValues(alpha: 0.12)
            : selected
            ? Colors.deepPurpleAccent.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selectedForMerge
              ? Colors.tealAccent
              : selected
              ? Colors.deepPurpleAccent
              : Colors.white12,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _selectLayer(index),
            onLongPress: _isPlaying ? null : () => _enterLayerTransform(index),
            onDoubleTap: _isPlaying ? null : () => _renameDrawingLayer(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  _buildHierarchyDragHandle('layer:${layer.id}'),
                  IconButton(
                    tooltip: layer.visible ? 'Hide Layer' : 'Show Layer',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _setLayerVisible(index, !layer.visible);
                    },
                    icon: Icon(
                      layer.visible ? Icons.visibility : Icons.visibility_off,
                      size: 20,
                    ),
                  ),
                  if (indented)
                    const Padding(
                      padding: EdgeInsets.only(right: 5),
                      child: Icon(
                        Icons.subdirectory_arrow_right,
                        size: 16,
                        color: Colors.white38,
                      ),
                    ),
                  Expanded(
                    child: Tooltip(
                      message: layer.name,
                      preferBelow: false,
                      child: Text(
                        layer.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Layer Options',
                    onSelected: (value) {
                      if (value == 'bag') {
                        _addDrawingLayerToBag(index);
                      } else if (value == 'png') {
                        _exportDrawingLayerPng(index);
                      } else if (value == 'merge-select') {
                        _toggleLayerMergeSelection(index);
                      } else if (value == 'rename') {
                        _renameDrawingLayer(index);
                      } else if (value == 'delete') {
                        _deleteDrawingLayer(index);
                      } else if (value == 'ungroup') {
                        _assignLayerToGroup(layer.id, null);
                      } else if (value.startsWith('group:')) {
                        _assignLayerToGroup(layer.id, value.substring(6));
                      }
                    },
                    itemBuilder: (context) {
                      return [
                        const PopupMenuItem(
                          value: 'bag',
                          child: ListTile(
                            leading: Icon(Icons.backpack_outlined),
                            title: Text('Add to Bag'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'png',
                          child: ListTile(
                            leading: Icon(Icons.image_outlined),
                            title: Text('Export PNG'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'merge-select',
                          child: ListTile(
                            leading: Icon(
                              selectedForMerge
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                            ),
                            title: Text(
                              selectedForMerge
                                  ? 'Remove from Merge'
                                  : 'Select for Merge',
                            ),
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          enabled: _layers.length > 1,
                          child: const Text('Delete'),
                        ),
                        if (currentGroup != null)
                          const PopupMenuItem(
                            value: 'ungroup',
                            child: Text('Remove from Group'),
                          ),
                        if (_layerGroups.isNotEmpty) const PopupMenuDivider(),
                        for (final group in _layerGroups)
                          PopupMenuItem(
                            value: 'group:${group.id}',
                            child: Row(
                              children: [
                                const Icon(Icons.folder_outlined, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    currentGroup?.id == group.id
                                        ? '${group.name} ✓'
                                        : group.name,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ];
                    },
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 10, 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 50,
                  child: Text('Opacity', style: TextStyle(fontSize: 11)),
                ),
                Expanded(
                  child: Slider(
                    value: layer.opacity,
                    min: 0,
                    max: 1,
                    onChanged: (value) {
                      _setLayerOpacity(index, value);
                    },
                  ),
                ),
                SizedBox(
                  width: 38,
                  child: Text(
                    '${(layer.opacity * 100).round()}%',
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferenceTransformWidget(
    ReferenceLayer reference,
    Widget child,
  ) {
    return Transform.translate(
      offset: Offset(reference.offsetX, reference.offsetY),
      child: Transform.rotate(
        angle: reference.rotation,
        alignment: Alignment.center,
        child: Transform.scale(
          scaleX: reference.scaleX,
          scaleY: reference.scaleY,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  Widget _buildActiveVideoReferenceWidget() {
    final reference = _activeReferenceLayer;
    final controller = _videoController;

    if (reference == null || controller == null) {
      return const SizedBox.shrink();
    }

    return _buildReferenceTransformWidget(
      reference,
      Opacity(
        opacity: reference.opacity,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }

  Widget _buildImageReferenceWidget(ReferenceLayer reference) {
    return _buildReferenceTransformWidget(
      reference,
      Opacity(
        opacity: reference.opacity,
        child: Image.file(
          File(reference.mediaPath),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    size: 48,
                    color: Colors.white54,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Reference image unavailable',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPerspectiveLoupe(BoxConstraints constraints) {
    final image = _perspectiveLoupeImage;
    final canvasPosition = _perspectiveLoupeCanvasPosition;
    final pointerPosition = _perspectiveLoupeScreenPosition;

    if (image == null || canvasPosition == null || pointerPosition == null) {
      return const SizedBox.shrink();
    }

    const loupeSize = 132.0;
    const loupeRadius = loupeSize / 2;
    const verticalOffset = 96.0;

    var centerX = pointerPosition.dx;
    var centerY = pointerPosition.dy - verticalOffset;

    // If there isn't enough room above the pointer, put the loupe below it.
    if (centerY - loupeRadius < 8) {
      centerY = pointerPosition.dy + verticalOffset;
    }

    centerX = centerX.clamp(
      loupeRadius + 8,
      math.max(loupeRadius + 8, constraints.maxWidth - loupeRadius - 8),
    );

    centerY = centerY.clamp(
      loupeRadius + 8,
      math.max(loupeRadius + 8, constraints.maxHeight - loupeRadius - 8),
    );

    return Positioned(
      left: centerX - loupeRadius,
      top: centerY - loupeRadius,
      width: loupeSize,
      height: loupeSize,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _PerspectiveLoupePainter(
            image: image,
            canvasPosition: canvasPosition,
            zoom: 3.5,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previousFrameStrokes = _getPreviousFrameStrokes();
    final nextFrameStrokes = _getNextFrameStrokes();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xCC121016),
                Color(0x66121016),
                Colors.transparent,
              ],
            ),
          ),
        ),
        title: Text(_projectName, overflow: TextOverflow.ellipsis),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Save Project',
            onPressed: _saveProject,
            icon: const Icon(Icons.save),
          ),
          IconButton(
            tooltip: _isExporting ? 'Exporting Animation' : 'Export Animation',
            onPressed: _isExporting ? null : _exportAnimation,
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.movie_creation_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrowToolbarLayout = constraints.maxWidth < 700;
                final isPortraitWorkspace =
                    constraints.maxHeight > constraints.maxWidth;

                final editToolbarExpanded =
                    _editToolbarExpanded ?? !isNarrowToolbarLayout;

                final canvasPadding = isPortraitWorkspace ? 0.0 : 16.0;

                return Stack(
                  key: _workspaceStackKey,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(canvasPadding),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: _canvasWidth,
                            height: _canvasHeight,
                            child: InteractiveViewer(
                              transformationController:
                                  _transformationController,
                              minScale: 0.5,
                              maxScale: 5.0,
                              panEnabled: false,
                              scaleEnabled: true,
                              child: Transform.rotate(
                                angle: _canvasRotation,
                                alignment: Alignment.center,
                                child: Builder(
                                  builder: (canvasContext) => Listener(
                                    onPointerDown: _isPlaying
                                        ? null
                                        : (event) => _handlePointerDown(
                                            event,
                                            canvasContext,
                                          ),
                                    onPointerMove: _isPlaying
                                        ? null
                                        : (event) => _handlePointerMove(
                                            event,
                                            canvasContext,
                                          ),
                                    onPointerUp: _isPlaying
                                        ? null
                                        : _handlePointerUp,
                                    onPointerCancel: _isPlaying
                                        ? null
                                        : _handlePointerCancel,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(24),
                                      child: RepaintBoundary(
                                        key: _canvasSampleKey,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            ColoredBox(
                                              color: _canvasBackgroundColor,
                                            ),
                                            if (_referenceMediaType ==
                                                    'video' &&
                                                _videoReady &&
                                                _videoController != null &&
                                                _activeReferenceLayer != null &&
                                                _activeReferenceLayer!.visible)
                                              _buildActiveVideoReferenceWidget(),
                                            for (final reference
                                                in _referenceLayers)
                                              if (reference.visible &&
                                                  reference.mediaType ==
                                                      'image' &&
                                                  reference
                                                      .mediaPath
                                                      .isNotEmpty)
                                                _buildImageReferenceWidget(
                                                  reference,
                                                ),
                                            CustomPaint(
                                              painter: AnimationCanvasPainter(
                                                strokes: <VectorStroke>[
                                                  ..._frames[_selectedFrameIndex],
                                                  ..._draftTextureStrokes,
                                                  ..._draftStampStrokes,
                                                ],
                                                currentStroke:
                                                    _draftStroke.isEmpty
                                                    ? null
                                                    : _draftStroke,
                                                previousOnionSkinStrokes:
                                                    _showOnionSkin
                                                    ? previousFrameStrokes
                                                    : const <VectorStroke>[],
                                                nextOnionSkinStrokes:
                                                    _showOnionSkin
                                                    ? nextFrameStrokes
                                                    : const <VectorStroke>[],
                                                strokeColor: _brushColor
                                                    .withValues(
                                                      alpha: _brushOpacity,
                                                    ),
                                                strokeWidth: _brushSize,
                                                brushType: _brushType,
                                                backgroundColor:
                                                    _canvasBackgroundColor,
                                                paintBackground:
                                                    _referenceMediaPath ==
                                                        null ||
                                                    (_referenceMediaType !=
                                                            'image' &&
                                                        _referenceMediaType !=
                                                            'video'),
                                                previousOnionSkinColor: Colors
                                                    .redAccent
                                                    .withValues(alpha: 0.40),
                                                nextOnionSkinColor: Colors
                                                    .greenAccent
                                                    .withValues(alpha: 0.40),
                                              ),
                                              child: const SizedBox.expand(),
                                            ),
                                            if (_fillLassoPoints.length > 1)
                                              IgnorePointer(
                                                child: CustomPaint(
                                                  painter: _FillLassoPainter(
                                                    points: _fillLassoPoints,
                                                    color: _brushColor,
                                                  ),
                                                  child:
                                                      const SizedBox.expand(),
                                                ),
                                              ),
                                            if (_draftShapeStrokes.isNotEmpty)
                                              IgnorePointer(
                                                child: CustomPaint(
                                                  painter: AnimationCanvasPainter(
                                                    strokes: _draftShapeStrokes,
                                                    currentStroke: null,
                                                    previousOnionSkinStrokes:
                                                        const <VectorStroke>[],
                                                    nextOnionSkinStrokes:
                                                        const <VectorStroke>[],
                                                    strokeColor: _brushColor,
                                                    previousOnionSkinColor:
                                                        Colors.transparent,
                                                    nextOnionSkinColor:
                                                        Colors.transparent,
                                                    strokeWidth: _brushSize,
                                                    brushType:
                                                        StrokeBrushType.solid,
                                                    backgroundColor:
                                                        _canvasBackgroundColor,
                                                    paintBackground: false,
                                                  ),
                                                  child:
                                                      const SizedBox.expand(),
                                                ),
                                              ),
                                            if (_perspectiveShapeEditing &&
                                                _perspectiveShapeCorners
                                                        .length ==
                                                    4)
                                              IgnorePointer(
                                                child: CustomPaint(
                                                  painter:
                                                      _PerspectiveShapeHandlesPainter(
                                                        corners:
                                                            _perspectiveShapeCorners,
                                                      ),
                                                  child:
                                                      const SizedBox.expand(),
                                                ),
                                              ),
                                            if (_isTransformActive)
                                              IgnorePointer(
                                                child: CustomPaint(
                                                  painter: _TransformOverlayPainter(
                                                    lassoPoints: _lassoPoints,
                                                    selectionBounds:
                                                        _transformSelectionBounds(),
                                                    pivot: _transformPivot,
                                                  ),
                                                  child:
                                                      const SizedBox.expand(),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_perspectiveLoupeImage != null &&
                        _perspectiveLoupeCanvasPosition != null &&
                        _perspectiveLoupeScreenPosition != null &&
                        _perspectiveDraggingCorner != null)
                      _buildPerspectiveLoupe(constraints),
                    if (!_isVideoScrubbing)
                      Positioned(
                        top: 78,
                        left: 16,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Material(
                              elevation: 8,
                              color: const Color(0xE61A1720),
                              borderRadius: BorderRadius.circular(16),
                              clipBehavior: Clip.antiAlias,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 6,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Undo',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: _undo,
                                      icon: const Icon(Icons.undo),
                                    ),
                                    const SizedBox(height: 2),
                                    IconButton(
                                      tooltip: 'Redo',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: _redo,
                                      icon: const Icon(Icons.redo),
                                    ),
                                    if (_drawingMode) ...[
                                      const SizedBox(height: 2),
                                      IconButton(
                                        tooltip: _isPlaying
                                            ? 'Pause Animation'
                                            : 'Play Animation',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: _togglePlayback,
                                        icon: Icon(
                                          _isPlaying
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          color: _isPlaying
                                              ? Colors.deepPurpleAccent
                                              : Colors.white70,
                                        ),
                                      ),
                                    ],

                                    const SizedBox(height: 2),
                                    IconButton(
                                      tooltip: _drawingExpanded
                                          ? 'Hide Pen'
                                          : 'Show Pen',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () {
                                        setState(() {
                                          _drawingExpanded = !_drawingExpanded;
                                        });
                                      },
                                      icon: Icon(
                                        Icons.edit,
                                        color: _drawingExpanded
                                            ? Colors.deepPurpleAccent
                                            : Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    if (_drawingMode &&
                                        _referenceMediaType == 'video' &&
                                        _videoReady) ...[
                                      const SizedBox(height: 2),
                                      IconButton(
                                        tooltip: 'Find Next Pose',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: _findNextReferencePose,
                                        icon: const Icon(Icons.search),
                                      ),
                                    ],

                                    if (_drawingMode) ...[
                                      const SizedBox(height: 2),
                                      IconButton(
                                        tooltip: _blendExpanded
                                            ? 'Hide Blend'
                                            : 'Show Blend',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          setState(() {
                                            if (!_blendExpanded) {
                                              _blendExpanded = true;
                                              _blendSamplingArmed = true;
                                              _blendBaseColor = _brushColor;
                                            } else if (!_blendSamplingArmed) {
                                              _blendSamplingArmed = true;
                                              _blendBaseColor = _brushColor;
                                            } else {
                                              _blendExpanded = false;
                                              _blendSamplingArmed = false;
                                            }
                                          });
                                        },
                                        icon: Icon(
                                          Icons.blur_on,
                                          color: _blendExpanded
                                              ? Colors.deepPurpleAccent
                                              : Colors.white70,
                                        ),
                                      ),

                                      const SizedBox(height: 2),
                                      IconButton(
                                        tooltip: _textureExpanded
                                            ? 'Hide Texture'
                                            : 'Show Texture',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          setState(() {
                                            _textureExpanded =
                                                !_textureExpanded;
                                            _textureActive = _textureExpanded;

                                            if (_textureExpanded) {
                                              _stampBrushActive = false;
                                              _stampBrushItem = null;
                                              _blendSamplingArmed = false;
                                            } else {
                                              _draftTextureStrokes =
                                                  <VectorStroke>[];
                                            }
                                          });
                                        },
                                        icon: Icon(
                                          Icons.grid_on_outlined,
                                          color: _textureExpanded
                                              ? Colors.deepPurpleAccent
                                              : Colors.white70,
                                        ),
                                      ),

                                      const SizedBox(height: 2),
                                      IconButton(
                                        tooltip: 'Open Bag',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: _openBag,
                                        icon: const Icon(
                                          Icons.backpack_outlined,
                                          color: Colors.white70,
                                        ),
                                      ),

                                      const SizedBox(height: 2),

                                      IconButton(
                                        tooltip: _stampBrushActive
                                            ? 'Stamp Brush: ${_stampBrushItem?.name ?? ''}'
                                            : 'Stamp Brush',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          if (_stampBrushActive &&
                                              !_stampBrushPanelExpanded) {
                                            setState(() {
                                              _stampBrushPanelExpanded = true;
                                            });
                                            return;
                                          }

                                          _openStampBrushPicker();
                                        },
                                        icon: Icon(
                                          Icons.content_copy,
                                          color: _stampBrushActive
                                              ? Colors.deepPurpleAccent
                                              : Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            IconButton(
                              tooltip: _drawingMode
                                  ? 'Return to Animation Mode'
                                  : 'Enter Drawing Mode',
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() {
                                  _drawingMode = !_drawingMode;

                                  if (_drawingMode) {
                                    _timingExpanded = false;
                                    _timelineExpanded = false;
                                    _transformToolbarExpanded = false;
                                  } else {
                                    _blendExpanded = false;
                                    _blendSamplingArmed = false;
                                  }
                                });
                              },
                              icon: Icon(
                                _drawingMode
                                    ? Icons.animation
                                    : Icons.draw_outlined,
                                color: _drawingMode
                                    ? Colors.cyanAccent
                                    : Colors.white70,
                              ),
                            ),

                            if (_drawingExpanded ||
                                (_drawingMode && _blendExpanded) ||
                                (_drawingMode &&
                                    _stampBrushActive &&
                                    _stampBrushPanelExpanded)) ...[
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight:
                                      constraints.maxHeight -
                                      110 -
                                      MediaQuery.of(context).viewPadding.bottom,
                                ),
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (_drawingMode &&
                                          _stampBrushActive &&
                                          _stampBrushPanelExpanded)
                                        Material(
                                          elevation: 8,
                                          color: const Color(0xE61A1720),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: SizedBox(
                                            width: constraints.maxWidth < 420
                                                ? constraints.maxWidth - 96
                                                : 300,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    14,
                                                    12,
                                                    14,
                                                    12,
                                                  ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Row(
                                                    children: [
                                                      const Expanded(
                                                        child: Text(
                                                          'Stamp',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                      Flexible(
                                                        child: Text(
                                                          _stampBrushItem
                                                                  ?.name ??
                                                              'Bag Asset',
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                color: Colors
                                                                    .white60,
                                                              ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      IconButton(
                                                        tooltip:
                                                            'Hide Stamp Controls',
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        onPressed: () {
                                                          setState(() {
                                                            _stampBrushPanelExpanded =
                                                                false;
                                                          });
                                                        },
                                                        icon: const Icon(
                                                          Icons
                                                              .keyboard_arrow_left,
                                                          size: 20,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 10),
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Scale'),
                                                      ),
                                                      Expanded(
                                                        child: Slider(
                                                          value:
                                                              _stampBrushScale,
                                                          min: 0.1,
                                                          max: 3.0,
                                                          divisions: 29,
                                                          label:
                                                              '${(_stampBrushScale * 100).round()}%',
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _stampBrushScale =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 46,
                                                        child: Text(
                                                          '${(_stampBrushScale * 100).round()}%',
                                                          textAlign:
                                                              TextAlign.right,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Spacing'),
                                                      ),
                                                      Expanded(
                                                        child: Slider(
                                                          value:
                                                              _stampBrushSpacing,
                                                          min: 20,
                                                          max: 400,
                                                          divisions: 38,
                                                          label:
                                                              _stampBrushSpacing
                                                                  .round()
                                                                  .toString(),
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _stampBrushSpacing =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 46,
                                                        child: Text(
                                                          _stampBrushSpacing
                                                              .round()
                                                              .toString(),
                                                          textAlign:
                                                              TextAlign.right,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Rotation'),
                                                      ),
                                                      Expanded(
                                                        child: Slider(
                                                          value:
                                                              _stampBrushRotation,
                                                          min: -180,
                                                          max: 180,
                                                          divisions: 72,
                                                          label:
                                                              '${_stampBrushRotation.round()}°',
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _stampBrushRotation =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 46,
                                                        child: Text(
                                                          '${_stampBrushRotation.round()}°',
                                                          textAlign:
                                                              TextAlign.right,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Random'),
                                                      ),
                                                      Expanded(
                                                        child: Slider(
                                                          value:
                                                              _stampBrushRandomRotation,
                                                          min: 0,
                                                          max: 180,
                                                          divisions: 36,
                                                          label:
                                                              '±${_stampBrushRandomRotation.round()}°',
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _stampBrushRandomRotation =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 46,
                                                        child: Text(
                                                          '±${_stampBrushRandomRotation.round()}°',
                                                          textAlign:
                                                              TextAlign.right,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Scatter'),
                                                      ),
                                                      Expanded(
                                                        child: Slider(
                                                          value:
                                                              _stampBrushScatter,
                                                          min: 0,
                                                          max: 300,
                                                          divisions: 30,
                                                          label:
                                                              _stampBrushScatter
                                                                  .round()
                                                                  .toString(),
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _stampBrushScatter =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 46,
                                                        child: Text(
                                                          _stampBrushScatter
                                                              .round()
                                                              .toString(),
                                                          textAlign:
                                                              TextAlign.right,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),

                                      if (_drawingMode &&
                                          _stampBrushActive &&
                                          _textureExpanded)
                                        const SizedBox(height: 8),

                                      if (_drawingMode && _textureExpanded)
                                        Material(
                                          elevation: 8,
                                          color: const Color(0xE61A1720),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: SizedBox(
                                            width: constraints.maxWidth < 420
                                                ? constraints.maxWidth - 96
                                                : 300,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    14,
                                                    12,
                                                    14,
                                                    12,
                                                  ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Text(
                                                      'Texture',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),

                                                  SegmentedButton<String>(
                                                    segments: const [
                                                      ButtonSegment<String>(
                                                        value: 'stipple',
                                                        label: Text('Stipple'),
                                                      ),
                                                      ButtonSegment<String>(
                                                        value: 'hatch',
                                                        label: Text('Hatch'),
                                                      ),
                                                      ButtonSegment<String>(
                                                        value: 'grain',
                                                        label: Text('Grain'),
                                                      ),
                                                    ],
                                                    selected: <String>{
                                                      _texturePattern,
                                                    },
                                                    onSelectionChanged:
                                                        (selection) {
                                                          setState(() {
                                                            _texturePattern =
                                                                selection.first;
                                                          });
                                                        },
                                                  ),

                                                  const SizedBox(height: 10),

                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Scale'),
                                                      ),
                                                      Expanded(
                                                        child: Slider(
                                                          value: _textureScale,
                                                          min: 2,
                                                          max: 30,
                                                          divisions: 28,
                                                          label: _textureScale
                                                              .round()
                                                              .toString(),
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _textureScale =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 38,
                                                        child: Text(
                                                          _textureScale
                                                              .round()
                                                              .toString(),
                                                          textAlign:
                                                              TextAlign.right,
                                                        ),
                                                      ),
                                                    ],
                                                  ),

                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Density'),
                                                      ),
                                                      Expanded(
                                                        child: Slider(
                                                          value:
                                                              _textureDensity,
                                                          min: 0.1,
                                                          max: 1.0,
                                                          divisions: 9,
                                                          label:
                                                              '${(_textureDensity * 100).round()}%',
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _textureDensity =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 40,
                                                        child: Text(
                                                          '${(_textureDensity * 100).round()}%',
                                                          textAlign:
                                                              TextAlign.right,
                                                        ),
                                                      ),
                                                    ],
                                                  ),

                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Scatter'),
                                                      ),
                                                      Expanded(
                                                        child: Slider(
                                                          value:
                                                              _textureScatter,
                                                          min: 0,
                                                          max: 50,
                                                          divisions: 25,
                                                          label: _textureScatter
                                                              .round()
                                                              .toString(),
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _textureScatter =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 40,
                                                        child: Text(
                                                          _textureScatter
                                                              .round()
                                                              .toString(),
                                                          textAlign:
                                                              TextAlign.right,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),

                                      if (_drawingMode &&
                                          _textureExpanded &&
                                          _blendExpanded)
                                        const SizedBox(height: 8),

                                      if (_drawingMode && _blendExpanded)
                                        Material(
                                          elevation: 8,
                                          color: const Color(0xE61A1720),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: SizedBox(
                                            width: constraints.maxWidth < 420
                                                ? constraints.maxWidth - 96
                                                : 300,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    14,
                                                    12,
                                                    14,
                                                    12,
                                                  ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Row(
                                                    children: [
                                                      const Expanded(
                                                        child: Text(
                                                          'Blend',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                      if (_blendSamplingArmed)
                                                        const Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              Icons.colorize,
                                                              size: 16,
                                                              color: Colors
                                                                  .cyanAccent,
                                                            ),
                                                            SizedBox(width: 4),
                                                            Text(
                                                              'Tap canvas',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Colors
                                                                    .cyanAccent,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 12),

                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Base'),
                                                      ),
                                                      Container(
                                                        width: 50,
                                                        height: 30,
                                                        decoration: BoxDecoration(
                                                          color:
                                                              _blendBaseColor,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                9,
                                                              ),
                                                          border: Border.all(
                                                            color:
                                                                Colors.white38,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          '#${_colorHex(_blendBaseColor)}',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 10,
                                                                color: Colors
                                                                    .white60,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),

                                                  const SizedBox(height: 8),

                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Sample'),
                                                      ),
                                                      Container(
                                                        width: 50,
                                                        height: 30,
                                                        decoration: BoxDecoration(
                                                          color:
                                                              _blendSampleColor,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                9,
                                                              ),
                                                          border: Border.all(
                                                            color:
                                                                Colors.white38,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          '#${_colorHex(_blendSampleColor)}',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 10,
                                                                color: Colors
                                                                    .white60,
                                                              ),
                                                        ),
                                                      ),
                                                      IconButton(
                                                        tooltip: 'Sample Again',
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        onPressed: () {
                                                          setState(() {
                                                            _blendBaseColor =
                                                                _brushColor;
                                                            _blendSamplingArmed =
                                                                true;
                                                          });
                                                        },
                                                        icon: Icon(
                                                          Icons.colorize,
                                                          size: 18,
                                                          color:
                                                              _blendSamplingArmed
                                                              ? Colors
                                                                    .cyanAccent
                                                              : Colors.white70,
                                                        ),
                                                      ),
                                                    ],
                                                  ),

                                                  const SizedBox(height: 10),

                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Strength'),
                                                      ),
                                                      Expanded(
                                                        child: Slider(
                                                          value: _blendAmount,
                                                          min: 0,
                                                          max: 1,
                                                          divisions: 20,
                                                          label:
                                                              '${(_blendAmount * 100).round()}%',
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _blendAmount =
                                                                  value;
                                                              _applyCurrentBlend();
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 40,
                                                        child: Text(
                                                          '${(_blendAmount * 100).round()}%',
                                                          textAlign:
                                                              TextAlign.right,
                                                        ),
                                                      ),
                                                    ],
                                                  ),

                                                  const SizedBox(height: 8),

                                                  Builder(
                                                    builder: (context) {
                                                      final mixedColor =
                                                          _currentBlendColor();

                                                      return Row(
                                                        children: [
                                                          const SizedBox(
                                                            width: 70,
                                                            child: Text(
                                                              'Result',
                                                            ),
                                                          ),
                                                          Expanded(
                                                            child: Container(
                                                              height: 34,
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    mixedColor,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      10,
                                                                    ),
                                                                border: Border.all(
                                                                  color: Colors
                                                                      .white24,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Text(
                                                            '#${_colorHex(mixedColor)}',
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .white60,
                                                                ),
                                                          ),
                                                        ],
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),

                                      if (_drawingMode &&
                                          _blendExpanded &&
                                          _drawingExpanded)
                                        const SizedBox(height: 8),

                                      if (_drawingExpanded)
                                        Material(
                                          elevation: 8,
                                          color: const Color(0xE61A1720),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: SizedBox(
                                            width: constraints.maxWidth < 420
                                                ? constraints.maxWidth - 96
                                                : 300,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    14,
                                                    10,
                                                    14,
                                                    12,
                                                  ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Presets'),
                                                      ),
                                                      Expanded(
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            IconButton(
                                                              tooltip:
                                                                  'Open Brush Presets',
                                                              visualDensity:
                                                                  VisualDensity
                                                                      .compact,
                                                              onPressed:
                                                                  _openBrushPresets,
                                                              icon: const Icon(
                                                                Icons
                                                                    .folder_open_outlined,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            IconButton(
                                                              tooltip:
                                                                  'Save Current Brush',
                                                              visualDensity:
                                                                  VisualDensity
                                                                      .compact,
                                                              onPressed:
                                                                  _saveCurrentBrushPreset,
                                                              icon: const Icon(
                                                                Icons
                                                                    .save_outlined,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),

                                                  const SizedBox(height: 8),

                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Type'),
                                                      ),
                                                      Expanded(
                                                        child: SegmentedButton<StrokeBrushType>(
                                                          segments: const [
                                                            ButtonSegment<
                                                              StrokeBrushType
                                                            >(
                                                              value:
                                                                  StrokeBrushType
                                                                      .solid,
                                                              label: Text(
                                                                'Solid',
                                                              ),
                                                            ),
                                                            ButtonSegment<
                                                              StrokeBrushType
                                                            >(
                                                              value:
                                                                  StrokeBrushType
                                                                      .pressure,
                                                              label: Text(
                                                                'Pressure',
                                                              ),
                                                            ),
                                                          ],
                                                          selected:
                                                              <StrokeBrushType>{
                                                                _brushType,
                                                              },
                                                          onSelectionChanged:
                                                              (selection) {
                                                                setState(() {
                                                                  _brushType =
                                                                      selection
                                                                          .first;
                                                                });
                                                              },
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Size'),
                                                      ),
                                                      Expanded(
                                                        child: Slider(
                                                          value: _brushSize,
                                                          min: 1,
                                                          max: 20,
                                                          divisions: 19,
                                                          label: _brushSize
                                                              .toStringAsFixed(
                                                                0,
                                                              ),
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _brushSize =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 28,
                                                        child: Text(
                                                          _brushSize
                                                              .toStringAsFixed(
                                                                0,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text(
                                                          'Stabiliser',
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Slider(
                                                          value:
                                                              _stabilizerStrength,
                                                          min: 0,
                                                          max: 0.9,
                                                          divisions: 9,
                                                          label:
                                                              '${(_stabilizerStrength * 100).round()}%',
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _stabilizerStrength =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 40,
                                                        child: Text(
                                                          '${(_stabilizerStrength * 100).round()}%',
                                                          textAlign:
                                                              TextAlign.right,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Pull'),
                                                      ),
                                                      Expanded(
                                                        child: Slider(
                                                          value:
                                                              _stabilizerPullDistance,
                                                          min: 0,
                                                          max: 40,
                                                          divisions: 20,
                                                          label:
                                                              '${_stabilizerPullDistance.round()} px',
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _stabilizerPullDistance =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 40,
                                                        child: Text(
                                                          '${_stabilizerPullDistance.round()}',
                                                          textAlign:
                                                              TextAlign.right,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),

                                                  // Brush opacity.
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Opacity'),
                                                      ),
                                                      Expanded(
                                                        child: Slider(
                                                          value: _brushOpacity,
                                                          min: 0.05,
                                                          max: 1.0,
                                                          divisions: 19,
                                                          label:
                                                              '${(_brushOpacity * 100).round()}%',
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _brushOpacity =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 40,
                                                        child: Text(
                                                          '${(_brushOpacity * 100).round()}%',
                                                          textAlign:
                                                              TextAlign.right,
                                                        ),
                                                      ),
                                                    ],
                                                  ),

                                                  const SizedBox(height: 8),

                                                  // Current brush colour.
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Colour'),
                                                      ),
                                                      Expanded(
                                                        child: Align(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child: Tooltip(
                                                            message:
                                                                'Choose Brush Colour',
                                                            child: InkWell(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                              onTap: () async {
                                                                final color =
                                                                    await _showColourPicker(
                                                                      _brushColor,
                                                                      title:
                                                                          'Brush Colour',
                                                                    );

                                                                if (color ==
                                                                        null ||
                                                                    !mounted) {
                                                                  return;
                                                                }

                                                                setState(() {
                                                                  _brushColor =
                                                                      color;
                                                                  _rememberRecentColor(
                                                                    color,
                                                                  );
                                                                });
                                                              },
                                                              child: Container(
                                                                width: 72,
                                                                height: 38,
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                      _brushColor,
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        12,
                                                                      ),
                                                                  border: Border.all(
                                                                    color: Colors
                                                                        .deepPurpleAccent,
                                                                    width: 2,
                                                                  ),
                                                                ),
                                                                child: Icon(
                                                                  Icons
                                                                      .palette_outlined,
                                                                  color:
                                                                      _brushColor
                                                                              .computeLuminance() >
                                                                          0.55
                                                                      ? Colors
                                                                            .black87
                                                                      : Colors
                                                                            .white,
                                                                  size: 19,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      Tooltip(
                                                        message:
                                                            'Visual Colour Picker',
                                                        child: IconButton(
                                                          tooltip:
                                                              'Visual Colour Picker',
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                          onPressed: () async {
                                                            final color =
                                                                await _showRadialColourPicker(
                                                                  _brushColor,
                                                                );

                                                            if (color == null ||
                                                                !mounted) {
                                                              return;
                                                            }

                                                            setState(() {
                                                              _brushColor =
                                                                  color;
                                                              _rememberRecentColor(
                                                                color,
                                                              );
                                                            });
                                                          },
                                                          icon: const Icon(
                                                            Icons
                                                                .color_lens_outlined,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        '#${_colorHex(_brushColor)}',
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          color: Colors.white60,
                                                        ),
                                                      ),
                                                    ],
                                                  ),

                                                  if (_recentColors
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      children: [
                                                        const SizedBox(
                                                          width: 70,
                                                          child: Text('Recent'),
                                                        ),
                                                        Expanded(
                                                          child: Wrap(
                                                            spacing: 7,
                                                            runSpacing: 7,
                                                            children: [
                                                              for (final color
                                                                  in _recentColors)
                                                                GestureDetector(
                                                                  onTap: () {
                                                                    setState(() {
                                                                      _brushColor =
                                                                          color;
                                                                      _rememberRecentColor(
                                                                        color,
                                                                      );
                                                                    });
                                                                  },
                                                                  child: Container(
                                                                    width: 24,
                                                                    height: 24,
                                                                    decoration: BoxDecoration(
                                                                      color:
                                                                          color,
                                                                      shape: BoxShape
                                                                          .circle,
                                                                      border: Border.all(
                                                                        color:
                                                                            _brushColor ==
                                                                                color
                                                                            ? Colors.deepPurpleAccent
                                                                            : Colors.white38,
                                                                        width:
                                                                            _brushColor ==
                                                                                color
                                                                            ? 3
                                                                            : 2,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],

                                                  const SizedBox(height: 10),
                                                  const Divider(height: 1),
                                                  const SizedBox(height: 8),

                                                  // Canvas colour remains available,
                                                  // but no longer occupies a huge grid.
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 70,
                                                        child: Text('Canvas'),
                                                      ),
                                                      Expanded(
                                                        child: Align(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child: Tooltip(
                                                            message:
                                                                'Choose Canvas Colour',
                                                            child: InkWell(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                              onTap: () async {
                                                                final color =
                                                                    await _showColourPicker(
                                                                      _canvasBackgroundColor,
                                                                      title:
                                                                          'Canvas Background',
                                                                    );

                                                                if (color ==
                                                                        null ||
                                                                    !mounted) {
                                                                  return;
                                                                }

                                                                setState(() {
                                                                  _canvasBackgroundColor =
                                                                      color;
                                                                });

                                                                _scheduleAutosave();
                                                              },
                                                              child: Container(
                                                                width: 72,
                                                                height: 38,
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                      _canvasBackgroundColor,
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        12,
                                                                      ),
                                                                  border: Border.all(
                                                                    color: Colors
                                                                        .white38,
                                                                    width: 2,
                                                                  ),
                                                                ),
                                                                child: const Icon(
                                                                  Icons
                                                                      .format_color_fill,
                                                                  size: 19,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      Text(
                                                        '#${_colorHex(_canvasBackgroundColor)}',
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          color: Colors.white60,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                    Positioned(
                      right: 16,
                      bottom: 96,
                      child: Material(
                        elevation: 8,
                        color: const Color(0xE61A1720),
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (_layersPanelExpanded) ...[
                                if (!_isVideoScrubbing)
                                  SizedBox(
                                    width: 300,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        8,
                                        8,
                                        4,
                                      ),
                                      child: Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'Layers',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip:
                                                _mergeSelectedLayerIds.length >=
                                                    2
                                                ? 'Merge Selected Layers'
                                                : 'Select 2+ layers to merge',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed:
                                                _isPlaying ||
                                                    _mergeSelectedLayerIds
                                                            .length <
                                                        2
                                                ? null
                                                : _mergeSelectedDrawingLayers,
                                            icon: Badge(
                                              isLabelVisible:
                                                  _mergeSelectedLayerIds
                                                      .isNotEmpty,
                                              label: Text(
                                                '${_mergeSelectedLayerIds.length}',
                                              ),
                                              child: const Icon(
                                                Icons.merge_type,
                                              ),
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            tooltip: 'Add Reference',
                                            enabled: !_isPlaying,
                                            icon: const Icon(
                                              Icons.perm_media_outlined,
                                            ),
                                            onSelected: (value) {
                                              if (value == 'image') {
                                                unawaited(
                                                  _addReferenceLayer('image'),
                                                );
                                              } else if (value == 'video') {
                                                unawaited(
                                                  _addReferenceLayer('video'),
                                                );
                                              }
                                            },
                                            itemBuilder: (context) => const [
                                              PopupMenuItem<String>(
                                                value: 'image',
                                                child: ListTile(
                                                  dense: true,
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  leading: Icon(
                                                    Icons.image_outlined,
                                                  ),
                                                  title: Text(
                                                    'Add Image Reference',
                                                  ),
                                                ),
                                              ),
                                              PopupMenuItem<String>(
                                                value: 'video',
                                                child: ListTile(
                                                  dense: true,
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  leading: Icon(
                                                    Icons.movie_outlined,
                                                  ),
                                                  title: Text(
                                                    'Add Video Reference',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          IconButton(
                                            tooltip: 'Add Layer Group',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: _isPlaying
                                                ? null
                                                : _addLayerGroup,
                                            icon: const Icon(
                                              Icons.create_new_folder_outlined,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Add Drawing Layer',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: _isPlaying
                                                ? null
                                                : _addDrawingLayer,
                                            icon: const Icon(Icons.add),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (!_isVideoScrubbing)
                                  const Divider(height: 1),

                                SizedBox(
                                  width: 300,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 300,
                                    ),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!_isVideoScrubbing)
                                            ..._buildLayerPanelEntries(),

                                          if (_referenceMediaType == 'video' &&
                                              _videoReady &&
                                              _videoController != null) ...[
                                            if (!_isVideoScrubbing)
                                              const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  vertical: 5,
                                                ),
                                                child: Divider(height: 1),
                                              ),
                                            Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    4,
                                                    2,
                                                    4,
                                                    4,
                                                  ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.white12,
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (_referenceMediaType ==
                                                          'video' &&
                                                      _videoReady &&
                                                      _videoController != null)
                                                    ValueListenableBuilder<
                                                      VideoPlayerValue
                                                    >(
                                                      valueListenable:
                                                          _videoController!,
                                                      builder:
                                                          (
                                                            context,
                                                            videoValue,
                                                            child,
                                                          ) {
                                                            final durationMs =
                                                                videoValue
                                                                    .duration
                                                                    .inMilliseconds;

                                                            final maxMs = math
                                                                .max(
                                                                  1,
                                                                  durationMs,
                                                                )
                                                                .toDouble();

                                                            final livePositionMs =
                                                                _isVideoScrubbing
                                                                ? _videoScrubPositionMs
                                                                : videoValue
                                                                      .position
                                                                      .inMilliseconds
                                                                      .toDouble();

                                                            final sliderValue =
                                                                livePositionMs
                                                                    .clamp(
                                                                      0.0,
                                                                      maxMs,
                                                                    );

                                                            return Padding(
                                                              padding:
                                                                  const EdgeInsets.fromLTRB(
                                                                    12,
                                                                    0,
                                                                    10,
                                                                    8,
                                                                  ),
                                                              child: Column(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  Row(
                                                                    children: [
                                                                      const SizedBox(
                                                                        width:
                                                                            50,
                                                                        child: Text(
                                                                          'Video',
                                                                          style: TextStyle(
                                                                            fontSize:
                                                                                11,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      IconButton(
                                                                        tooltip:
                                                                            'Previous Video Frame',
                                                                        visualDensity:
                                                                            VisualDensity.compact,
                                                                        onPressed: () {
                                                                          unawaited(
                                                                            _stepReferenceVideo(
                                                                              -1,
                                                                            ),
                                                                          );
                                                                        },
                                                                        icon: const Icon(
                                                                          Icons
                                                                              .chevron_left,
                                                                          size:
                                                                              18,
                                                                        ),
                                                                      ),
                                                                      Expanded(
                                                                        child: Slider(
                                                                          value:
                                                                              sliderValue,
                                                                          min:
                                                                              0,
                                                                          max:
                                                                              maxMs,
                                                                          onChangeStart:
                                                                              (
                                                                                value,
                                                                              ) async {
                                                                                final controller = _videoController;

                                                                                if (controller !=
                                                                                        null &&
                                                                                    controller.value.isPlaying) {
                                                                                  await controller.pause();
                                                                                }

                                                                                if (!mounted) {
                                                                                  return;
                                                                                }

                                                                                setState(() {
                                                                                  _isVideoScrubbing = true;
                                                                                  _videoScrubPositionMs = value;
                                                                                  _videoScrubDragStartMs = value;
                                                                                  _videoScrubDragStartSliderMs = value;
                                                                                });
                                                                              },
                                                                          onChanged:
                                                                              (
                                                                                value,
                                                                              ) {
                                                                                final dampedValue =
                                                                                    (_videoScrubDragStartMs +
                                                                                            ((value -
                                                                                                    _videoScrubDragStartSliderMs) *
                                                                                                0.75))
                                                                                        .clamp(
                                                                                          0.0,
                                                                                          maxMs,
                                                                                        );

                                                                                setState(() {
                                                                                  _videoScrubPositionMs = dampedValue;
                                                                                });

                                                                                unawaited(
                                                                                  _seekReferenceVideoToMs(
                                                                                    dampedValue,
                                                                                  ),
                                                                                );
                                                                              },
                                                                          onChangeEnd:
                                                                              (
                                                                                value,
                                                                              ) {
                                                                                setState(() {
                                                                                  _isVideoScrubbing = false;
                                                                                  _videoScrubPositionMs = value;
                                                                                });

                                                                                unawaited(
                                                                                  _seekReferenceVideoToMs(
                                                                                    value,
                                                                                  ),
                                                                                );
                                                                              },
                                                                        ),
                                                                      ),
                                                                      IconButton(
                                                                        tooltip:
                                                                            'Capture Pose & Draw',
                                                                        visualDensity:
                                                                            VisualDensity.compact,
                                                                        onPressed:
                                                                            _isPlaying
                                                                            ? null
                                                                            : _captureReferencePose,
                                                                        icon: const Icon(
                                                                          Icons
                                                                              .add_a_photo_outlined,
                                                                          size:
                                                                              18,
                                                                        ),
                                                                      ),
                                                                      IconButton(
                                                                        tooltip:
                                                                            'Next Video Frame',
                                                                        visualDensity:
                                                                            VisualDensity.compact,
                                                                        onPressed: () {
                                                                          unawaited(
                                                                            _stepReferenceVideo(
                                                                              1,
                                                                            ),
                                                                          );
                                                                        },
                                                                        icon: const Icon(
                                                                          Icons
                                                                              .chevron_right,
                                                                          size:
                                                                              18,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  Row(
                                                                    children: [
                                                                      const SizedBox(
                                                                        width:
                                                                            50,
                                                                      ),
                                                                      Text(
                                                                        _formatVideoTime(
                                                                          Duration(
                                                                            milliseconds:
                                                                                sliderValue.round(),
                                                                          ),
                                                                        ),
                                                                        style: const TextStyle(
                                                                          fontSize:
                                                                              9,
                                                                          color:
                                                                              Colors.white60,
                                                                        ),
                                                                      ),
                                                                      const Spacer(),
                                                                      Text(
                                                                        _formatVideoTime(
                                                                          videoValue
                                                                              .duration,
                                                                        ),
                                                                        style: const TextStyle(
                                                                          fontSize:
                                                                              9,
                                                                          color:
                                                                              Colors.white60,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          },
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              IconButton(
                                tooltip: _layersPanelExpanded
                                    ? 'Hide Layers'
                                    : 'Show Layers',
                                onPressed: () {
                                  setState(() {
                                    _layersPanelExpanded =
                                        !_layersPanelExpanded;
                                  });
                                },
                                icon: Icon(
                                  Icons.layers_outlined,
                                  color: _layersPanelExpanded
                                      ? Colors.deepPurpleAccent
                                      : Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    if (!_isVideoScrubbing)
                      Positioned(
                        top:
                            MediaQuery.of(context).viewPadding.top +
                            kToolbarHeight +
                            8,
                        right: 16,
                        child: Material(
                          elevation: 8,
                          color: const Color(0xE61A1720),
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (editToolbarExpanded) ...[
                                  IconButton(
                                    tooltip: 'Reset View',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _resetCanvasView,
                                    icon: const Icon(Icons.center_focus_strong),
                                  ),
                                  IconButton(
                                    tooltip: 'Eraser',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      setState(() {
                                        _isEraserActive = !_isEraserActive;
                                        _isTintToolActive = false;
                                        _isFillToolActive = false;
                                        _clearFillLasso();
                                        _isShapeToolActive = false;
                                        _clearShapeDraft();
                                        _isTransformActive = false;
                                        _clearTransformSelection();
                                      });
                                    },
                                    icon: Icon(
                                      Icons.auto_fix_off,
                                      color: _isEraserActive
                                          ? Colors.deepPurpleAccent
                                          : Colors.white70,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip:
                                        'Tint Brush · Size = reach · Opacity = strength',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _isPlaying
                                        ? null
                                        : () {
                                            setState(() {
                                              final alreadyActive =
                                                  _isTintToolActive &&
                                                  !_isSolidRecolourMode;

                                              _isTintToolActive =
                                                  !alreadyActive;
                                              _isSolidRecolourMode = false;

                                              _isEraserActive = false;
                                              _isFillToolActive = false;
                                              _isShapeToolActive = false;
                                              _isTransformActive = false;

                                              _textureActive = false;
                                              _stampBrushActive = false;
                                              _stampBrushItem = null;
                                              _blendSamplingArmed = false;

                                              _draftStroke =
                                                  const <VectorPoint>[];
                                              _draftTextureStrokes =
                                                  <VectorStroke>[];
                                              _draftStampStrokes =
                                                  <VectorStroke>[];

                                              _tintTouchedStrokeIndices.clear();
                                              _tintGestureChanged = false;
                                              _tintGestureUndoCaptured = false;

                                              _clearFillLasso();
                                              _clearShapeDraft();
                                              _clearTransformSelection();
                                            });
                                          },
                                    icon: Icon(
                                      Icons.format_paint_outlined,
                                      color:
                                          _isTintToolActive &&
                                              !_isSolidRecolourMode
                                          ? Colors.deepPurpleAccent
                                          : Colors.white70,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip:
                                        'Recolour Stroke · Replace full colour',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _isPlaying
                                        ? null
                                        : () {
                                            setState(() {
                                              final alreadyActive =
                                                  _isTintToolActive &&
                                                  _isSolidRecolourMode;

                                              _isTintToolActive =
                                                  !alreadyActive;
                                              _isSolidRecolourMode = true;

                                              _isEraserActive = false;
                                              _isFillToolActive = false;
                                              _isShapeToolActive = false;
                                              _isTransformActive = false;

                                              _textureActive = false;
                                              _stampBrushActive = false;
                                              _stampBrushItem = null;
                                              _blendSamplingArmed = false;

                                              _draftStroke =
                                                  const <VectorPoint>[];
                                              _draftTextureStrokes =
                                                  <VectorStroke>[];
                                              _draftStampStrokes =
                                                  <VectorStroke>[];

                                              _tintTouchedStrokeIndices.clear();
                                              _tintGestureChanged = false;
                                              _tintGestureUndoCaptured = false;

                                              _clearFillLasso();
                                              _clearShapeDraft();
                                              _clearTransformSelection();
                                            });
                                          },
                                    icon: Icon(
                                      Icons.format_color_fill_outlined,
                                      color:
                                          _isTintToolActive &&
                                              _isSolidRecolourMode
                                          ? Colors.deepPurpleAccent
                                          : Colors.white70,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: _transformToolbarExpanded
                                        ? 'Hide Transform Tools'
                                        : 'Show Transform Tools',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _isPlaying
                                        ? null
                                        : () {
                                            setState(() {
                                              _transformToolbarExpanded =
                                                  !_transformToolbarExpanded;
                                            });
                                          },
                                    icon: Icon(
                                      Icons.open_with,
                                      color:
                                          _isTransformActive ||
                                              _transformToolbarExpanded
                                          ? Colors.deepPurpleAccent
                                          : Colors.white70,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Fill Tool',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _isPlaying
                                        ? null
                                        : () {
                                            setState(() {
                                              _isFillToolActive =
                                                  !_isFillToolActive;

                                              _isEraserActive = false;
                                              _isTintToolActive = false;
                                              _isShapeToolActive = false;
                                              _isTransformActive = false;

                                              _draftStroke =
                                                  const <VectorPoint>[];
                                              _clearShapeDraft();
                                              _clearTransformSelection();

                                              if (!_isFillToolActive) {
                                                _clearFillLasso();
                                              }
                                            });
                                          },
                                    icon: Icon(
                                      Icons.format_color_fill,
                                      color: _isFillToolActive
                                          ? Colors.deepPurpleAccent
                                          : Colors.white70,
                                    ),
                                  ),
                                  PopupMenuButton<_ShapeToolType>(
                                    tooltip: 'Shape Tool',
                                    enabled: !_isPlaying,
                                    onSelected: (shape) {
                                      setState(() {
                                        _shapeToolType = shape;
                                        _isShapeToolActive = true;

                                        _isFillToolActive = false;
                                        _clearFillLasso();
                                        _isEraserActive = false;
                                        _isTintToolActive = false;
                                        _isTransformActive = false;
                                        _activeLayerGroupId = null;

                                        _draftStroke = const <VectorPoint>[];
                                        _clearTransformSelection();
                                        _clearShapeDraft();
                                      });
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: _ShapeToolType.line,
                                        child: ListTile(
                                          leading: Icon(Icons.horizontal_rule),
                                          title: Text('Line'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: _ShapeToolType.rectangle,
                                        child: ListTile(
                                          leading: Icon(
                                            Icons.rectangle_outlined,
                                          ),
                                          title: Text('Rectangle'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: _ShapeToolType.filledRectangle,
                                        child: ListTile(
                                          leading: Icon(Icons.rectangle),
                                          title: Text('Filled Rectangle'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value:
                                            _ShapeToolType.perspectiveRectangle,
                                        child: ListTile(
                                          leading: Icon(
                                            Icons.crop_free_rounded,
                                          ),
                                          title: Text('Perspective Rectangle'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: _ShapeToolType.square,
                                        child: ListTile(
                                          leading: Icon(Icons.crop_square),
                                          title: Text('Square'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: _ShapeToolType.filledSquare,
                                        child: ListTile(
                                          leading: Icon(Icons.square),
                                          title: Text('Filled Square'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: _ShapeToolType.circle,
                                        child: ListTile(
                                          leading: Icon(Icons.circle_outlined),
                                          title: Text('Circle'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: _ShapeToolType.filledCircle,
                                        child: ListTile(
                                          leading: Icon(Icons.circle),
                                          title: Text('Filled Circle'),
                                        ),
                                      ),
                                    ],
                                    icon: Icon(
                                      Icons.category_outlined,
                                      color: _isShapeToolActive
                                          ? Colors.deepPurpleAccent
                                          : Colors.white70,
                                    ),
                                  ),
                                  if (_perspectiveShapeEditing) ...[
                                    IconButton(
                                      tooltip: 'Commit Perspective Shape',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: _confirmPerspectiveShape,
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                        color: Colors.greenAccent,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Cancel Perspective Shape',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: _cancelPerspectiveShape,
                                      icon: const Icon(
                                        Icons.cancel_outlined,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                  ],
                                ],
                                IconButton(
                                  tooltip: editToolbarExpanded
                                      ? 'Hide Edit Tools'
                                      : 'Show Edit Tools',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    setState(() {
                                      final next = !editToolbarExpanded;
                                      _editToolbarExpanded = next;
                                    });
                                  },
                                  icon: Icon(
                                    editToolbarExpanded
                                        ? Icons.chevron_right
                                        : Icons.tune,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (_transformToolbarExpanded && !_isVideoScrubbing)
                      Positioned(
                        top:
                            MediaQuery.of(context).viewPadding.top +
                            kToolbarHeight +
                            68,
                        right: 16,
                        child: Material(
                          elevation: 8,
                          color: const Color(0xE61A1720),
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: _isTransformActive
                                      ? 'Exit Transform'
                                      : 'Transform / Lasso',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _isPlaying
                                      ? null
                                      : () {
                                          setState(() {
                                            _isTransformActive =
                                                !_isTransformActive;

                                            _isEraserActive = false;
                                            _isTintToolActive = false;
                                            _isFillToolActive = false;
                                            _isShapeToolActive = false;

                                            _clearFillLasso();
                                            _clearShapeDraft();
                                            _draftStroke =
                                                const <VectorPoint>[];

                                            if (!_isTransformActive) {
                                              _clearTransformSelection();
                                            }
                                          });
                                        },
                                  icon: Icon(
                                    Icons.select_all,
                                    color: _isTransformActive
                                        ? Colors.deepPurpleAccent
                                        : Colors.white70,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Flip Horizontal',
                                  visualDensity: VisualDensity.compact,
                                  onPressed:
                                      _isPlaying ||
                                          (_selectedTransformStrokes.isEmpty &&
                                              _transformReferenceLayerId ==
                                                  null)
                                      ? null
                                      : _flipSelectedStrokesHorizontally,
                                  icon: const Icon(Icons.flip),
                                ),
                                IconButton(
                                  tooltip: 'Copy Selection',
                                  visualDensity: VisualDensity.compact,
                                  onPressed:
                                      _isPlaying ||
                                          _selectedTransformStrokes.isEmpty
                                      ? null
                                      : _copySelectedStrokes,
                                  icon: const Icon(Icons.content_copy),
                                ),
                                IconButton(
                                  tooltip: 'Paste Selection',
                                  visualDensity: VisualDensity.compact,
                                  onPressed:
                                      _isPlaying || _strokeClipboard.isEmpty
                                      ? null
                                      : _pasteCopiedStrokes,
                                  icon: const Icon(Icons.content_paste),
                                ),
                                const SizedBox(width: 2),
                                IconButton(
                                  tooltip: 'Collapse Transform Tools',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    setState(() {
                                      _transformToolbarExpanded = false;
                                    });
                                  },
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    if (!_drawingMode && !_isVideoScrubbing)
                      Positioned(
                        bottom: 16 + MediaQuery.of(context).viewPadding.bottom,
                        left: 16,
                        child: _timelineExpanded
                            ? Material(
                                elevation: 8,
                                color: const Color(0xE61A1720),
                                borderRadius: BorderRadius.circular(16),
                                clipBehavior: Clip.antiAlias,
                                child: SizedBox(
                                  width: constraints.maxWidth >= 800
                                      ? (constraints.maxWidth - 32).clamp(
                                          360.0,
                                          760.0,
                                        )
                                      : constraints.maxWidth - 32,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      8,
                                      8,
                                      8,
                                    ),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          tooltip: 'Hide Timeline',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () {
                                            setState(() {
                                              _timelineExpanded = false;
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.keyboard_arrow_down,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SingleChildScrollView(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    CompositedTransformTarget(
                                                      link: _timingButtonLink,
                                                      child: IconButton(
                                                        tooltip: _timingExpanded
                                                            ? 'Hide Timing'
                                                            : 'Show Timing',
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        constraints: BoxConstraints(
                                                          minWidth:
                                                              constraints
                                                                      .maxWidth <
                                                                  500
                                                              ? 32
                                                              : 40,
                                                          minHeight:
                                                              constraints
                                                                      .maxWidth <
                                                                  500
                                                              ? 32
                                                              : 40,
                                                        ),
                                                        padding:
                                                            constraints
                                                                    .maxWidth <
                                                                500
                                                            ? EdgeInsets.zero
                                                            : const EdgeInsets.all(
                                                                8,
                                                              ),
                                                        onPressed: () {
                                                          setState(() {
                                                            _timingExpanded =
                                                                !_timingExpanded;
                                                          });
                                                        },
                                                        icon: Icon(
                                                          Icons.schedule,
                                                          color: _timingExpanded
                                                              ? Colors
                                                                    .deepPurpleAccent
                                                              : Colors.white70,
                                                        ),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Onion Skin',
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      constraints: BoxConstraints(
                                                        minWidth:
                                                            constraints
                                                                    .maxWidth <
                                                                500
                                                            ? 32
                                                            : 40,
                                                        minHeight:
                                                            constraints
                                                                    .maxWidth <
                                                                500
                                                            ? 32
                                                            : 40,
                                                      ),
                                                      padding:
                                                          constraints.maxWidth <
                                                              500
                                                          ? EdgeInsets.zero
                                                          : const EdgeInsets.all(
                                                              8,
                                                            ),
                                                      onPressed:
                                                          _toggleOnionSkin,
                                                      icon: Icon(
                                                        Icons.layers,
                                                        color: _showOnionSkin
                                                            ? Colors
                                                                  .deepPurpleAccent
                                                            : Colors.white70,
                                                      ),
                                                    ),
                                                    if (constraints.maxWidth >=
                                                        500)
                                                      const SizedBox(width: 4),
                                                    IconButton(
                                                      tooltip: 'Add Frame',
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      constraints: BoxConstraints(
                                                        minWidth:
                                                            constraints
                                                                    .maxWidth <
                                                                500
                                                            ? 32
                                                            : 40,
                                                        minHeight:
                                                            constraints
                                                                    .maxWidth <
                                                                500
                                                            ? 32
                                                            : 40,
                                                      ),
                                                      padding:
                                                          constraints.maxWidth <
                                                              500
                                                          ? EdgeInsets.zero
                                                          : const EdgeInsets.all(
                                                              8,
                                                            ),
                                                      onPressed: _isPlaying
                                                          ? null
                                                          : _addFrame,
                                                      icon: const Icon(
                                                        Icons.add,
                                                      ),
                                                    ),
                                                    if (_referenceMediaType ==
                                                            'video' &&
                                                        _videoReady)
                                                      IconButton(
                                                        tooltip:
                                                            'Capture Reference Pose',
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        constraints: BoxConstraints(
                                                          minWidth:
                                                              constraints
                                                                      .maxWidth <
                                                                  500
                                                              ? 32
                                                              : 40,
                                                          minHeight:
                                                              constraints
                                                                      .maxWidth <
                                                                  500
                                                              ? 32
                                                              : 40,
                                                        ),
                                                        padding:
                                                            constraints
                                                                    .maxWidth <
                                                                500
                                                            ? EdgeInsets.zero
                                                            : const EdgeInsets.all(
                                                                8,
                                                              ),
                                                        onPressed: _isPlaying
                                                            ? null
                                                            : _captureReferencePose,
                                                        icon: const Icon(
                                                          Icons
                                                              .add_a_photo_outlined,
                                                        ),
                                                      ),
                                                    IconButton(
                                                      tooltip:
                                                          'Duplicate Frame',
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      constraints: BoxConstraints(
                                                        minWidth:
                                                            constraints
                                                                    .maxWidth <
                                                                500
                                                            ? 32
                                                            : 40,
                                                        minHeight:
                                                            constraints
                                                                    .maxWidth <
                                                                500
                                                            ? 32
                                                            : 40,
                                                      ),
                                                      padding:
                                                          constraints.maxWidth <
                                                              500
                                                          ? EdgeInsets.zero
                                                          : const EdgeInsets.all(
                                                              8,
                                                            ),
                                                      onPressed: _isPlaying
                                                          ? null
                                                          : _duplicateFrame,
                                                      icon: const Icon(
                                                        Icons.copy,
                                                      ),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Delete Frame',
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      constraints: BoxConstraints(
                                                        minWidth:
                                                            constraints
                                                                    .maxWidth <
                                                                500
                                                            ? 32
                                                            : 40,
                                                        minHeight:
                                                            constraints
                                                                    .maxWidth <
                                                                500
                                                            ? 32
                                                            : 40,
                                                      ),
                                                      padding:
                                                          constraints.maxWidth <
                                                              500
                                                          ? EdgeInsets.zero
                                                          : const EdgeInsets.all(
                                                              8,
                                                            ),
                                                      onPressed: _isPlaying
                                                          ? null
                                                          : _deleteFrame,
                                                      icon: const Icon(
                                                        Icons.delete_outline,
                                                      ),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Clear Frame',
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      constraints: BoxConstraints(
                                                        minWidth:
                                                            constraints
                                                                    .maxWidth <
                                                                500
                                                            ? 32
                                                            : 40,
                                                        minHeight:
                                                            constraints
                                                                    .maxWidth <
                                                                500
                                                            ? 32
                                                            : 40,
                                                      ),
                                                      padding:
                                                          constraints.maxWidth <
                                                              500
                                                          ? EdgeInsets.zero
                                                          : const EdgeInsets.all(
                                                              8,
                                                            ),
                                                      onPressed: _isPlaying
                                                          ? null
                                                          : _clearCurrentFrame,
                                                      icon: const Icon(
                                                        Icons.clear,
                                                      ),
                                                    ),
                                                    IconButton(
                                                      tooltip: _isPlaying
                                                          ? 'Pause'
                                                          : 'Play',
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      onPressed:
                                                          _togglePlayback,
                                                      icon: Icon(
                                                        _isPlaying
                                                            ? Icons.pause
                                                            : Icons.play_arrow,
                                                        color: _isPlaying
                                                            ? Colors
                                                                  .deepPurpleAccent
                                                            : Colors.white70,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              SizedBox(
                                                height: 64,
                                                child: ReorderableListView.builder(
                                                  scrollController:
                                                      _timelineScrollController,
                                                  scrollDirection:
                                                      Axis.horizontal,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                      ),
                                                  itemCount: _frames.length,
                                                  onReorderItem: _reorderFrame,
                                                  itemBuilder: (context, index) {
                                                    final isSelected =
                                                        index ==
                                                        _selectedFrameIndex;

                                                    return Padding(
                                                      key: Key('frame-$index'),
                                                      padding:
                                                          const EdgeInsets.only(
                                                            right: 6,
                                                          ),
                                                      child: InkWell(
                                                        onTap: () =>
                                                            _selectFrame(index),
                                                        child: Container(
                                                          width: 64,
                                                          clipBehavior:
                                                              Clip.antiAlias,
                                                          decoration: BoxDecoration(
                                                            color: Theme.of(context)
                                                                .colorScheme
                                                                .surfaceContainerHighest,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                            border: Border.all(
                                                              color: isSelected
                                                                  ? Colors
                                                                        .deepPurpleAccent
                                                                  : Colors
                                                                        .white12,
                                                              width: isSelected
                                                                  ? 3
                                                                  : 1,
                                                            ),
                                                          ),
                                                          child: Stack(
                                                            children: [
                                                              CustomPaint(
                                                                painter:
                                                                    FrameThumbnailPainter(
                                                                      strokes:
                                                                          _frames[index],
                                                                    ),
                                                                child:
                                                                    const SizedBox.expand(),
                                                              ),
                                                              Positioned(
                                                                right: 4,
                                                                bottom: 4,
                                                                child: Container(
                                                                  padding:
                                                                      const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            6,
                                                                        vertical:
                                                                            2,
                                                                      ),
                                                                  decoration: BoxDecoration(
                                                                    color: const Color(
                                                                      0xCC121016,
                                                                    ),
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          10,
                                                                        ),
                                                                    border: Border.all(
                                                                      color:
                                                                          isSelected
                                                                          ? Colors.deepPurpleAccent
                                                                          : Colors.white12,
                                                                      width: 1,
                                                                    ),
                                                                  ),
                                                                  child: Text(
                                                                    '${_frameDurations[index]}x',
                                                                    style: const TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                      color: Colors
                                                                          .white,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  IconButton(
                                                    tooltip: 'Jump to Start',
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    onPressed:
                                                        _selectedFrameIndex == 0
                                                        ? null
                                                        : () =>
                                                              _navigateToFrame(
                                                                0,
                                                              ),
                                                    icon: const Icon(
                                                      Icons.first_page,
                                                      size: 21,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Previous Frame',
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    onPressed:
                                                        _selectedFrameIndex == 0
                                                        ? null
                                                        : _previousFrame,
                                                    icon: const Icon(
                                                      Icons.chevron_left,
                                                      size: 21,
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    width: 112,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          'Frame ${_selectedFrameIndex + 1} / ${_frames.length}',
                                                          textAlign:
                                                              TextAlign.center,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                        ),
                                                        if (_referenceFrameTimesMs
                                                            .isNotEmpty)
                                                          Text(
                                                            _referenceTimestampForFrame(
                                                              _selectedFrameIndex,
                                                            ),
                                                            textAlign: TextAlign
                                                                .center,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 9,
                                                                  color: Colors
                                                                      .white60,
                                                                ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Slider(
                                                      value: _selectedFrameIndex
                                                          .toDouble(),
                                                      min: 0,
                                                      max: _frames.length > 1
                                                          ? (_frames.length - 1)
                                                                .toDouble()
                                                          : 1,
                                                      divisions:
                                                          _frames.length > 1
                                                          ? _frames.length - 1
                                                          : 1,
                                                      onChanged:
                                                          _frames.length <= 1
                                                          ? null
                                                          : (value) {
                                                              _navigateToFrame(
                                                                value.round(),
                                                              );
                                                            },
                                                    ),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Next Frame',
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    onPressed:
                                                        _selectedFrameIndex >=
                                                            _frames.length - 1
                                                        ? null
                                                        : _nextFrame,
                                                    icon: const Icon(
                                                      Icons.chevron_right,
                                                      size: 21,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Jump to End',
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    onPressed:
                                                        _selectedFrameIndex >=
                                                            _frames.length - 1
                                                        ? null
                                                        : () =>
                                                              _navigateToFrame(
                                                                _frames.length -
                                                                    1,
                                                              ),
                                                    icon: const Icon(
                                                      Icons.last_page,
                                                      size: 21,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : Material(
                                elevation: 8,
                                color: const Color(0xE61A1720),
                                borderRadius: BorderRadius.circular(16),
                                clipBehavior: Clip.antiAlias,
                                child: IconButton(
                                  tooltip: 'Show Timeline',
                                  onPressed: () {
                                    setState(() {
                                      _timelineExpanded = true;
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.view_timeline_outlined,
                                  ),
                                ),
                              ),
                      ),

                    if (_timingExpanded &&
                        !_drawingMode &&
                        _timelineExpanded &&
                        !_isVideoScrubbing)
                      CompositedTransformFollower(
                        link: _timingButtonLink,
                        showWhenUnlinked: false,
                        targetAnchor: Alignment.topCenter,
                        followerAnchor: Alignment.bottomCenter,
                        offset: const Offset(0, -8),
                        child: Material(
                          elevation: 10,
                          color: const Color(0xF21A1720),
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: SizedBox(
                            width: constraints.maxWidth < 420
                                ? constraints.maxWidth - 32
                                : 300,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                10,
                                14,
                                12,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 70,
                                        child: Text('FPS'),
                                      ),
                                      Expanded(
                                        child: Slider(
                                          value: _fps,
                                          min: 1,
                                          max: 24,
                                          divisions: 23,
                                          label: _fps.toStringAsFixed(0),
                                          onChanged: (value) {
                                            setState(() {
                                              _fps = value;
                                            });

                                            _syncVideoToSelectedFrame();

                                            if (_isPlaying) {
                                              _startPlaybackTimer();
                                            }
                                          },
                                        ),
                                      ),
                                      SizedBox(
                                        width: 28,
                                        child: Text(_fps.toStringAsFixed(0)),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 70,
                                        child: Text('Duration'),
                                      ),
                                      Expanded(
                                        child: Slider(
                                          value:
                                              _frameDurations[_selectedFrameIndex]
                                                  .toDouble(),
                                          min: 1,
                                          max: 8,
                                          divisions: 7,
                                          label:
                                              '${_frameDurations[_selectedFrameIndex]}',
                                          onChanged: (value) {
                                            setState(() {
                                              _frameDurations[_selectedFrameIndex] =
                                                  value.round();
                                            });

                                            _scheduleAutosave();
                                          },
                                        ),
                                      ),
                                      SizedBox(
                                        width: 28,
                                        child: Text(
                                          '${_frameDurations[_selectedFrameIndex]}x',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TransformOverlayPainter extends CustomPainter {
  const _TransformOverlayPainter({
    required this.lassoPoints,
    required this.selectionBounds,
    required this.pivot,
  });

  final List<VectorPoint> lassoPoints;
  final Rect? selectionBounds;
  final Offset? pivot;

  @override
  void paint(Canvas canvas, Size size) {
    final lassoPaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (lassoPoints.length > 1) {
      final path = Path()..moveTo(lassoPoints.first.dx, lassoPoints.first.dy);

      for (var i = 1; i < lassoPoints.length; i++) {
        path.lineTo(lassoPoints[i].dx, lassoPoints[i].dy);
      }

      canvas.drawPath(path, lassoPaint);
    }

    final bounds = selectionBounds;

    if (bounds != null) {
      final boxPaint = Paint()
        ..color = Colors.cyanAccent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawRect(bounds.inflate(6), boxPaint);

      final rotationHandle = bounds.topCenter + const Offset(0, -34);
      final effectivePivot = pivot ?? bounds.center;

      final guidePaint = Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.45)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      // Rotation handle remains above the selection.
      canvas.drawLine(bounds.topCenter, rotationHandle, boxPaint);

      // A faint guide shows the active rotation relationship.
      canvas.drawLine(rotationHandle, effectivePivot, guidePaint);

      final rotationHandlePaint = Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.fill;

      canvas.drawCircle(rotationHandle, 7, rotationHandlePaint);

      // Draggable pivot / anchor.
      final pivotOuterPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;

      final pivotInnerPaint = Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(effectivePivot, 9, pivotOuterPaint);
      canvas.drawCircle(effectivePivot, 8, pivotInnerPaint);

      canvas.drawLine(
        effectivePivot + const Offset(-11, 0),
        effectivePivot + const Offset(11, 0),
        pivotInnerPaint,
      );

      canvas.drawLine(
        effectivePivot + const Offset(0, -11),
        effectivePivot + const Offset(0, 11),
        pivotInnerPaint,
      );

      final handlePaint = Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.fill;

      for (final point in [
        bounds.topLeft,
        bounds.topRight,
        bounds.bottomLeft,
        bounds.bottomRight,
      ]) {
        canvas.drawCircle(point, 6, handlePaint);
      }

      // Midpoint handles provide non-uniform squash/stretch.
      for (final point in [
        bounds.centerLeft,
        bounds.centerRight,
        bounds.topCenter,
        bounds.bottomCenter,
      ]) {
        canvas.drawRect(
          Rect.fromCenter(center: point, width: 12, height: 12),
          handlePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TransformOverlayPainter oldDelegate) {
    return true;
  }
}

class _FillLassoPainter extends CustomPainter {
  const _FillLassoPainter({required this.points, required this.color});

  final List<VectorPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final path = Path()..moveTo(points.first.dx, points.first.dy);

    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    path.close();

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    final outlinePaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _FillLassoPainter oldDelegate) {
    return true;
  }
}

class _RadialColourPickerPainter extends CustomPainter {
  const _RadialColourPickerPainter({required this.hsv});

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final outerRadius = math.min(size.width, size.height) / 2 - 4;

    const ringWidth = 24.0;
    final innerRadius = outerRadius - ringWidth;

    final ringRect = Rect.fromCircle(
      center: center,
      radius: outerRadius - (ringWidth / 2),
    );

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..shader = SweepGradient(
        colors: [
          for (var hue = 0; hue <= 360; hue += 30)
            HSVColor.fromAHSV(1, hue.toDouble(), 1, 1).toColor(),
        ],
      ).createShader(ringRect)
      ..isAntiAlias = true;

    canvas.drawCircle(center, outerRadius - (ringWidth / 2), ringPaint);

    final innerPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          HSVColor.fromAHSV(1, hsv.hue, 0, hsv.value).toColor(),
          HSVColor.fromAHSV(1, hsv.hue, 1, hsv.value).toColor(),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: innerRadius))
      ..isAntiAlias = true;

    canvas.drawCircle(center, innerRadius, innerPaint);

    final hueAngle = hsv.hue * math.pi / 180;

    final hueHandleRadius = outerRadius - (ringWidth / 2);

    final hueHandle = Offset(
      center.dx + math.cos(hueAngle) * hueHandleRadius,
      center.dy + math.sin(hueAngle) * hueHandleRadius,
    );

    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..isAntiAlias = true;

    canvas.drawCircle(hueHandle, 8, handlePaint);

    final saturationHandle = Offset(
      center.dx + math.cos(hueAngle) * innerRadius * hsv.saturation,
      center.dy + math.sin(hueAngle) * innerRadius * hsv.saturation,
    );

    canvas.drawCircle(saturationHandle, 7, handlePaint);
  }

  @override
  bool shouldRepaint(covariant _RadialColourPickerPainter oldDelegate) {
    return oldDelegate.hsv != hsv;
  }
}

class _PerspectiveShapeHandlesPainter extends CustomPainter {
  const _PerspectiveShapeHandlesPainter({required this.corners});

  final List<Offset> corners;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) {
      return;
    }

    final guidePaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.75)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final handleFillPaint = Paint()
      ..color = const Color(0xFF1A1720)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final handleOutlinePaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final guide = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    canvas.drawPath(guide, guidePaint);

    for (final corner in corners) {
      canvas.drawCircle(corner, 10, handleFillPaint);

      canvas.drawCircle(corner, 10, handleOutlinePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PerspectiveShapeHandlesPainter oldDelegate) {
    return oldDelegate.corners != corners;
  }
}

class _PerspectiveLoupePainter extends CustomPainter {
  const _PerspectiveLoupePainter({
    required this.image,
    required this.canvasPosition,
    required this.zoom,
  });

  final ui.Image image;
  final Offset canvasPosition;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;

    canvas.save();

    final clipPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius - 3));

    canvas.clipPath(clipPath);

    final sourceWidth = size.width / zoom;
    final sourceHeight = size.height / zoom;

    final sourceRect = Rect.fromCenter(
      center: canvasPosition,
      width: sourceWidth,
      height: sourceHeight,
    );

    final destinationRect = Offset.zero & size;

    canvas.drawImageRect(
      image,
      sourceRect,
      destinationRect,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true,
    );

    // A subtle dark centre ring makes the actual target coordinate readable
    // against both light and dark reference artwork.
    final centreHalo = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawCircle(center, 5, centreHalo);

    final crosshairPaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    const gap = 7.0;
    const arm = 22.0;

    canvas.drawLine(
      Offset(center.dx - arm, center.dy),
      Offset(center.dx - gap, center.dy),
      crosshairPaint,
    );

    canvas.drawLine(
      Offset(center.dx + gap, center.dy),
      Offset(center.dx + arm, center.dy),
      crosshairPaint,
    );

    canvas.drawLine(
      Offset(center.dx, center.dy - arm),
      Offset(center.dx, center.dy - gap),
      crosshairPaint,
    );

    canvas.drawLine(
      Offset(center.dx, center.dy + gap),
      Offset(center.dx, center.dy + arm),
      crosshairPaint,
    );

    canvas.restore();

    final borderPaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    canvas.drawCircle(center, radius - 2, borderPaint);

    final outerPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.72)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    canvas.drawCircle(center, radius - 5, outerPaint);
  }

  @override
  bool shouldRepaint(covariant _PerspectiveLoupePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.canvasPosition != canvasPosition ||
        oldDelegate.zoom != zoom;
  }
}
