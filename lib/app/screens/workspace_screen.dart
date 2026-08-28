import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';
import '../models/bag_item.dart';
import '../models/brush_preset.dart';
import '../models/drawing_layer.dart';
import '../models/inkdframes_project.dart';
import '../models/layer_group.dart';
import '../models/vector_point.dart';
import '../models/vector_stroke.dart';
import '../painters/animation_canvas_painter.dart';
import '../painters/frame_thumbnail_painter.dart';
import '../services/animation_export_service.dart';
import '../services/brush_preset_service.dart';
import '../services/bag_service.dart';
import 'bag_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _ShapeToolType { line, rectangle, square, circle }

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
  String? _activeLayerGroupId;

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
  List<VectorPoint> _fillLassoPoints = const <VectorPoint>[];

  bool _isShapeToolActive = false;
  _ShapeToolType _shapeToolType = _ShapeToolType.line;
  Offset? _shapeStartPosition;
  List<VectorStroke> _draftShapeStrokes = const <VectorStroke>[];

  bool _isTransformActive = false;
  bool _isTransformDragging = false;
  bool _isTransformScaling = false;
  bool _isTransformRotating = false;

  List<VectorPoint> _lassoPoints = const <VectorPoint>[];
  Map<String, Set<int>> _selectedTransformStrokes = <String, Set<int>>{};

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

    final project = InkdFramesProject(
      id: _projectId,
      name: _projectName,
      fps: _fps,
      frames: _frames,
      layers: _layers,
      layerGroups: _layerGroups,
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

  List<VectorStroke> _compositeFrame(int frameIndex) {
    final strokes = <VectorStroke>[];

    // Layer list is displayed top-to-bottom.
    // Paint bottom layers first so the first layer remains visually on top.
    for (final layer in _layers.reversed) {
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

    setState(() {
      _activeLayerIndex = index;
      _activeLayerGroupId = null;
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

  bool _isLayerEffectivelyVisible(DrawingLayer layer) {
    if (!layer.visible) return false;

    final group = _groupContainingLayer(layer.id);

    return group == null || group.visible;
  }

  void _selectLayerGroup(String groupId) {
    final exists = _layerGroups.any((group) => group.id == groupId);

    if (!exists) return;

    setState(() {
      _activeLayerGroupId = groupId;
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
      visible: true,
      expanded: true,
    );

    setState(() {
      // Insert the Bag artwork at the top of the layer stack.
      _layers.insertAll(0, newLayers);
      _layerGroups.add(newGroup);

      // Select the newly unpacked group.
      _activeLayerGroupId = newGroup.id;
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

    pocketAssignments[item.id] = selectedPocket;

    await prefs.setString(pocketAssignmentsKey, jsonEncode(pocketAssignments));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.name} tucked into $selectedPocket 🎒')),
    );
  }

  void _addLayerGroup() {
    setState(() {
      final group = LayerGroup(
        id: 'group_${DateTime.now().microsecondsSinceEpoch}',
        name: 'Group ${_layerGroups.length + 1}',
        childLayerIds: <String>[],
      );

      _layerGroups.add(group);
      _activeLayerGroupId = group.id;
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
    final index = _layerGroups.indexWhere((group) => group.id == groupId);

    if (index == -1) return;

    final group = _layerGroups[index];
    final childLayerIds = Set<String>.from(group.childLayerIds);

    setState(() {
      // Deleting a group also deletes every layer still contained inside it.
      // Users can preserve individual layers by removing them from the group first.
      _layers.removeWhere((layer) => childLayerIds.contains(layer.id));
      _layerGroups.removeAt(index);

      // Never allow a project to end up with no drawing layers.
      if (_layers.isEmpty) {
        _layers.add(
          DrawingLayer(
            id: 'linework_${DateTime.now().microsecondsSinceEpoch}',
            name: 'Linework',
            frames: List.generate(
              _frameDurations.length,
              (_) => <VectorStroke>[],
            ),
          ),
        );
      }

      if (_activeLayerGroupId == groupId) {
        _activeLayerGroupId = null;
      }

      _activeLayerIndex = _activeLayerIndex.clamp(0, _layers.length - 1);

      _clearTransformSelection();
      _resetUndoRedo();
      _rebuildCompositeFrames();
    });

    _scheduleAutosave();
  }

  void _assignLayerToGroup(String layerId, String? groupId) {
    setState(() {
      // A drawing layer belongs to at most one group.
      for (var i = 0; i < _layerGroups.length; i++) {
        final group = _layerGroups[i];

        if (group.childLayerIds.contains(layerId)) {
          final ids = List<String>.from(group.childLayerIds)..remove(layerId);

          _layerGroups[i] = group.copyWith(childLayerIds: ids);
        }
      }

      if (groupId != null) {
        final groupIndex = _layerGroups.indexWhere(
          (group) => group.id == groupId,
        );

        if (groupIndex != -1) {
          final group = _layerGroups[groupIndex];

          final ids = List<String>.from(group.childLayerIds);

          if (!ids.contains(layerId)) {
            ids.add(layerId);
          }

          _layerGroups[groupIndex] = group.copyWith(childLayerIds: ids);
        }
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

    setState(() {
      _layers.insert(
        0,
        DrawingLayer(
          id: 'layer_${DateTime.now().microsecondsSinceEpoch}',
          name: 'Layer ${_layers.length + 1}',
          frames: List.generate(frameCount, (_) => <VectorStroke>[]),
        ),
      );

      _activeLayerIndex = 0;
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
      _layers.removeAt(index);

      for (var groupIndex = 0; groupIndex < _layerGroups.length; groupIndex++) {
        final group = _layerGroups[groupIndex];

        if (group.childLayerIds.contains(deletedLayerId)) {
          final ids = List<String>.from(group.childLayerIds)
            ..remove(deletedLayerId);

          _layerGroups[groupIndex] = group.copyWith(childLayerIds: ids);
        }
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

  void _moveDrawingLayer(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _layers.length ||
        newIndex < 0 ||
        newIndex >= _layers.length ||
        oldIndex == newIndex) {
      return;
    }

    setState(() {
      final activeId = _activeLayer.id;
      final layer = _layers.removeAt(oldIndex);
      _layers.insert(newIndex, layer);

      _activeLayerIndex = _layers.indexWhere(
        (candidate) => candidate.id == activeId,
      );

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
            ),
          ),
        );

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
      }

      _activeLayerIndex = 0;
      _ensureLayerFrameCount();
      _rebuildCompositeFrames();
      _resetUndoRedo();

      _fps = project.fps;
      _canvasWidth = project.canvasWidth;
      _canvasHeight = project.canvasHeight;
      _canvasBackgroundColor = Color(project.canvasBackgroundColor);
      _referenceMediaPath = project.referenceMediaPath;
      _referenceMediaType = project.referenceMediaType;
      _referenceVisible = project.referenceVisible;
      _referenceOpacity = project.referenceOpacity;

      _referenceFrameTimesMs
        ..clear()
        ..addAll(project.referenceFrameTimesMs);

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

  void _clearTransformSelection() {
    _lassoPoints = const <VectorPoint>[];
    _selectedTransformStrokes = <String, Set<int>>{};
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

  Offset _transformRotationHandle(Rect bounds) {
    return bounds.topCenter + const Offset(0, -34);
  }

  bool _transformRotationHandleHit(Offset position, Rect bounds) {
    const hitRadius = 24.0;

    return (position - _transformRotationHandle(bounds)).distance <= hitRadius;
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
    double scale,
    Offset anchor,
    Map<String, List<VectorStroke>> snapshot,
  ) {
    if (_selectedTransformStrokes.isEmpty) return;

    final safeScale = scale.clamp(0.05, 20.0);

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
                  dx: anchor.dx + ((point.dx - anchor.dx) * safeScale),
                  dy: anchor.dy + ((point.dy - anchor.dy) * safeScale),
                  pressure: point.pressure,
                ),
              )
              .toList(),
          strokeWidth: source.filled
              ? source.strokeWidth
              : (source.strokeWidth * safeScale).clamp(0.25, 500.0),
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

    VectorStroke stroke(List<Offset> points) {
      return VectorStroke(
        points: points.map(point).toList(),
        strokeWidth: _brushSize,
        color: _brushColor.withValues(alpha: _brushOpacity),
      );
    }

    switch (_shapeToolType) {
      case _ShapeToolType.line:
        return <VectorStroke>[
          stroke(<Offset>[start, end]),
        ];

      case _ShapeToolType.rectangle:
        final rect = Rect.fromPoints(start, end);

        return <VectorStroke>[
          stroke(<Offset>[rect.topLeft, rect.topRight]),
          stroke(<Offset>[rect.topRight, rect.bottomRight]),
          stroke(<Offset>[rect.bottomRight, rect.bottomLeft]),
          stroke(<Offset>[rect.bottomLeft, rect.topLeft]),
        ];

      case _ShapeToolType.square:
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;

        final side = math.max(dx.abs(), dy.abs());

        final squareEnd = Offset(
          start.dx + (dx < 0 ? -side : side),
          start.dy + (dy < 0 ? -side : side),
        );

        final rect = Rect.fromPoints(start, squareEnd);

        return <VectorStroke>[
          stroke(<Offset>[rect.topLeft, rect.topRight]),
          stroke(<Offset>[rect.topRight, rect.bottomRight]),
          stroke(<Offset>[rect.bottomRight, rect.bottomLeft]),
          stroke(<Offset>[rect.bottomLeft, rect.topLeft]),
        ];

      case _ShapeToolType.circle:
        final rect = Rect.fromPoints(start, end);
        final center = rect.center;
        final radiusX = rect.width / 2;
        final radiusY = rect.height / 2;

        if (radiusX < 0.5 || radiusY < 0.5) {
          return const <VectorStroke>[];
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

        return <VectorStroke>[stroke(points)];
    }
  }

  void _updateShapePreview(Offset position) {
    final start = _shapeStartPosition;

    if (start == null) return;

    _draftShapeStrokes = _shapeStrokes(start, position);
  }

  void _clearShapeDraft() {
    _shapeStartPosition = null;
    _draftShapeStrokes = const <VectorStroke>[];
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

  void _handlePointerDown(PointerDownEvent event, BuildContext canvasContext) {
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
      final bounds = _selectedStrokeBounds();

      if (bounds != null) {
        if (_transformRotationHandleHit(canvasPosition, bounds)) {
          if (_activeLayerGroup == null) {
            _saveUndoState();
          } else {
            _saveGroupUndoState();
          }

          final center = bounds.center;

          setState(() {
            _isTransformRotating = true;
            _isTransformScaling = false;
            _isTransformDragging = false;
            _transformRotationCenter = center;
            _transformRotationStartAngle = _angleFromCenter(
              canvasPosition,
              center,
            );
            _transformRotationSnapshot = _selectedTransformSnapshot();
          });

          return;
        }

        final corner = _transformCornerHit(canvasPosition, bounds);

        if (corner != null) {
          if (_activeLayerGroup == null) {
            _saveUndoState();
          } else {
            _saveGroupUndoState();
          }

          final anchor = _oppositeTransformCorner(corner, bounds);

          final startDistance = (corner - anchor).distance;

          setState(() {
            _isTransformScaling = true;
            _isTransformDragging = false;
            _isTransformRotating = false;
            _transformScaleAnchor = anchor;
            _transformScaleStartDistance = startDistance < 0.001
                ? 0.001
                : startDistance;
            _transformScaleSnapshot = _selectedTransformSnapshot();
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
      } else {
        setState(() {
          _selectedTransformStrokes = <String, Set<int>>{};
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
      setState(() {
        _shapeStartPosition = canvasPosition;
        _draftShapeStrokes = _shapeStrokes(canvasPosition, canvasPosition);
      });

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
      if (_isTransformRotating &&
          _transformRotationCenter != null &&
          _transformRotationStartAngle != null &&
          _transformRotationSnapshot != null) {
        final currentAngle = _angleFromCenter(
          canvasPosition,
          _transformRotationCenter!,
        );

        final angle = currentAngle - _transformRotationStartAngle!;

        setState(() {
          _rotateSelectedStrokes(
            angle,
            _transformRotationCenter!,
            _transformRotationSnapshot!,
          );
        });

        return;
      }

      if (_isTransformScaling &&
          _transformScaleAnchor != null &&
          _transformScaleStartDistance != null &&
          _transformScaleSnapshot != null) {
        final currentDistance =
            (canvasPosition - _transformScaleAnchor!).distance;

        final scale = currentDistance / _transformScaleStartDistance!;

        setState(() {
          _scaleSelectedStrokes(
            scale,
            _transformScaleAnchor!,
            _transformScaleSnapshot!,
          );
        });

        return;
      }

      if (_isTransformDragging && _transformLastPosition != null) {
        final delta = canvasPosition - _transformLastPosition!;

        setState(() {
          _moveSelectedStrokes(delta);
          _transformLastPosition = canvasPosition;
        });

        return;
      }

      if (_lassoPoints.isNotEmpty) {
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
      final last = _fillLassoPoints.last;
      final dx = canvasPosition.dx - last.dx;
      final dy = canvasPosition.dy - last.dy;

      if ((dx * dx) + (dy * dy) >= 4) {
        setState(() {
          _fillLassoPoints.add(
            VectorPoint(
              dx: canvasPosition.dx,
              dy: canvasPosition.dy,
              pressure: 1,
            ),
          );
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

    if (_isShapeToolActive && _shapeStartPosition != null) {
      setState(() {
        _commitShape();
      });

      _scheduleAutosave();
      return;
    }

    if (_isTransformActive) {
      setState(() {
        if (_isTransformRotating) {
          _isTransformRotating = false;
          _transformRotationCenter = null;
          _transformRotationStartAngle = null;
          _transformRotationSnapshot = null;
        } else if (_isTransformScaling) {
          _isTransformScaling = false;
          _transformScaleAnchor = null;
          _transformScaleStartDistance = null;
          _transformScaleSnapshot = null;
        } else if (_isTransformDragging) {
          _isTransformDragging = false;
          _transformLastPosition = null;
        } else {
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
    if (_activePointerCount > 0) {
      _activePointerCount -= 1;
    }
    if (_isPlaying) {
      return;
    }
    setState(() {
      _draftStroke = const <VectorPoint>[];
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

  List<Widget> _buildLayerPanelEntries() {
    final widgets = <Widget>[];

    for (final group in _layerGroups) {
      widgets.add(_buildLayerGroupCard(group));
    }

    for (var index = 0; index < _layers.length; index++) {
      final layer = _layers[index];

      if (_groupContainingLayer(layer.id) == null) {
        widgets.add(_buildDrawingLayerCard(index, indented: false));
      }
    }

    return widgets;
  }

  Widget _buildLayerGroupCard(LayerGroup group) {
    final selected = _activeLayerGroupId == group.id;

    final childIndices = <int>[];

    for (var index = 0; index < _layers.length; index++) {
      if (group.childLayerIds.contains(_layers[index].id)) {
        childIndices.add(index);
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 0),
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
            onDoubleTap: _isPlaying ? null : () => _renameLayerGroup(group.id),
            child: Row(
              children: [
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
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete Group')),
                  ],
                ),
              ],
            ),
          ),

          if (group.expanded) ...[
            for (final layerIndex in childIndices)
              _buildDrawingLayerCard(layerIndex, indented: true),
          ],
        ],
      ),
    );
  }

  Widget _buildDrawingLayerCard(int index, {required bool indented}) {
    final layer = _layers[index];
    final selected = _activeLayerGroupId == null && index == _activeLayerIndex;

    final currentGroup = _groupContainingLayer(layer.id);

    return Container(
      margin: EdgeInsets.fromLTRB(indented ? 22 : 6, 4, 6, 0),
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
            onTap: () => _selectLayer(index),
            onDoubleTap: _isPlaying ? null : () => _renameDrawingLayer(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
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
                  IconButton(
                    tooltip: 'Move Layer Up',
                    visualDensity: VisualDensity.compact,
                    onPressed: _isPlaying || index == 0
                        ? null
                        : () => _moveDrawingLayer(index, index - 1),
                    icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Move Layer Down',
                    visualDensity: VisualDensity.compact,
                    onPressed: _isPlaying || index == _layers.length - 1
                        ? null
                        : () => _moveDrawingLayer(index, index + 1),
                    icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Layer Options',
                    onSelected: (value) {
                      if (value == 'rename') {
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
                                          if (_referenceVisible &&
                                              _referenceMediaType == 'video' &&
                                              _videoReady &&
                                              _videoController != null)
                                            Opacity(
                                              opacity: _referenceOpacity,
                                              child: FittedBox(
                                                fit: BoxFit.contain,
                                                child: SizedBox(
                                                  width: _videoController!
                                                      .value
                                                      .size
                                                      .width,
                                                  height: _videoController!
                                                      .value
                                                      .size
                                                      .height,
                                                  child: VideoPlayer(
                                                    _videoController!,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (_referenceVisible &&
                                              _referenceMediaType == 'image' &&
                                              _referenceMediaPath != null)
                                            Opacity(
                                              opacity: _referenceOpacity,
                                              child: Image.file(
                                                File(_referenceMediaPath!),
                                                fit: BoxFit.contain,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) {
                                                      return const Center(
                                                        child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .broken_image_outlined,
                                                              size: 48,
                                                              color: Colors
                                                                  .white54,
                                                            ),
                                                            SizedBox(height: 8),
                                                            Text(
                                                              'Reference image unavailable',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .white54,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                              ),
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
                                                  _referenceMediaPath == null ||
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
                                                child: const SizedBox.expand(),
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
                                                child: const SizedBox.expand(),
                                              ),
                                            ),
                                          if (_isTransformActive)
                                            IgnorePointer(
                                              child: CustomPaint(
                                                painter: _TransformOverlayPainter(
                                                  lassoPoints: _lassoPoints,
                                                  selectionBounds:
                                                      _selectedStrokeBounds(),
                                                ),
                                                child: const SizedBox.expand(),
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

                                          if (_referenceMediaPath != null) ...[
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
                                                  if (!_isVideoScrubbing)
                                                    Row(
                                                      children: [
                                                        IconButton(
                                                          tooltip:
                                                              _referenceVisible
                                                              ? 'Hide Reference'
                                                              : 'Show Reference',
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                          onPressed: () {
                                                            setState(() {
                                                              _referenceVisible =
                                                                  !_referenceVisible;
                                                            });
                                                            _scheduleAutosave();
                                                          },
                                                          icon: Icon(
                                                            _referenceVisible
                                                                ? Icons
                                                                      .visibility
                                                                : Icons
                                                                      .visibility_off,
                                                            size: 20,
                                                          ),
                                                        ),
                                                        Icon(
                                                          _referenceMediaType ==
                                                                  'video'
                                                              ? Icons
                                                                    .movie_outlined
                                                              : Icons
                                                                    .image_outlined,
                                                          size: 19,
                                                          color: Colors.white70,
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            _referenceMediaType ==
                                                                    'video'
                                                                ? 'Video Reference'
                                                                : 'Image Reference',
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                        const Padding(
                                                          padding:
                                                              EdgeInsets.only(
                                                                right: 10,
                                                              ),
                                                          child: Icon(
                                                            Icons.lock_outline,
                                                            size: 17,
                                                            color:
                                                                Colors.white38,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  if (!_isVideoScrubbing)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.fromLTRB(
                                                            12,
                                                            0,
                                                            10,
                                                            2,
                                                          ),
                                                      child: Row(
                                                        children: [
                                                          const SizedBox(
                                                            width: 50,
                                                            child: Text(
                                                              'Opacity',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                              ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            child: Slider(
                                                              value:
                                                                  _referenceOpacity,
                                                              min: 0,
                                                              max: 1,
                                                              onChanged: (value) {
                                                                setState(() {
                                                                  _referenceOpacity =
                                                                      value;
                                                                });
                                                                _scheduleAutosave();
                                                              },
                                                            ),
                                                          ),
                                                          SizedBox(
                                                            width: 38,
                                                            child: Text(
                                                              '${(_referenceOpacity * 100).round()}%',
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        10,
                                                                  ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
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
                                        value: _ShapeToolType.square,
                                        child: ListTile(
                                          leading: Icon(Icons.crop_square),
                                          title: Text('Square'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: _ShapeToolType.circle,
                                        child: ListTile(
                                          leading: Icon(Icons.circle_outlined),
                                          title: Text('Circle'),
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
  });

  final List<VectorPoint> lassoPoints;
  final Rect? selectionBounds;

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

      canvas.drawLine(bounds.topCenter, rotationHandle, boxPaint);

      final rotationHandlePaint = Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.fill;

      canvas.drawCircle(rotationHandle, 7, rotationHandlePaint);

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
