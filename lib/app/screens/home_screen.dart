import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'project_library_screen.dart';
import 'welcome_home_screen.dart';
import 'workspace_screen.dart';
import 'bag_screen.dart';
import '../models/bag_item.dart';
import '../models/composite_asset.dart';
import '../models/placed_decoration.dart';
import '../models/vector_point.dart';
import '../models/vector_stroke.dart';
import '../painters/animation_canvas_painter.dart';
import '../painters/bag_item_preview_painter.dart';
import '../services/bag_service.dart';

class _ImageAlphaMask {
  const _ImageAlphaMask({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;

  bool hitTest(
    Offset position,
    Size boxSize, {
    required bool mirrored,
    int alphaThreshold = 32,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        boxSize.width <= 0 ||
        boxSize.height <= 0) {
      return false;
    }

    // Match Image.file(... fit: BoxFit.contain).
    final scale = (boxSize.width / width < boxSize.height / height)
        ? boxSize.width / width
        : boxSize.height / height;

    final renderedWidth = width * scale;
    final renderedHeight = height * scale;

    final left = (boxSize.width - renderedWidth) / 2;
    final top = (boxSize.height - renderedHeight) / 2;

    if (position.dx < left ||
        position.dy < top ||
        position.dx >= left + renderedWidth ||
        position.dy >= top + renderedHeight) {
      return false;
    }

    var normalizedX = (position.dx - left) / renderedWidth;
    final normalizedY = (position.dy - top) / renderedHeight;

    if (mirrored) {
      normalizedX = 1.0 - normalizedX;
    }

    final pixelX = (normalizedX * width).floor().clamp(0, width - 1);
    final pixelY = (normalizedY * height).floor().clamp(0, height - 1);

    final alphaIndex = ((pixelY * width) + pixelX) * 4 + 3;

    if (alphaIndex < 0 || alphaIndex >= rgba.length) {
      return false;
    }

    return rgba[alphaIndex] >= alphaThreshold;
  }
}

class _AlphaHitTest extends SingleChildRenderObjectWidget {
  const _AlphaHitTest({
    required this.mask,
    required this.mirrored,
    required super.child,
  });

  final _ImageAlphaMask? mask;
  final bool mirrored;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderAlphaHitTest(mask: mask, mirrored: mirrored);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderAlphaHitTest renderObject,
  ) {
    renderObject
      ..mask = mask
      ..mirrored = mirrored;
  }
}

class _RenderAlphaHitTest extends RenderProxyBox {
  _RenderAlphaHitTest({required _ImageAlphaMask? mask, required bool mirrored})
    : _mask = mask,
      _mirrored = mirrored;

  _ImageAlphaMask? _mask;
  bool _mirrored;

  set mask(_ImageAlphaMask? value) {
    _mask = value;
  }

  set mirrored(bool value) {
    _mirrored = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final currentMask = _mask;

    // Vector Bag items keep their existing rectangular hit area.
    // Raster image items become alpha-aware once their mask is ready.
    if (currentMask != null &&
        !currentMask.hitTest(position, size, mirrored: _mirrored)) {
      return false;
    }

    return super.hitTest(result, position: position);
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _RoomNodeOverride {
  final double offsetX;
  final double offsetY;
  final double scale;
  final bool mirrored;

  // Instance-local choice for Composite variant nodes.
  //
  // null means: use the authored Bag Composite activeIndex.
  final int? activeVariantIndex;

  const _RoomNodeOverride({
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.scale = 1.0,
    this.mirrored = false,
    this.activeVariantIndex,
  });

  _RoomNodeOverride copyWith({
    double? offsetX,
    double? offsetY,
    double? scale,
    bool? mirrored,
    int? activeVariantIndex,
  }) {
    return _RoomNodeOverride(
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      scale: scale ?? this.scale,
      mirrored: mirrored ?? this.mirrored,
      activeVariantIndex: activeVariantIndex ?? this.activeVariantIndex,
    );
  }

  bool get isIdentity =>
      offsetX.abs() < 0.000001 &&
      offsetY.abs() < 0.000001 &&
      (scale - 1.0).abs() < 0.000001 &&
      !mirrored &&
      activeVariantIndex == null;
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _decorationsKey = 'inkdframes_home_decorations_v1';

  final BagService _bagService = BagService();

  List<PlacedDecoration> _decorations = <PlacedDecoration>[];

  Map<String, BagItem> _bagItemsById = <String, BagItem>{};

  bool _decorateMode = false;
  String? _selectedDecorationId;

  // --------------------------------------------------------
  // ROOM MANAGER
  //
  // A placed Composite can be entered without flattening or
  // dismantling it. While inside Room Contents mode the outer
  // room instance is locked so later patches can safely target
  // its internal Composite nodes instead.
  // --------------------------------------------------------
  String? _editingRoomDecorationId;

  // The currently selected authored node inside the active Composite room.
  // This is intentionally selection-only for Rooms Awaken #2.
  // We do not mutate the reusable Bag Composite source here.
  String? _selectedRoomNodeId;
  String? _selectedRoomNodeName;

  // Rooms Awaken #9
  //
  // The current Composite hierarchy scope.
  //
  // Empty means the Composite root. Each entry is an authored group/node ID
  // that has been entered. Only direct children of the current scope are
  // selectable and transformable.
  final List<String> _roomScopeNodeIds = <String>[];

  // Instance-local Composite overrides.
  //
  // outer key = placed decoration ID
  // inner key = authored Composite node ID
  //
  // The reusable Bag Composite remains immutable.
  final Map<String, Map<String, _RoomNodeOverride>> _roomNodeOverrides =
      <String, Map<String, _RoomNodeOverride>>{};

  bool get _isEditingRoomContents => _editingRoomDecorationId != null;

  // Rooms Awaken #12
  //
  // Internal Composite editing is no longer part of the normal Room Manager
  // contract. Keep the historical machinery dormant for the moment while the
  // authored-room rules settle, rather than deleting intertwined persistence
  // and gesture code in the same cleanup pass.
  bool get _legacyRoomNodeEditingEnabled => false;

  BagItem? get _selectedDecorationBagItem {
    final selected = _selectedDecoration;
    if (selected == null) return null;
    return _bagItemsById[selected.bagItemId];
  }

  bool get _selectedDecorationIsComposite =>
      _selectedDecorationBagItem?.isComposite ?? false;

  void _enterRoomContents() {
    final selected = _selectedDecoration;

    if (selected == null || !_selectedDecorationIsComposite) {
      return;
    }

    setState(() {
      _editingRoomDecorationId = selected.id;
      _selectedDecorationId = selected.id;
      _selectedRoomNodeId = null;
      _selectedRoomNodeName = null;
      _roomScopeNodeIds.clear();
      _decorateMode = true;
    });
  }

  void _exitRoomContents() {
    final roomId = _editingRoomDecorationId;

    setState(() {
      _editingRoomDecorationId = null;
      _selectedRoomNodeId = null;
      _selectedRoomNodeName = null;
      _roomScopeNodeIds.clear();

      if (roomId != null &&
          _decorations.any((decoration) => decoration.id == roomId)) {
        _selectedDecorationId = roomId;
      }
    });
  }

  final ScrollController _homeScrollController = ScrollController();

  final Map<int, Offset> _decorateTouchPointers = <int, Offset>{};
  Offset? _decoratePanCentroid;

  // Rooms Awaken #6
  //
  // Two-finger scaling of a selected semantic node uses the raw touch
  // pointers already tracked by Home. Keeping this separate from Flutter's
  // scale recognizer prevents the existing one-finger room drag from
  // competing with pinch gestures.
  double? _roomNodePinchStartDistance;
  double? _roomNodePinchStartScale;
  String? _roomNodePinchDecorationId;
  String? _roomNodePinchNodeId;

  final Map<String, _ImageAlphaMask> _imageAlphaMasks =
      <String, _ImageAlphaMask>{};

  @override
  void initState() {
    super.initState();
    _loadDecorations();
  }

  @override
  void dispose() {
    _homeScrollController.dispose();
    super.dispose();
  }

  void _handleDecoratePointerDown(PointerDownEvent event) {
    if (!_decorateMode || event.kind != PointerDeviceKind.touch) {
      return;
    }

    _decorateTouchPointers[event.pointer] = event.position;

    if (_decorateTouchPointers.length >= 2) {
      if (_isEditingRoomContents && _selectedRoomNodeId != null) {
        _beginRoomNodePinch();
        _decoratePanCentroid = null;
        return;
      }

      _decoratePanCentroid = _touchCentroid();
    }
  }

  void _handleDecoratePointerMove(PointerMoveEvent event) {
    if (!_decorateMode ||
        event.kind != PointerDeviceKind.touch ||
        !_decorateTouchPointers.containsKey(event.pointer)) {
      return;
    }

    _decorateTouchPointers[event.pointer] = event.position;

    if (_decorateTouchPointers.length < 2) {
      _decoratePanCentroid = null;
      return;
    }

    // While editing a semantic room node, two fingers belong exclusively
    // to that node. The Home panorama must not slide underneath it.
    if (_isEditingRoomContents && _selectedRoomNodeId != null) {
      if (_roomNodePinchStartDistance == null ||
          _roomNodePinchDecorationId != _editingRoomDecorationId ||
          _roomNodePinchNodeId != _selectedRoomNodeId) {
        _beginRoomNodePinch();
      }

      _updateRoomNodePinch();
      _decoratePanCentroid = null;
      return;
    }

    final centroid = _touchCentroid();
    final previous = _decoratePanCentroid;

    _decoratePanCentroid = centroid;

    if (previous == null || !_homeScrollController.hasClients) {
      return;
    }

    final horizontalDelta = centroid.dx - previous.dx;

    final position = _homeScrollController.position;

    final target = (_homeScrollController.offset - horizontalDelta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    _homeScrollController.jumpTo(target);
  }

  void _handleDecoratePointerUp(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }

    final wasPinching = _roomNodePinchStartDistance != null;

    _decorateTouchPointers.remove(event.pointer);

    if (wasPinching && _decorateTouchPointers.length < 2) {
      _finishRoomNodePinch();
    }

    if (_decorateTouchPointers.length >= 2) {
      if (_isEditingRoomContents && _selectedRoomNodeId != null) {
        _beginRoomNodePinch();
        _decoratePanCentroid = null;
      } else {
        _decoratePanCentroid = _touchCentroid();
      }
    } else {
      _decoratePanCentroid = null;
    }
  }

  double? _currentTouchDistance() {
    if (_decorateTouchPointers.length < 2) {
      return null;
    }

    final points = _decorateTouchPointers.values.take(2).toList();
    return (points[0] - points[1]).distance;
  }

  void _beginRoomNodePinch() {
    final decorationId = _editingRoomDecorationId;
    final nodeId = _selectedRoomNodeId;
    final distance = _currentTouchDistance();

    if (decorationId == null ||
        nodeId == null ||
        distance == null ||
        distance <= 0.000001) {
      return;
    }

    final current = _roomNodeOverrideFor(decorationId, nodeId);

    _roomNodePinchStartDistance = distance;
    _roomNodePinchStartScale = current.scale;
    _roomNodePinchDecorationId = decorationId;
    _roomNodePinchNodeId = nodeId;
  }

  void _updateRoomNodePinch() {
    final startDistance = _roomNodePinchStartDistance;
    final startScale = _roomNodePinchStartScale;
    final decorationId = _roomNodePinchDecorationId;
    final nodeId = _roomNodePinchNodeId;
    final distance = _currentTouchDistance();

    if (startDistance == null ||
        startScale == null ||
        decorationId == null ||
        nodeId == null ||
        distance == null ||
        startDistance <= 0.000001) {
      return;
    }

    if (decorationId != _editingRoomDecorationId ||
        nodeId != _selectedRoomNodeId) {
      return;
    }

    final nextScale = (startScale * (distance / startDistance)).clamp(
      0.1,
      10.0,
    );

    _updateSelectedRoomNodeOverride(
      (current) => current.copyWith(scale: nextScale),
      persist: false,
    );
  }

  void _finishRoomNodePinch() {
    final hadPinch = _roomNodePinchStartDistance != null;

    _roomNodePinchStartDistance = null;
    _roomNodePinchStartScale = null;
    _roomNodePinchDecorationId = null;
    _roomNodePinchNodeId = null;

    if (hadPinch) {
      _saveDecorations();
    }
  }

  Offset _touchCentroid() {
    if (_decorateTouchPointers.isEmpty) {
      return Offset.zero;
    }

    var dx = 0.0;
    var dy = 0.0;

    for (final point in _decorateTouchPointers.values) {
      dx += point.dx;
      dy += point.dy;
    }

    return Offset(
      dx / _decorateTouchPointers.length,
      dy / _decorateTouchPointers.length,
    );
  }

  Future<void> _loadDecorations() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _bagService.loadItems();

    final raw = prefs.getString(_decorationsKey);

    final decorations = <PlacedDecoration>[];

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);

        if (decoded is List) {
          decorations.addAll(
            decoded.whereType<Map>().map(
              (entry) => PlacedDecoration.fromJson(
                entry.map<String, dynamic>(
                  (key, value) => MapEntry(key.toString(), value),
                ),
              ),
            ),
          );
        }
      } catch (_) {}
    }

    if (!mounted) return;

    final loadedRoomOverrides = <String, Map<String, _RoomNodeOverride>>{};

    for (final decoration in decorations) {
      if (decoration.roomNodeOverrides.isEmpty) {
        continue;
      }

      final nodeOverrides = <String, _RoomNodeOverride>{};

      for (final entry in decoration.roomNodeOverrides.entries) {
        final override = _roomNodeOverrideFromJson(entry.value);

        if (!override.isIdentity) {
          nodeOverrides[entry.key] = override;
        }
      }

      if (nodeOverrides.isNotEmpty) {
        loadedRoomOverrides[decoration.id] = nodeOverrides;
      }
    }

    setState(() {
      _decorations = decorations;
      _roomNodeOverrides
        ..clear()
        ..addAll(loadedRoomOverrides);

      _bagItemsById = <String, BagItem>{
        for (final item in items) item.id: item,
      };
    });

    await _primeImageAlphaMasks(items);
  }

  Future<void> _saveDecorations() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _decorationsKey,
      jsonEncode(
        _decorations
            .map(
              (decoration) => decoration
                  .copyWith(
                    roomNodeOverrides: _serializedRoomOverridesFor(
                      decoration.id,
                    ),
                  )
                  .toJson(),
            )
            .toList(),
      ),
    );
  }

  void _collectCompositeImagePaths(CompositeNode node, Set<String> paths) {
    if (node.type == 'reference') {
      final mediaType = node.payload['mediaType']?.toString() ?? 'image';
      final mediaPath = node.payload['mediaPath']?.toString() ?? '';

      if (mediaType == 'image' && mediaPath.isNotEmpty) {
        paths.add(mediaPath);
      }
    }

    for (final child in node.children) {
      _collectCompositeImagePaths(child, paths);
    }
  }

  Future<void> _primeImageAlphaMasks(Iterable<BagItem> items) async {
    final loaded = <String, _ImageAlphaMask>{};
    final imagePaths = <String>{};

    for (final item in items) {
      if (item.isImage) {
        final imagePath = item.imagePath;

        if (imagePath != null && imagePath.isNotEmpty) {
          imagePaths.add(imagePath);
        }
      }

      final composite = item.composite;

      if (composite != null) {
        _collectCompositeImagePaths(composite.root, imagePaths);
      }
    }

    for (final imagePath in imagePaths) {
      if (_imageAlphaMasks.containsKey(imagePath) ||
          loaded.containsKey(imagePath)) {
        continue;
      }

      try {
        final file = File(imagePath);

        if (!await file.exists()) {
          continue;
        }

        final bytes = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();

        final byteData = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );

        if (byteData != null) {
          loaded[imagePath] = _ImageAlphaMask(
            width: frame.image.width,
            height: frame.image.height,
            rgba: Uint8List.fromList(
              byteData.buffer.asUint8List(
                byteData.offsetInBytes,
                byteData.lengthInBytes,
              ),
            ),
          );
        }

        frame.image.dispose();
        codec.dispose();
      } catch (_) {
        // If an image cannot be decoded, leave it unmasked rather than
        // breaking Home/Decorate rendering.
      }
    }

    if (!mounted || loaded.isEmpty) {
      return;
    }

    setState(() {
      _imageAlphaMasks.addAll(loaded);
    });
  }

  List<VectorStroke> _bagItemStrokes(BagItem item) {
    final strokes = <VectorStroke>[];

    // Bag layers are stored top-to-bottom, matching the Workspace layer panel.
    // Paint bottom layers first so upper layers remain visually on top.
    for (final layer in item.layers.reversed) {
      if (!layer.visible) {
        continue;
      }

      for (final stroke in layer.strokes) {
        strokes.add(
          VectorStroke(
            points: stroke.points.map((point) => point.copy()).toList(),
            strokeWidth: stroke.strokeWidth,
            color: stroke.color.withValues(
              alpha: stroke.color.a * layer.opacity,
            ),
            filled: stroke.filled,
            brushType: stroke.brushType,
          ),
        );
      }
    }

    return strokes;
  }

  List<VectorPoint> _smoothVectorHitPoints(List<VectorPoint> source) {
    if (source.length < 3) {
      return source;
    }

    final smoothed = <VectorPoint>[source.first];

    for (var i = 1; i < source.length - 1; i++) {
      final previous = source[i - 1];
      final current = source[i];
      final next = source[i + 1];

      smoothed.add(
        VectorPoint(
          dx: (previous.dx * 0.25) + (current.dx * 0.50) + (next.dx * 0.25),
          dy: (previous.dy * 0.25) + (current.dy * 0.50) + (next.dy * 0.25),
          pressure:
              (previous.pressure * 0.25) +
              (current.pressure * 0.50) +
              (next.pressure * 0.25),
        ),
      );
    }

    smoothed.add(source.last);
    return smoothed;
  }

  double _vectorPressureWidth(VectorPoint point, double maximumWidth) {
    final pressure = point.pressure.clamp(0.0, 1.0);
    final response = math.pow(pressure, 1.35).toDouble();

    const minimumFactor = 0.015;

    final factor = minimumFactor + (response * (1.0 - minimumFactor));

    return maximumWidth * factor;
  }

  double _distanceToVectorSegment(Offset point, Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;

    final lengthSquared = (dx * dx) + (dy * dy);

    if (lengthSquared <= 0.000001) {
      return (point - start).distance;
    }

    final projection =
        (((point.dx - start.dx) * dx) + ((point.dy - start.dy) * dy)) /
        lengthSquared;

    final t = projection.clamp(0.0, 1.0);

    final nearest = Offset(start.dx + (dx * t), start.dy + (dy * t));

    return (point - nearest).distance;
  }

  bool _vectorStrokeHitTest(VectorStroke stroke, Offset point) {
    if (stroke.points.isEmpty) {
      return false;
    }

    // Finger-friendly tolerance in authored Composite coordinates.
    //
    // This is deliberately larger than the painted edge so thin linework
    // remains practical to select on a phone/tablet.
    const touchTolerance = 28.0;

    // --------------------------------------------------------
    // Filled artwork
    // --------------------------------------------------------

    if (stroke.filled) {
      if (stroke.points.length == 1) {
        final p = stroke.points.first;

        return (point - Offset(p.dx, p.dy)).distance <=
            (stroke.strokeWidth / 2) + touchTolerance;
      }

      if (stroke.points.length >= 3) {
        final path = Path()
          ..moveTo(stroke.points.first.dx, stroke.points.first.dy);

        for (var i = 1; i < stroke.points.length; i++) {
          final p = stroke.points[i];
          path.lineTo(p.dx, p.dy);
        }

        path.close();

        if (path.contains(point)) {
          return true;
        }

        // Also make the edge itself finger-friendly.
        for (var i = 0; i < stroke.points.length; i++) {
          final a = stroke.points[i];
          final b = stroke.points[(i + 1) % stroke.points.length];

          if (_distanceToVectorSegment(
                point,
                Offset(a.dx, a.dy),
                Offset(b.dx, b.dy),
              ) <=
              touchTolerance) {
            return true;
          }
        }
      }

      return false;
    }

    // --------------------------------------------------------
    // Normal / pressure-sensitive strokes
    // --------------------------------------------------------

    final points = _smoothVectorHitPoints(stroke.points);

    if (points.length == 1) {
      final p = points.first;

      final width = stroke.brushType == StrokeBrushType.pressure
          ? _vectorPressureWidth(p, stroke.strokeWidth)
          : stroke.strokeWidth;

      return (point - Offset(p.dx, p.dy)).distance <=
          (width / 2) + touchTolerance;
    }

    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];

      final startWidth = stroke.brushType == StrokeBrushType.pressure
          ? _vectorPressureWidth(start, stroke.strokeWidth)
          : stroke.strokeWidth;

      final endWidth = stroke.brushType == StrokeBrushType.pressure
          ? _vectorPressureWidth(end, stroke.strokeWidth)
          : stroke.strokeWidth;

      final hitRadius = (math.max(startWidth, endWidth) / 2) + touchTolerance;

      if (_distanceToVectorSegment(
            point,
            Offset(start.dx, start.dy),
            Offset(end.dx, end.dy),
          ) <=
          hitRadius) {
        return true;
      }
    }

    return false;
  }

  // --------------------------------------------------------
  // ROOMS AWAKEN #9 - SCOPED HIERARCHY NAVIGATION
  // --------------------------------------------------------

  CompositeAsset? get _editingRoomComposite {
    final decorationId = _editingRoomDecorationId;

    if (decorationId == null) {
      return null;
    }

    PlacedDecoration? decoration;

    for (final candidate in _decorations) {
      if (candidate.id == decorationId) {
        decoration = candidate;
        break;
      }
    }

    if (decoration == null) {
      return null;
    }

    return _bagItemsById[decoration.bagItemId]?.composite;
  }

  CompositeNode? _findCompositeNodeByIdScoped(CompositeNode node, String id) {
    if (node.id == id) {
      return node;
    }

    for (final child in node.children) {
      final found = _findCompositeNodeByIdScoped(child, id);

      if (found != null) {
        return found;
      }
    }

    return null;
  }

  CompositeNode? get _currentRoomScopeNode {
    final composite = _editingRoomComposite;

    if (composite == null) {
      return null;
    }

    if (_roomScopeNodeIds.isEmpty) {
      return composite.root;
    }

    final scopeId = _roomScopeNodeIds.last;

    return _findCompositeNodeByIdScoped(composite.root, scopeId) ??
        composite.root;
  }

  String get _currentRoomScopeName {
    final scope = _currentRoomScopeNode;

    if (scope == null || _roomScopeNodeIds.isEmpty) {
      return 'Room';
    }

    final name = scope.name.trim();
    return name.isEmpty ? 'Group' : name;
  }

  List<CompositeNode> get _currentRoomScopeChildren {
    final scope = _currentRoomScopeNode;

    if (scope == null) {
      return const <CompositeNode>[];
    }

    return scope.children.where((child) => child.visible).toList();
  }

  CompositeNode? get _selectedRoomNodeInScope {
    final selectedId = _selectedRoomNodeId;

    if (selectedId == null) {
      return null;
    }

    for (final child in _currentRoomScopeChildren) {
      if (child.id == selectedId) {
        return child;
      }
    }

    return null;
  }

  bool get _canEnterSelectedRoomNode {
    final selected = _selectedRoomNodeInScope;

    if (selected == null) {
      return false;
    }

    // Groups are true hierarchy containers.
    //
    // Variant Slots remain state-switchers rather than navigation scopes.
    return selected.type == 'group' && selected.children.isNotEmpty;
  }

  bool get _canGoBackRoomScope => _roomScopeNodeIds.isNotEmpty;

  void _enterSelectedRoomNode() {
    final selected = _selectedRoomNodeInScope;

    if (selected == null ||
        selected.type != 'group' ||
        selected.children.isEmpty) {
      return;
    }

    setState(() {
      _roomScopeNodeIds.add(selected.id);
      _selectedRoomNodeId = null;
      _selectedRoomNodeName = null;
    });
  }

  void _backRoomScope() {
    if (_roomScopeNodeIds.isEmpty) {
      _exitRoomContents();
      return;
    }

    setState(() {
      _roomScopeNodeIds.removeLast();
      _selectedRoomNodeId = null;
      _selectedRoomNodeName = null;
    });
  }

  void _cycleRoomScopeSelection(int direction) {
    final children = _currentRoomScopeChildren;

    if (children.isEmpty) {
      return;
    }

    var currentIndex = children.indexWhere(
      (child) => child.id == _selectedRoomNodeId,
    );

    if (currentIndex < 0) {
      currentIndex = direction >= 0 ? -1 : 0;
    }

    final nextIndex = (currentIndex + direction) % children.length;

    final selected = children[nextIndex];

    setState(() {
      _selectedRoomNodeId = selected.id;
      _selectedRoomNodeName = selected.name.trim().isEmpty
          ? selected.type
          : selected.name;
    });
  }

  CompositeNode? _findScopedCompositeHit({
    required CompositeNode scope,
    required Offset point,
    required Size canvasSize,
    required String decorationId,
  }) {
    // Only direct children of the active scope can become selected.
    //
    // The existing recursive hit tester is still used to determine whether
    // the touch lands anywhere inside each direct child's visible content.
    // If it does, selection resolves back to that direct child.
    for (final child in scope.children) {
      if (!child.visible) {
        continue;
      }

      final hit = _findCompositeNodeHit(
        child,
        point,
        canvasSize,
        decorationId: decorationId,
        semanticOwner: child,
      );

      if (hit != null) {
        return child;
      }
    }

    return null;
  }

  CompositeNode? _findCompositeNodeHit(
    CompositeNode node,
    Offset point,
    Size canvasSize, {
    required String decorationId,
    CompositeNode? semanticOwner,
  }) {
    if (!node.visible) {
      return null;
    }

    final nodeOverride = _roomNodeOverrideFor(decorationId, node.id);

    final nodePoint = _inverseRoomNodeOverridePoint(
      point: point,
      canvasSize: canvasSize,
      override: nodeOverride,
    );

    if (node.type == 'group') {
      final owner = node.name.trim().isNotEmpty ? node : semanticOwner;

      // Composite children are stored front-to-back.
      for (final child in node.children) {
        final hit = _findCompositeNodeHit(
          child,
          nodePoint,
          canvasSize,
          decorationId: decorationId,
          semanticOwner: owner,
        );

        if (hit != null) {
          return hit;
        }
      }

      return null;
    }

    if (node.type == 'variant') {
      if (node.children.isEmpty) {
        return null;
      }

      final activeIndex = _activeRoomVariantIndex(decorationId, node);

      return _findCompositeNodeHit(
        node.children[activeIndex],
        nodePoint,
        canvasSize,
        decorationId: decorationId,
        semanticOwner: semanticOwner,
      );
    }

    if (node.type == 'reference') {
      final mediaPath = node.payload['mediaPath']?.toString() ?? '';
      final mediaType = node.payload['mediaType']?.toString() ?? 'image';

      if (mediaType != 'image' || mediaPath.isEmpty) {
        return null;
      }

      final mask = _imageAlphaMasks[mediaPath];

      // Until the mask is ready, do not let a giant transparent reference
      // rectangle steal selection from objects underneath it.
      if (mask == null) {
        return null;
      }

      final offsetX = (node.payload['offsetX'] as num?)?.toDouble() ?? 0.0;
      final offsetY = (node.payload['offsetY'] as num?)?.toDouble() ?? 0.0;
      final rotation = (node.payload['rotation'] as num?)?.toDouble() ?? 0.0;
      final scaleX = (node.payload['scaleX'] as num?)?.toDouble() ?? 1.0;
      final scaleY = (node.payload['scaleY'] as num?)?.toDouble() ?? 1.0;

      if (scaleX.abs() < 0.000001 || scaleY.abs() < 0.000001) {
        return null;
      }

      final center = Offset(canvasSize.width / 2, canvasSize.height / 2);

      // Undo Transform.translate.
      var local = nodePoint - Offset(offsetX, offsetY);

      // Move into centre-relative coordinates.
      local -= center;

      // Undo Transform.rotate.
      if (rotation != 0.0) {
        final c = math.cos(-rotation);
        final s = math.sin(-rotation);

        local = Offset(
          (local.dx * c) - (local.dy * s),
          (local.dx * s) + (local.dy * c),
        );
      }

      // Undo Transform.scale.
      local = Offset(local.dx / scaleX, local.dy / scaleY);

      local += center;

      final hit = mask.hitTest(local, canvasSize, mirrored: false);

      if (!hit) {
        return null;
      }

      return semanticOwner ?? node;
    }

    if (node.type == 'layer') {
      final strokes = _compositeLayerStrokes(node);

      // Walk frontmost stroke first so overlapping artwork behaves
      // like the visible painting order.
      for (final stroke in strokes.reversed) {
        if (!_vectorStrokeHitTest(stroke, nodePoint)) {
          continue;
        }

        // Prefer a specifically named layer such as Sofa, Plant, Lamp,
        // etc. If the layer itself has no useful name, fall back to the
        // nearest semantic parent group.
        if (node.name.trim().isNotEmpty) {
          return node;
        }

        return semanticOwner ?? node;
      }

      return null;
    }

    return null;
  }

  // ignore: unused_element
  void _selectCompositeRoomChild({
    required PlacedDecoration decoration,
    required BagItem bagItem,
    required Offset localPosition,
    required Size decorationSize,
  }) {
    if (!_isEditingRoomContents ||
        decoration.id != _editingRoomDecorationId ||
        !bagItem.isComposite) {
      return;
    }

    final composite = bagItem.composite;

    if (composite == null ||
        composite.canvasWidth <= 0 ||
        composite.canvasHeight <= 0 ||
        decorationSize.width <= 0 ||
        decorationSize.height <= 0) {
      return;
    }

    // The selected border adds a 2px Padding around the rendered room.
    // Convert from the GestureDetector's box into that inner render box.
    const selectionPadding = 2.0;

    final innerWidth = (decorationSize.width - (selectionPadding * 2)).clamp(
      1.0,
      double.infinity,
    );
    final innerHeight = (decorationSize.height - (selectionPadding * 2)).clamp(
      1.0,
      double.infinity,
    );

    var innerPoint = Offset(
      localPosition.dx - selectionPadding,
      localPosition.dy - selectionPadding,
    );

    // Undo the placed room mirror around its centre.
    if (decoration.mirrored) {
      innerPoint = Offset(innerWidth - innerPoint.dx, innerPoint.dy);
    }

    // _buildCompositeDecoration uses BoxFit.contain.
    final fitScaleX = innerWidth / composite.canvasWidth;
    final fitScaleY = innerHeight / composite.canvasHeight;
    final fitScale = fitScaleX < fitScaleY ? fitScaleX : fitScaleY;

    if (fitScale <= 0) {
      return;
    }

    final renderedWidth = composite.canvasWidth * fitScale;
    final renderedHeight = composite.canvasHeight * fitScale;

    final fittedLeft = (innerWidth - renderedWidth) / 2;
    final fittedTop = (innerHeight - renderedHeight) / 2;

    if (innerPoint.dx < fittedLeft ||
        innerPoint.dy < fittedTop ||
        innerPoint.dx >= fittedLeft + renderedWidth ||
        innerPoint.dy >= fittedTop + renderedHeight) {
      setState(() {
        _selectedRoomNodeId = null;
        _selectedRoomNodeName = null;
      });
      return;
    }

    final compositePoint = Offset(
      (innerPoint.dx - fittedLeft) / fitScale,
      (innerPoint.dy - fittedTop) / fitScale,
    );

    final scope = _currentRoomScopeNode ?? composite.root;

    final hit = _findScopedCompositeHit(
      scope: scope,
      point: compositePoint,
      canvasSize: Size(composite.canvasWidth, composite.canvasHeight),
      decorationId: decoration.id,
    );

    setState(() {
      _selectedRoomNodeId = hit?.id;
      _selectedRoomNodeName = hit == null
          ? null
          : (hit.name.trim().isEmpty ? hit.type : hit.name);
    });
  }

  // ignore: unused_element
  void _dragCompositeRoomChild({
    required PlacedDecoration decoration,
    required BagItem bagItem,
    required Offset delta,
    required Size decorationSize,
  }) {
    if (!_isEditingRoomContents ||
        decoration.id != _editingRoomDecorationId ||
        _selectedRoomNodeId == null ||
        !bagItem.isComposite) {
      return;
    }

    final composite = bagItem.composite;

    if (composite == null ||
        composite.canvasWidth <= 0 ||
        composite.canvasHeight <= 0 ||
        decorationSize.width <= 0 ||
        decorationSize.height <= 0) {
      return;
    }

    // Match the selected-room render padding used by
    // _selectCompositeRoomChild.
    const selectionPadding = 2.0;

    final innerWidth = (decorationSize.width - (selectionPadding * 2)).clamp(
      1.0,
      double.infinity,
    );

    final innerHeight = (decorationSize.height - (selectionPadding * 2)).clamp(
      1.0,
      double.infinity,
    );

    // _buildCompositeDecoration renders with BoxFit.contain.
    // Convert the gesture delta from displayed room pixels back into
    // authored Composite coordinates before storing the node override.
    final fitScaleX = innerWidth / composite.canvasWidth;
    final fitScaleY = innerHeight / composite.canvasHeight;
    final fitScale = fitScaleX < fitScaleY ? fitScaleX : fitScaleY;

    if (fitScale <= 0) {
      return;
    }

    var compositeDx = delta.dx / fitScale;
    final compositeDy = delta.dy / fitScale;

    // The entire placed room may itself be mirrored.
    // Because node overrides live in authored Composite coordinates,
    // horizontal dragging must be inverted when the outer room is mirrored.
    if (decoration.mirrored) {
      compositeDx = -compositeDx;
    }

    _nudgeSelectedRoomNode(compositeDx, compositeDy, persist: false);
  }

  Map<String, dynamic> _roomNodeOverrideToJson(_RoomNodeOverride override) {
    return <String, dynamic>{
      'offsetX': override.offsetX,
      'offsetY': override.offsetY,
      'scale': override.scale,
      'mirrored': override.mirrored,
      if (override.activeVariantIndex != null)
        'activeVariantIndex': override.activeVariantIndex,
    };
  }

  _RoomNodeOverride _roomNodeOverrideFromJson(Map<String, dynamic> json) {
    return _RoomNodeOverride(
      offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0.0,
      offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0.0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      mirrored: json['mirrored'] == true,
      activeVariantIndex: (json['activeVariantIndex'] as num?)?.toInt(),
    );
  }

  Map<String, Map<String, dynamic>> _serializedRoomOverridesFor(
    String decorationId,
  ) {
    final overrides = _roomNodeOverrides[decorationId];

    if (overrides == null || overrides.isEmpty) {
      return const <String, Map<String, dynamic>>{};
    }

    return <String, Map<String, dynamic>>{
      for (final entry in overrides.entries)
        entry.key: _roomNodeOverrideToJson(entry.value),
    };
  }

  _RoomNodeOverride _roomNodeOverrideFor(String? decorationId, String nodeId) {
    if (decorationId == null) {
      return const _RoomNodeOverride();
    }

    return _roomNodeOverrides[decorationId]?[nodeId] ??
        const _RoomNodeOverride();
  }

  // ignore: unused_element
  CompositeNode? _findCompositeNodeById(CompositeNode node, String nodeId) {
    if (node.id == nodeId) {
      return node;
    }

    for (final child in node.children) {
      final match = _findCompositeNodeById(child, nodeId);

      if (match != null) {
        return match;
      }
    }

    return null;
  }

  List<CompositeNode> _variantNodesForSelectedRoomNode() {
    final item = _selectedDecorationBagItem;
    final composite = item?.composite;

    if (!_isEditingRoomContents || composite == null) {
      return const <CompositeNode>[];
    }

    final variants = <CompositeNode>[];

    void collect(CompositeNode node) {
      if (!node.visible) {
        return;
      }

      if (node.type == 'variant') {
        if (node.children.isNotEmpty) {
          variants.add(node);
        }

        // A Variant node is a sealed configurable slot.
        // Room Manager may switch its authored alternatives, but it does not
        // expose or edit the Composite hierarchy itself.
        return;
      }

      for (final child in node.children) {
        collect(child);
      }
    }

    collect(composite.root);

    return variants;
  }

  List<CompositeNode> get _selectedRoomVariantNodes =>
      _variantNodesForSelectedRoomNode();

  int _activeRoomVariantIndex(String? decorationId, CompositeNode variantNode) {
    if (variantNode.children.isEmpty) {
      return 0;
    }

    final authored = (variantNode.payload['activeIndex'] as num?)?.toInt() ?? 0;

    final override = _roomNodeOverrideFor(decorationId, variantNode.id);

    final requested = override.activeVariantIndex ?? authored;

    return requested.clamp(0, variantNode.children.length - 1);
  }

  String _roomVariantSlotName(CompositeNode variantNode) {
    final name = variantNode.name.trim();

    if (name.isNotEmpty) {
      return name;
    }

    return 'Variant';
  }

  String _roomVariantChoiceName(CompositeNode variantNode) {
    final decorationId = _editingRoomDecorationId;

    if (decorationId == null || variantNode.children.isEmpty) {
      return 'None';
    }

    final activeIndex = _activeRoomVariantIndex(decorationId, variantNode);

    final activeChild = variantNode.children[activeIndex];
    final childName = activeChild.name.trim();

    if (childName.isNotEmpty) {
      return childName;
    }

    return '${activeIndex + 1}';
  }

  String _roomVariantLabel(CompositeNode variantNode) {
    return '${_roomVariantSlotName(variantNode)}: '
        '${_roomVariantChoiceName(variantNode)}';
  }

  // ignore: unused_element
  void _stepRoomVariant(CompositeNode variantNode, int delta) {
    final decorationId = _editingRoomDecorationId;

    if (decorationId == null || variantNode.children.isEmpty) {
      return;
    }

    final currentIndex = _activeRoomVariantIndex(decorationId, variantNode);

    final count = variantNode.children.length;
    final nextIndex = (currentIndex + delta) % count;
    final safeNextIndex = nextIndex < 0 ? nextIndex + count : nextIndex;

    _setRoomVariantChoice(variantNode, safeNextIndex);
  }

  void _setRoomVariantChoice(CompositeNode variantNode, int index) {
    final decorationId = _editingRoomDecorationId;

    if (decorationId == null || variantNode.children.isEmpty) {
      return;
    }

    final safeIndex = index.clamp(0, variantNode.children.length - 1);

    setState(() {
      final roomOverrides = _roomNodeOverrides.putIfAbsent(
        decorationId,
        () => <String, _RoomNodeOverride>{},
      );

      final current =
          roomOverrides[variantNode.id] ?? const _RoomNodeOverride();

      roomOverrides[variantNode.id] = current.copyWith(
        activeVariantIndex: safeIndex,
      );
    });

    _saveDecorations();
  }

  void _resetRoomVariantChoice(CompositeNode variantNode) {
    final decorationId = _editingRoomDecorationId;

    if (decorationId == null) {
      return;
    }

    setState(() {
      final roomOverrides = _roomNodeOverrides[decorationId];

      if (roomOverrides == null) {
        return;
      }

      final current = roomOverrides[variantNode.id];

      if (current == null) {
        return;
      }

      final reset = _RoomNodeOverride(
        offsetX: current.offsetX,
        offsetY: current.offsetY,
        scale: current.scale,
        mirrored: current.mirrored,
      );

      if (reset.isIdentity) {
        roomOverrides.remove(variantNode.id);
      } else {
        roomOverrides[variantNode.id] = reset;
      }

      if (roomOverrides.isEmpty) {
        _roomNodeOverrides.remove(decorationId);
      }
    });

    _saveDecorations();
  }

  Future<void> _showRoomVariantPicker(CompositeNode variantNode) async {
    final decorationId = _editingRoomDecorationId;

    if (decorationId == null || variantNode.children.isEmpty) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final activeIndex = _activeRoomVariantIndex(
              decorationId,
              variantNode,
            );

            final authoredIndex =
                ((variantNode.payload['activeIndex'] as num?)?.toInt() ?? 0)
                    .clamp(0, variantNode.children.length - 1);

            final hasInstanceOverride =
                _roomNodeOverrides[decorationId]?[variantNode.id]
                    ?.activeVariantIndex !=
                null;

            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF171717),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.amberAccent.withValues(alpha: 0.7),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 24,
                      spreadRadius: 2,
                      color: Colors.black54,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_mosaic_outlined,
                          color: Colors.amberAccent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _roomVariantSlotName(variantNode),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (
                              var index = 0;
                              index < variantNode.children.length;
                              index++
                            )
                              Builder(
                                builder: (context) {
                                  final child = variantNode.children[index];
                                  final label = child.name.trim().isNotEmpty
                                      ? child.name.trim()
                                      : 'Choice ${index + 1}';
                                  final selected = index == activeIndex;
                                  final authored = index == authoredIndex;

                                  return InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () {
                                      _setRoomVariantChoice(variantNode, index);
                                      setSheetState(() {});
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      width: 150,
                                      constraints: const BoxConstraints(
                                        minHeight: 118,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? Colors.amberAccent.withValues(
                                                alpha: 0.13,
                                              )
                                            : Colors.white.withValues(
                                                alpha: 0.045,
                                              ),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: selected
                                              ? Colors.amberAccent
                                              : Colors.white24,
                                          width: selected ? 2 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            height: 72,
                                            width: double.infinity,
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                _buildRoomVariantPreview(
                                                  variantNode,
                                                  index,
                                                ),
                                                if (selected)
                                                  Positioned(
                                                    right: 5,
                                                    top: 5,
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            2,
                                                          ),
                                                      decoration:
                                                          const BoxDecoration(
                                                            color:
                                                                Colors.black87,
                                                            shape:
                                                                BoxShape.circle,
                                                          ),
                                                      child: const Icon(
                                                        Icons.check_circle,
                                                        size: 22,
                                                        color:
                                                            Colors.amberAccent,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            label,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: selected
                                                  ? Colors.amberAccent
                                                  : Colors.white,
                                              fontWeight: selected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                          if (authored) ...[
                                            const SizedBox(height: 4),
                                            const Text(
                                              'Authored',
                                              style: TextStyle(
                                                color: Colors.white54,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (hasInstanceOverride) ...[
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            _resetRoomVariantChoice(variantNode);
                            setSheetState(() {});
                          },
                          icon: const Icon(
                            Icons.restart_alt,
                            color: Colors.amberAccent,
                          ),
                          label: const Text(
                            'Reset to authored',
                            style: TextStyle(color: Colors.amberAccent),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _updateSelectedRoomNodeOverride(
    _RoomNodeOverride Function(_RoomNodeOverride current) update, {
    bool persist = true,
  }) {
    final decorationId = _editingRoomDecorationId;
    final nodeId = _selectedRoomNodeId;

    if (decorationId == null || nodeId == null) {
      return;
    }

    setState(() {
      final roomOverrides = _roomNodeOverrides.putIfAbsent(
        decorationId,
        () => <String, _RoomNodeOverride>{},
      );

      final current = roomOverrides[nodeId] ?? const _RoomNodeOverride();

      final next = update(current);

      if (next.isIdentity) {
        roomOverrides.remove(nodeId);

        if (roomOverrides.isEmpty) {
          _roomNodeOverrides.remove(decorationId);
        }
      } else {
        roomOverrides[nodeId] = next;
      }
    });

    if (persist) {
      _saveDecorations();
    }
  }

  void _nudgeSelectedRoomNode(double dx, double dy, {bool persist = true}) {
    _updateSelectedRoomNodeOverride(
      (current) => current.copyWith(
        offsetX: current.offsetX + dx,
        offsetY: current.offsetY + dy,
      ),
      persist: persist,
    );
  }

  void _scaleSelectedRoomNode(double factor) {
    _updateSelectedRoomNodeOverride(
      (current) =>
          current.copyWith(scale: (current.scale * factor).clamp(0.1, 10.0)),
    );
  }

  void _mirrorSelectedRoomNode() {
    _updateSelectedRoomNodeOverride(
      (current) => current.copyWith(mirrored: !current.mirrored),
    );
  }

  void _resetSelectedRoomNodeOverride() {
    final decorationId = _editingRoomDecorationId;
    final nodeId = _selectedRoomNodeId;

    if (decorationId == null || nodeId == null) {
      return;
    }

    setState(() {
      final roomOverrides = _roomNodeOverrides[decorationId];

      roomOverrides?.remove(nodeId);

      if (roomOverrides != null && roomOverrides.isEmpty) {
        _roomNodeOverrides.remove(decorationId);
      }
    });

    _saveDecorations();
  }

  Offset _inverseRoomNodeOverridePoint({
    required Offset point,
    required Size canvasSize,
    required _RoomNodeOverride override,
  }) {
    if (override.isIdentity) {
      return point;
    }

    var local = point - Offset(override.offsetX, override.offsetY);

    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);

    local -= center;

    final signedScaleX = override.mirrored ? -override.scale : override.scale;

    if (signedScaleX.abs() < 0.000001 || override.scale.abs() < 0.000001) {
      return point;
    }

    local = Offset(local.dx / signedScaleX, local.dy / override.scale);

    return local + center;
  }

  Widget _applyRoomNodeOverride({
    required CompositeNode node,
    required Widget child,
    required String? decorationId,
  }) {
    final override = _roomNodeOverrideFor(decorationId, node.id);

    if (override.isIdentity) {
      return child;
    }

    Widget result = Transform.scale(
      scaleX: override.mirrored ? -override.scale : override.scale,
      scaleY: override.scale,
      alignment: Alignment.center,
      child: child,
    );

    result = Transform.translate(
      offset: Offset(override.offsetX, override.offsetY),
      child: result,
    );

    return result;
  }

  List<VectorStroke> _compositeLayerStrokes(CompositeNode node) {
    final rawFrames = node.payload['frames'];

    if (rawFrames is! List || rawFrames.isEmpty) {
      return <VectorStroke>[];
    }

    final rawFrame = rawFrames.first;

    if (rawFrame is! List) {
      return <VectorStroke>[];
    }

    final layerOpacity =
        (node.payload['opacity'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 1.0;

    final strokes = <VectorStroke>[];

    for (final rawStroke in rawFrame) {
      if (rawStroke is! Map) {
        continue;
      }

      final stroke = VectorStroke.fromJson(
        Map<String, dynamic>.from(rawStroke),
      );

      strokes.add(
        VectorStroke(
          points: stroke.points.map((point) => point.copy()).toList(),
          strokeWidth: stroke.strokeWidth,
          color: stroke.color.withValues(alpha: stroke.color.a * layerOpacity),
          filled: stroke.filled,
          brushType: stroke.brushType,
        ),
      );
    }

    return strokes;
  }

  Widget _buildCompositeNode(
    CompositeNode node, {
    required CompositeAsset asset,
    required String? decorationId,
  }) {
    if (!node.visible) {
      return const SizedBox.shrink();
    }

    if (node.type == 'group') {
      return _applyRoomNodeOverride(
        node: node,
        decorationId: decorationId,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Composite children are stored front-to-back, matching the
            // Workspace Layers panel. Stack paints first-to-last, so reverse.
            for (final child in node.children.reversed)
              _buildCompositeNode(
                child,
                asset: asset,
                decorationId: decorationId,
              ),
          ],
        ),
      );
    }

    if (node.type == 'variant') {
      if (node.children.isEmpty) {
        return const SizedBox.shrink();
      }

      final activeIndex = _activeRoomVariantIndex(decorationId, node);

      return _applyRoomNodeOverride(
        node: node,
        decorationId: decorationId,
        child: _buildCompositeNode(
          node.children[activeIndex],
          asset: asset,
          decorationId: decorationId,
        ),
      );
    }

    if (node.type == 'layer') {
      final strokes = _compositeLayerStrokes(node);

      if (strokes.isEmpty) {
        return const SizedBox.shrink();
      }

      return _applyRoomNodeOverride(
        node: node,
        decorationId: decorationId,
        child: CustomPaint(
          painter: AnimationCanvasPainter(
            strokes: strokes,
            currentStroke: null,
            previousOnionSkinStrokes: const <VectorStroke>[],
            nextOnionSkinStrokes: const <VectorStroke>[],
            strokeColor: Colors.transparent,
            strokeWidth: 1.0,
            brushType: StrokeBrushType.solid,
            backgroundColor: Colors.transparent,
            paintBackground: false,
            previousOnionSkinColor: Colors.transparent,
            nextOnionSkinColor: Colors.transparent,
          ),
          child: const SizedBox.expand(),
        ),
      );
    }

    if (node.type == 'reference') {
      final mediaPath = node.payload['mediaPath']?.toString() ?? '';
      final mediaType = node.payload['mediaType']?.toString() ?? 'image';

      // Home V1 renders still-image Composite references.
      // Video Composite references remain preserved in the structured asset
      // and can be activated by the future interactive-room renderer.
      if (mediaType != 'image' || mediaPath.isEmpty) {
        return const SizedBox.shrink();
      }

      final opacity =
          (node.payload['opacity'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 1.0;

      final offsetX = (node.payload['offsetX'] as num?)?.toDouble() ?? 0.0;

      final offsetY = (node.payload['offsetY'] as num?)?.toDouble() ?? 0.0;

      final rotation = (node.payload['rotation'] as num?)?.toDouble() ?? 0.0;

      final scaleX = (node.payload['scaleX'] as num?)?.toDouble() ?? 1.0;

      final scaleY = (node.payload['scaleY'] as num?)?.toDouble() ?? 1.0;

      return _applyRoomNodeOverride(
        node: node,
        decorationId: decorationId,
        child: Transform.translate(
          offset: Offset(offsetX, offsetY),
          child: Transform.rotate(
            angle: rotation,
            alignment: Alignment.center,
            child: Transform.scale(
              scaleX: scaleX,
              scaleY: scaleY,
              alignment: Alignment.center,
              child: Opacity(
                opacity: opacity,
                child: Image.file(
                  File(mediaPath),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Rect? _unionRects(Rect? a, Rect? b) {
    if (a == null) return b;
    if (b == null) return a;

    return Rect.fromLTRB(
      a.left < b.left ? a.left : b.left,
      a.top < b.top ? a.top : b.top,
      a.right > b.right ? a.right : b.right,
      a.bottom > b.bottom ? a.bottom : b.bottom,
    );
  }

  Rect? _alphaMaskVisibleBounds(_ImageAlphaMask mask) {
    if (mask.width <= 0 || mask.height <= 0 || mask.rgba.isEmpty) {
      return null;
    }

    var minX = mask.width;
    var minY = mask.height;
    var maxX = -1;
    var maxY = -1;

    const threshold = 24;

    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        final alphaIndex = ((y * mask.width) + x) * 4 + 3;

        if (alphaIndex < 0 || alphaIndex >= mask.rgba.length) {
          continue;
        }

        if (mask.rgba[alphaIndex] < threshold) {
          continue;
        }

        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }

    if (maxX < minX || maxY < minY) {
      return null;
    }

    return Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );
  }

  Offset _rotatePointAroundCenter(
    Offset point,
    Offset center,
    double rotation,
  ) {
    final translated = point - center;

    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);

    return Offset(
          (translated.dx * cosR) - (translated.dy * sinR),
          (translated.dx * sinR) + (translated.dy * cosR),
        ) +
        center;
  }

  Rect _transformPreviewRect({
    required Rect rect,
    required Size canvasSize,
    double offsetX = 0.0,
    double offsetY = 0.0,
    double rotation = 0.0,
    double scaleX = 1.0,
    double scaleY = 1.0,
  }) {
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);

    Offset transformPoint(Offset point) {
      var transformed = Offset(
        center.dx + ((point.dx - center.dx) * scaleX),
        center.dy + ((point.dy - center.dy) * scaleY),
      );

      transformed = _rotatePointAroundCenter(transformed, center, rotation);

      return transformed + Offset(offsetX, offsetY);
    }

    final points = <Offset>[
      transformPoint(rect.topLeft),
      transformPoint(rect.topRight),
      transformPoint(rect.bottomLeft),
      transformPoint(rect.bottomRight),
    ];

    var minX = points.first.dx;
    var minY = points.first.dy;
    var maxX = points.first.dx;
    var maxY = points.first.dy;

    for (final point in points.skip(1)) {
      if (point.dx < minX) minX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy > maxY) maxY = point.dy;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Rect? _compositeNodePreviewBounds(
    CompositeNode node,
    CompositeAsset asset, {
    String? decorationId,
  }) {
    if (!node.visible) {
      return null;
    }

    final canvasSize = Size(asset.canvasWidth, asset.canvasHeight);

    if (node.type == 'group') {
      Rect? bounds;

      for (final child in node.children) {
        bounds = _unionRects(
          bounds,
          _compositeNodePreviewBounds(child, asset, decorationId: decorationId),
        );
      }

      return bounds;
    }

    if (node.type == 'variant') {
      if (node.children.isEmpty) {
        return null;
      }

      final safeIndex = decorationId == null
          ? ((node.payload['activeIndex'] as num?)?.toInt() ?? 0).clamp(
              0,
              node.children.length - 1,
            )
          : _activeRoomVariantIndex(decorationId, node);

      return _compositeNodePreviewBounds(
        node.children[safeIndex],
        asset,
        decorationId: decorationId,
      );
    }

    if (node.type == 'layer') {
      final strokes = _compositeLayerStrokes(node);

      if (strokes.isEmpty) {
        return null;
      }

      Rect? bounds;

      for (final stroke in strokes) {
        if (stroke.points.isEmpty) {
          continue;
        }

        var minX = stroke.points.first.dx;
        var minY = stroke.points.first.dy;
        var maxX = stroke.points.first.dx;
        var maxY = stroke.points.first.dy;

        for (final point in stroke.points.skip(1)) {
          if (point.dx < minX) minX = point.dx;
          if (point.dy < minY) minY = point.dy;
          if (point.dx > maxX) maxX = point.dx;
          if (point.dy > maxY) maxY = point.dy;
        }

        final padding = stroke.strokeWidth / 2;

        final strokeBounds = Rect.fromLTRB(
          minX - padding,
          minY - padding,
          maxX + padding,
          maxY + padding,
        );

        bounds = _unionRects(bounds, strokeBounds);
      }

      return bounds;
    }

    if (node.type == 'reference') {
      final mediaPath = node.payload['mediaPath']?.toString() ?? '';

      final mediaType = node.payload['mediaType']?.toString() ?? 'image';

      if (mediaType != 'image' || mediaPath.isEmpty) {
        return null;
      }

      final mask = _imageAlphaMasks[mediaPath];

      if (mask == null || mask.width <= 0 || mask.height <= 0) {
        return null;
      }

      final alphaBounds = _alphaMaskVisibleBounds(mask);

      if (alphaBounds == null) {
        return null;
      }

      final imageScale =
          asset.canvasWidth / mask.width < asset.canvasHeight / mask.height
          ? asset.canvasWidth / mask.width
          : asset.canvasHeight / mask.height;

      final renderedWidth = mask.width * imageScale;
      final renderedHeight = mask.height * imageScale;

      final imageLeft = (asset.canvasWidth - renderedWidth) / 2;
      final imageTop = (asset.canvasHeight - renderedHeight) / 2;

      final baseRect = Rect.fromLTRB(
        imageLeft + alphaBounds.left * imageScale,
        imageTop + alphaBounds.top * imageScale,
        imageLeft + alphaBounds.right * imageScale,
        imageTop + alphaBounds.bottom * imageScale,
      );

      final offsetX = (node.payload['offsetX'] as num?)?.toDouble() ?? 0.0;
      final offsetY = (node.payload['offsetY'] as num?)?.toDouble() ?? 0.0;
      final rotation = (node.payload['rotation'] as num?)?.toDouble() ?? 0.0;
      final scaleX = (node.payload['scaleX'] as num?)?.toDouble() ?? 1.0;
      final scaleY = (node.payload['scaleY'] as num?)?.toDouble() ?? 1.0;

      return _transformPreviewRect(
        rect: baseRect,
        canvasSize: canvasSize,
        offsetX: offsetX,
        offsetY: offsetY,
        rotation: rotation,
        scaleX: scaleX,
        scaleY: scaleY,
      );
    }

    return null;
  }

  Rect _expandedPreviewBounds(Rect bounds, Size canvasSize) {
    final paddingX = bounds.width * 0.14;
    final paddingY = bounds.height * 0.14;

    final padded = Rect.fromLTRB(
      bounds.left - paddingX,
      bounds.top - paddingY,
      bounds.right + paddingX,
      bounds.bottom + paddingY,
    );

    return Rect.fromLTRB(
      padded.left.clamp(0.0, canvasSize.width),
      padded.top.clamp(0.0, canvasSize.height),
      padded.right.clamp(0.0, canvasSize.width),
      padded.bottom.clamp(0.0, canvasSize.height),
    );
  }

  Widget _buildRoomVariantPreview(CompositeNode variantNode, int index) {
    final item = _selectedDecorationBagItem;
    final composite = item?.composite;

    if (composite == null ||
        composite.canvasWidth <= 0 ||
        composite.canvasHeight <= 0 ||
        index < 0 ||
        index >= variantNode.children.length) {
      return const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 30,
          color: Colors.white38,
        ),
      );
    }

    final choice = variantNode.children[index];

    final canvasSize = Size(composite.canvasWidth, composite.canvasHeight);

    final rawBounds = _compositeNodePreviewBounds(choice, composite);

    if (rawBounds == null || rawBounds.width <= 0 || rawBounds.height <= 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ColoredBox(
          color: Colors.black26,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: composite.canvasWidth,
              height: composite.canvasHeight,
              child: _buildCompositeNode(
                choice,
                asset: composite,
                decorationId: null,
              ),
            ),
          ),
        ),
      );
    }

    final bounds = _expandedPreviewBounds(rawBounds, canvasSize);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: Colors.black26,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
              return const SizedBox.shrink();
            }

            final scaleX = constraints.maxWidth / bounds.width;
            final scaleY = constraints.maxHeight / bounds.height;

            final previewScale = scaleX < scaleY ? scaleX : scaleY;

            final left =
                ((constraints.maxWidth - bounds.width * previewScale) / 2) -
                (bounds.left * previewScale);

            final top =
                ((constraints.maxHeight - bounds.height * previewScale) / 2) -
                (bounds.top * previewScale);

            return ClipRect(
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: left,
                    top: top,
                    child: Transform.scale(
                      scale: previewScale,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: composite.canvasWidth,
                        height: composite.canvasHeight,
                        child: _buildCompositeNode(
                          choice,
                          asset: composite,
                          decorationId: null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCroppedCompositeDecoration(
    BagItem item, {
    required PlacedDecoration decoration,
    required Rect visibleBounds,
    required double sceneScale,
  }) {
    final composite = item.composite;

    if (composite == null ||
        composite.canvasWidth <= 0 ||
        composite.canvasHeight <= 0 ||
        visibleBounds.width <= 0 ||
        visibleBounds.height <= 0) {
      return const SizedBox.shrink();
    }

    return ClipRect(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: -visibleBounds.left * sceneScale,
            top: -visibleBounds.top * sceneScale,
            child: Transform.scale(
              scale: sceneScale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: composite.canvasWidth,
                height: composite.canvasHeight,
                child: _buildCompositeNode(
                  composite.root,
                  asset: composite,
                  decorationId: decoration.id,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompositeDecoration(
    BagItem item, {
    required PlacedDecoration decoration,
  }) {
    final composite = item.composite;

    if (composite == null ||
        composite.canvasWidth <= 0 ||
        composite.canvasHeight <= 0) {
      return const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white38),
      );
    }

    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.center,
      child: SizedBox(
        width: composite.canvasWidth,
        height: composite.canvasHeight,
        child: _buildCompositeNode(
          composite.root,
          asset: composite,
          decorationId: decoration.id,
        ),
      ),
    );
  }

  Future<void> _chooseDecoration() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _bagService.loadItems();

    await _primeImageAlphaMasks(items);

    if (!mounted) return;

    // --------------------------------------------------------
    // Read the exact same Pocket data used by BagScreen.
    // --------------------------------------------------------

    const customPocketsKey = 'inkdframes_bag_custom_pockets_v1';
    const pocketAssignmentsKey = 'inkdframes_bag_pocket_assignments_v1';

    final builtInPockets = <Map<String, String>>[
      <String, String>{'id': 'built_in_sketches', 'name': 'Sketches'},
      <String, String>{'id': 'built_in_characters', 'name': 'Characters'},
      <String, String>{'id': 'built_in_textures', 'name': 'Textures'},
      <String, String>{'id': 'built_in_props', 'name': 'Props'},
      <String, String>{'id': 'built_in_brushes', 'name': 'Brushes'},
      <String, String>{'id': 'built_in_misc', 'name': 'Misc.'},
    ];

    final customPockets = <Map<String, String>>[];

    final rawCustomPockets = prefs.getString(customPocketsKey);

    if (rawCustomPockets != null && rawCustomPockets.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCustomPockets);

        if (decoded is List) {
          for (final entry in decoded.whereType<Map>()) {
            final id = entry['id']?.toString() ?? '';
            final name = entry['name']?.toString() ?? 'Pocket';

            if (id.isNotEmpty) {
              customPockets.add(<String, String>{'id': id, 'name': name});
            }
          }
        }
      } catch (_) {}
    }

    final assignments = <String, String>{};

    final rawAssignments = prefs.getString(pocketAssignmentsKey);

    if (rawAssignments != null && rawAssignments.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAssignments);

        if (decoded is Map) {
          for (final entry in decoded.entries) {
            assignments[entry.key.toString()] = entry.value.toString();
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;

    String? activePocketId;
    String? activePocketName;

    final selectedItem = await showModalBottomSheet<BagItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF21160F),
      barrierColor: Colors.black54,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            List<BagItem> activeItems() {
              if (activePocketId == '__unsorted__') {
                return items
                    .where((item) => !assignments.containsKey(item.id))
                    .toList();
              }

              return items
                  .where((item) => assignments[item.id] == activePocketId)
                  .toList();
            }

            Widget pocketTile({
              required String id,
              required String name,
              required IconData icon,
              required int count,
            }) {
              return ListTile(
                leading: Icon(icon, color: const Color(0xFFF1D3A2)),
                title: Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFFF4E5CF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: Text(
                  '$count',
                  style: const TextStyle(color: Colors.white54),
                ),
                onTap: () {
                  setSheetState(() {
                    activePocketId = id;
                    activePocketName = name;
                  });
                },
              );
            }

            final pocketItems = activeItems();

            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.62,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          if (activePocketId != null)
                            IconButton(
                              tooltip: 'Back to Pockets',
                              onPressed: () {
                                setSheetState(() {
                                  activePocketId = null;
                                  activePocketName = null;
                                });
                              },
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Color(0xFFF1D3A2),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              activePocketId == null
                                  ? 'YOUR POCKETS'
                                  : activePocketName!.toUpperCase(),
                              textAlign: activePocketId == null
                                  ? TextAlign.center
                                  : TextAlign.left,
                              style: const TextStyle(
                                color: Color(0xFFF1D3A2),
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ),
                          if (activePocketId != null) const SizedBox(width: 48),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(color: Colors.white12),

                      Expanded(
                        child: activePocketId == null
                            ? ListView(
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(8, 8, 8, 6),
                                    child: Text(
                                      'POCKETS',
                                      style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),

                                  for (final pocket in builtInPockets)
                                    pocketTile(
                                      id: pocket['id']!,
                                      name: pocket['name']!,
                                      icon: Icons.inventory_2_outlined,
                                      count: assignments.values
                                          .where((id) => id == pocket['id'])
                                          .length,
                                    ),

                                  if (customPockets.isNotEmpty) ...[
                                    const Padding(
                                      padding: EdgeInsets.fromLTRB(8, 18, 8, 6),
                                      child: Text(
                                        'MY POCKETS',
                                        style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                    for (final pocket in customPockets)
                                      pocketTile(
                                        id: pocket['id']!,
                                        name: pocket['name']!,
                                        icon: Icons.folder_outlined,
                                        count: assignments.values
                                            .where((id) => id == pocket['id'])
                                            .length,
                                      ),
                                  ],

                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(8, 18, 8, 6),
                                    child: Text(
                                      'UNSORTED',
                                      style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),

                                  pocketTile(
                                    id: '__unsorted__',
                                    name: 'Unsorted',
                                    icon: Icons.inbox_outlined,
                                    count: items
                                        .where(
                                          (item) =>
                                              !assignments.containsKey(item.id),
                                        )
                                        .length,
                                  ),
                                ],
                              )
                            : pocketItems.isEmpty
                            ? const Center(
                                child: Text(
                                  'This Pocket is empty.',
                                  style: TextStyle(
                                    color: Color(0xFFCFB997),
                                    fontSize: 15,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: pocketItems.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(color: Colors.white12),
                                itemBuilder: (context, index) {
                                  final item = pocketItems[index];

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 6,
                                    ),
                                    leading: SizedBox(
                                      width: 58,
                                      height: 58,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.black26,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: Colors.white12,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: item.isImage
                                              ? Image.file(
                                                  File(item.imagePath!),
                                                  fit: BoxFit.contain,
                                                  errorBuilder:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) {
                                                        return const Icon(
                                                          Icons
                                                              .broken_image_outlined,
                                                          color: Colors.white38,
                                                        );
                                                      },
                                                )
                                              : item.isComposite
                                              ? const Center(
                                                  child: Icon(
                                                    Icons.view_in_ar_outlined,
                                                    size: 34,
                                                    color: Color(0xFFF1D3A2),
                                                  ),
                                                )
                                              : CustomPaint(
                                                  painter:
                                                      BagItemPreviewPainter(
                                                        strokes:
                                                            _bagItemStrokes(
                                                              item,
                                                            ),
                                                      ),
                                                ),
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      item.name,
                                      style: const TextStyle(
                                        color: Color(0xFFF4E5CF),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: const Text(
                                      'Tap to place in Home',
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                    trailing: const Icon(
                                      Icons.add_circle_outline,
                                      color: Color(0xFFF1D3A2),
                                    ),
                                    onTap: () {
                                      Navigator.pop(sheetContext, item);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selectedItem == null || !mounted) {
      return;
    }

    setState(() {
      _bagItemsById[selectedItem.id] = selectedItem;

      final decoration = PlacedDecoration(
        id: 'decor_${DateTime.now().microsecondsSinceEpoch}',
        bagItemId: selectedItem.id,
        name: selectedItem.name,
        x: 0.5,
        y: 0.5,
        scale: 1.0,
        rotation: 0.0,
      );

      _decorations.add(decoration);
      _selectedDecorationId = decoration.id;
      _decorateMode = true;
    });

    await _saveDecorations();
  }

  PlacedDecoration? get _selectedDecoration {
    final id = _selectedDecorationId;

    if (id == null) return null;

    for (final decoration in _decorations) {
      if (decoration.id == id) {
        return decoration;
      }
    }

    return null;
  }

  void _replaceDecoration(PlacedDecoration updated) {
    final index = _decorations.indexWhere(
      (decoration) => decoration.id == updated.id,
    );

    if (index == -1) return;

    _decorations[index] = updated;
  }

  Size? _bagItemDrawingSize(BagItem item) {
    if (item.isComposite) {
      final composite = item.composite;

      if (composite == null ||
          composite.canvasWidth <= 0 ||
          composite.canvasHeight <= 0) {
        return null;
      }

      return Size(composite.canvasWidth, composite.canvasHeight);
    }

    final strokes = _bagItemStrokes(
      item,
    ).where((stroke) => stroke.points.isNotEmpty).toList();

    if (strokes.isEmpty) {
      return null;
    }

    final allPoints = strokes.expand((stroke) => stroke.points).toList();

    var minX = allPoints.first.dx;
    var maxX = allPoints.first.dx;
    var minY = allPoints.first.dy;
    var maxY = allPoints.first.dy;

    var maxStrokeWidth = 1.0;

    for (final stroke in strokes) {
      if (stroke.strokeWidth > maxStrokeWidth) {
        maxStrokeWidth = stroke.strokeWidth;
      }

      for (final point in stroke.points) {
        if (point.dx < minX) minX = point.dx;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dy > maxY) maxY = point.dy;
      }
    }

    // Match BagItemPreviewPainter's bounds calculation exactly.
    final padding = (maxStrokeWidth / 2) + 2;

    minX -= padding;
    maxX += padding;
    minY -= padding;
    maxY += padding;

    return Size(
      (maxX - minX).clamp(1.0, double.infinity),
      (maxY - minY).clamp(1.0, double.infinity),
    );
  }

  double? _decorationVisibleScaleAtOne({
    required BagItem item,
    required double roomWidth,
    required double roomHeight,
  }) {
    final drawingSize = _bagItemDrawingSize(item);

    if (drawingSize == null) {
      return null;
    }

    if (item.isComposite) {
      final composite = item.composite;

      if (composite == null ||
          composite.canvasWidth <= 0 ||
          composite.canvasHeight <= 0) {
        return null;
      }

      final scaleX = roomWidth / composite.canvasWidth;
      final scaleY = roomHeight / composite.canvasHeight;

      return scaleX < scaleY ? scaleX : scaleY;
    }

    // These match the decoration box and BagItemPreviewPainter.
    const decorationFraction = 0.18;
    const previewFitFraction = 0.82;

    final boxWidth = roomWidth * decorationFraction;
    final boxHeight = roomHeight * decorationFraction;

    final scaleX = (boxWidth * previewFitFraction) / drawingSize.width;

    final scaleY = (boxHeight * previewFitFraction) / drawingSize.height;

    return scaleX < scaleY ? scaleX : scaleY;
  }

  Future<void> _fitSelectedDecorationWidth({
    required double roomWidth,
    required double roomHeight,
  }) async {
    final selected = _selectedDecoration;

    if (selected == null) return;

    final item = _bagItemsById[selected.bagItemId];

    if (item == null) return;

    final drawingSize = _bagItemDrawingSize(item);

    final previewScale = _decorationVisibleScaleAtOne(
      item: item,
      roomWidth: roomWidth,
      roomHeight: roomHeight,
    );

    if (drawingSize == null || previewScale == null) {
      return;
    }

    final visibleWidthAtScaleOne = drawingSize.width * previewScale;

    if (visibleWidthAtScaleOne <= 0) {
      return;
    }

    final targetScale = (roomWidth / visibleWidthAtScaleOne).clamp(0.15, 20.0);

    setState(() {
      _replaceDecoration(selected.copyWith(scale: targetScale, x: 0.5));
    });

    await _saveDecorations();
  }

  Future<void> _fitSelectedDecorationHeight({
    required double roomWidth,
    required double roomHeight,
  }) async {
    final selected = _selectedDecoration;

    if (selected == null) return;

    final item = _bagItemsById[selected.bagItemId];

    if (item == null) return;

    final drawingSize = _bagItemDrawingSize(item);

    final previewScale = _decorationVisibleScaleAtOne(
      item: item,
      roomWidth: roomWidth,
      roomHeight: roomHeight,
    );

    if (drawingSize == null || previewScale == null) {
      return;
    }

    final visibleHeightAtScaleOne = drawingSize.height * previewScale;

    if (visibleHeightAtScaleOne <= 0) {
      return;
    }

    final targetScale = (roomHeight / visibleHeightAtScaleOne).clamp(
      0.15,
      20.0,
    );

    setState(() {
      _replaceDecoration(selected.copyWith(scale: targetScale, y: 0.5));
    });

    await _saveDecorations();
  }

  Future<void> _fitSelectedDecorationRoom({
    required double roomWidth,
    required double roomHeight,
  }) async {
    final selected = _selectedDecoration;

    if (selected == null) return;

    final item = _bagItemsById[selected.bagItemId];

    if (item == null) return;

    final drawingSize = _bagItemDrawingSize(item);

    final previewScale = _decorationVisibleScaleAtOne(
      item: item,
      roomWidth: roomWidth,
      roomHeight: roomHeight,
    );

    if (drawingSize == null || previewScale == null) {
      return;
    }

    final visibleWidthAtScaleOne = drawingSize.width * previewScale;

    final visibleHeightAtScaleOne = drawingSize.height * previewScale;

    if (visibleWidthAtScaleOne <= 0 || visibleHeightAtScaleOne <= 0) {
      return;
    }

    // Leave a tiny margin for general-purpose room fitting.
    final widthScale = ((roomWidth * 0.96) / visibleWidthAtScaleOne);

    final heightScale = ((roomHeight * 0.96) / visibleHeightAtScaleOne);

    final targetScale = (widthScale < heightScale ? widthScale : heightScale)
        .clamp(0.15, 20.0);

    setState(() {
      _replaceDecoration(selected.copyWith(scale: targetScale, x: 0.5, y: 0.5));
    });

    await _saveDecorations();
  }

  Future<void> _duplicateSelectedDecorationAsInstance() async {
    final selected = _selectedDecoration;

    if (selected == null) {
      return;
    }

    final duplicateId = 'decor_${DateTime.now().microsecondsSinceEpoch}';

    final duplicate = selected.copyWith(
      id: duplicateId,
      name: '${selected.name} Instance',
      x: (selected.x + 0.025).clamp(0.0, 1.0),
      y: (selected.y + 0.025).clamp(0.0, 1.0),
    );

    // Duplicate what the user currently sees.
    //
    // Variant choices and any other Composite instance overrides live in the
    // Home state map under the placed decoration ID rather than in the shared
    // Bag source. Give the duplicate its own map containing the original
    // instance's current state.
    //
    // From this point onward the two instances are independent.
    final sourceOverrides = _roomNodeOverrides[selected.id];

    final duplicateOverrides = sourceOverrides == null
        ? <String, _RoomNodeOverride>{}
        : <String, _RoomNodeOverride>{
            for (final entry in sourceOverrides.entries) entry.key: entry.value,
          };

    setState(() {
      _decorations.add(duplicate);

      if (duplicateOverrides.isNotEmpty) {
        _roomNodeOverrides[duplicateId] = duplicateOverrides;
      }

      _selectedDecorationId = duplicate.id;
      _decorateMode = true;
    });

    await _saveDecorations();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${selected.name} duplicated with its current variants 🔗',
        ),
      ),
    );
  }

  Future<void> _deleteSelectedDecoration() async {
    final selected = _selectedDecoration;

    if (selected == null) return;

    setState(() {
      _decorations.removeWhere((decoration) => decoration.id == selected.id);

      _selectedDecorationId = null;
    });

    await _saveDecorations();
  }

  Future<void> _resetSelectedDecoration() async {
    final selected = _selectedDecoration;

    if (selected == null) return;

    setState(() {
      _replaceDecoration(
        selected.copyWith(scale: 1.0, rotation: 0.0, mirrored: false),
      );
    });

    await _saveDecorations();
  }

  Future<void> _showDecorationPicker() async {
    if (_decorations.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no placed decorations yet.')),
      );
      return;
    }

    final selectedId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF21160F),
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.62,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: _decorations.length,
              separatorBuilder: (_, _) => const Divider(color: Colors.white12),
              itemBuilder: (context, index) {
                final decoration = _decorations[index];
                final selected = decoration.id == _selectedDecorationId;

                return ListTile(
                  leading: Icon(
                    selected
                        ? Icons.check_box_outlined
                        : Icons.crop_square_outlined,
                    color: selected
                        ? Colors.cyanAccent
                        : const Color(0xFFF1D3A2),
                  ),
                  title: Text(
                    decoration.name,
                    style: const TextStyle(
                      color: Color(0xFFF4E5CF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Scale ${(decoration.scale * 100).round()}%',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check, color: Colors.cyanAccent)
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext, decoration.id);
                  },
                );
              },
            ),
          ),
        );
      },
    );

    if (selectedId == null || !mounted) {
      return;
    }

    setState(() {
      _selectedDecorationId = selectedId;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_homeScrollController.hasClients) {
        return;
      }

      final decoration = _selectedDecoration;

      if (decoration == null) {
        return;
      }

      final position = _homeScrollController.position;
      final roomWidth = position.maxScrollExtent + position.viewportDimension;

      final target =
          ((decoration.x * roomWidth) - (position.viewportDimension / 2)).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );

      _homeScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _showComingSoon(BuildContext context, String area) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(area),
          content: const Text(
            'This part of your InkdFrames home is still being built.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createBlankAnimation(BuildContext context) async {
    final screenSize = MediaQuery.sizeOf(context);
    final initialPortrait = screenSize.height > screenSize.width;

    final result = await showDialog<({String name, bool portrait, double fps})>(
      context: context,
      builder: (dialogContext) {
        return _CreateAnimationDialog(
          title: 'Create animation',
          initialName: '',
          initialPortrait: initialPortrait,
        );
      },
    );

    if (result == null || !context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkspaceScreen(
          projectName: result.name,
          initialCanvasWidth: result.portrait ? 1080 : 1920,
          initialCanvasHeight: result.portrait ? 1920 : 1080,
          initialFps: result.fps,
        ),
      ),
    );
  }

  Future<void> _importMemory(BuildContext context) async {
    final mediaType = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Import a Memory'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext, 'image');
              },
              child: const ListTile(
                leading: Icon(Icons.image_outlined),
                title: Text('Import Image'),
                subtitle: Text('JPG, JPEG or PNG'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext, 'video');
              },
              child: const ListTile(
                leading: Icon(Icons.videocam_outlined),
                title: Text('Import Video'),
                subtitle: Text('Video reference'),
              ),
            ),
          ],
        );
      },
    );

    if (mediaType == null || !context.mounted) return;

    String? sourcePath;
    String? sourceName;

    if (Platform.isLinux) {
      final testDirectory = Directory(
        mediaType == 'image'
            ? '/sdcard/InkdFramesTestMedia/images'
            : '/sdcard/InkdFramesTestMedia/videos',
      );

      final files = testDirectory.existsSync()
          ? testDirectory.listSync().whereType<File>().toList()
          : <File>[];

      if (files.isEmpty) {
        if (!context.mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mediaType == 'image'
                  ? 'No test images found in InkdFramesTestMedia/images.'
                  : 'No test videos found in InkdFramesTestMedia/videos.',
            ),
          ),
        );

        return;
      }

      final selectedFile = await showDialog<File>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              mediaType == 'image' ? 'Choose Test Image' : 'Choose Test Video',
            ),
            content: SizedBox(
              width: 420,
              height: 320,
              child: ListView.separated(
                itemCount: files.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final file = files[index];
                  final name = file.uri.pathSegments.last;

                  return ListTile(
                    leading: Icon(
                      mediaType == 'image'
                          ? Icons.image_outlined
                          : Icons.movie_outlined,
                    ),
                    title: Text(name),
                    onTap: () {
                      Navigator.pop(dialogContext, file);
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );

      if (selectedFile == null || !context.mounted) {
        return;
      }

      sourcePath = selectedFile.path;
      sourceName = selectedFile.uri.pathSegments.last;
    } else {
      final pickedFile = await FilePicker.pickFile(
        type: mediaType == 'image' ? FileType.image : FileType.video,
      );

      if (pickedFile == null || !context.mounted) {
        return;
      }

      if (pickedFile.path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access that file.')),
        );
        return;
      }

      sourcePath = pickedFile.path!;
      sourceName = pickedFile.name;
    }

    final screenSize = MediaQuery.sizeOf(context);
    final initialPortrait = screenSize.height > screenSize.width;

    final result = await showDialog<({String name, bool portrait, double fps})>(
      context: context,
      builder: (dialogContext) {
        return _CreateAnimationDialog(
          title: mediaType == 'image'
              ? 'Create from image'
              : 'Create from video',
          initialName: sourceName!.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          initialPortrait: initialPortrait,
          showFps: mediaType == 'video',
          initialFps: mediaType == 'video' ? 12 : 8,
        );
      },
    );

    if (result == null || !context.mounted) return;

    final referenceDirectory = Platform.isLinux
        ? Directory('/tmp/inkdframes_reference_media')
        : Directory('/data/user/0/com.inkdframes.app/files/reference_media');

    if (!await referenceDirectory.exists()) {
      await referenceDirectory.create(recursive: true);
    }

    final extension = sourceName.contains('.')
        ? '.${sourceName.split('.').last}'
        : '';

    final storedPath =
        '${referenceDirectory.path}/'
        '${DateTime.now().microsecondsSinceEpoch}$extension';

    await File(sourcePath).copy(storedPath);

    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkspaceScreen(
          projectName: result.name,
          initialCanvasWidth: result.portrait ? 1080 : 1920,
          initialCanvasHeight: result.portrait ? 1920 : 1080,
          initialReferenceMediaPath: storedPath,
          initialReferenceMediaType: mediaType,
          initialFps: result.fps,
        ),
      ),
    );
  }

  Widget _roomHotspot({required String tooltip, required VoidCallback onTap}) {
    return IgnorePointer(
      ignoring: _decorateMode,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              splashColor: Colors.white12,
              highlightColor: Colors.white10,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isPortrait = constraints.maxHeight > constraints.maxWidth;

          final roomHeight = constraints.maxHeight;

          // Portrait keeps the room at a readable landscape scale.
          // The phone becomes a horizontal viewport into the room.
          final roomWidth = isPortrait
              ? roomHeight * (3 / 2)
              : constraints.maxWidth;

          Widget buildRoom() {
            return SizedBox(
              width: roomWidth,
              height: roomHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/inkdframes_home_room_v1.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),

                  for (final decoration in _decorations)
                    if (_bagItemsById[decoration.bagItemId] != null)
                      Builder(
                        builder: (context) {
                          final bagItem = _bagItemsById[decoration.bagItemId]!;

                          double decorationWidth;
                          double decorationHeight;
                          double decorationLeft;
                          double decorationTop;

                          Rect? compositeVisibleBounds;
                          double? compositeSceneScale;

                          if (bagItem.isComposite &&
                              bagItem.composite != null) {
                            final composite = bagItem.composite!;

                            final roomScaleX =
                                roomWidth / composite.canvasWidth;

                            final roomScaleY =
                                roomHeight / composite.canvasHeight;

                            compositeSceneScale = roomScaleX < roomScaleY
                                ? roomScaleX
                                : roomScaleY;

                            final calculatedBounds =
                                _compositeNodePreviewBounds(
                                  composite.root,
                                  composite,
                                  decorationId: decoration.id,
                                );

                            final usableBounds =
                                calculatedBounds != null &&
                                    calculatedBounds.width > 0 &&
                                    calculatedBounds.height > 0
                                ? calculatedBounds
                                : Rect.fromLTWH(
                                    0,
                                    0,
                                    composite.canvasWidth,
                                    composite.canvasHeight,
                                  );

                            compositeVisibleBounds = usableBounds;

                            decorationWidth =
                                usableBounds.width * compositeSceneScale;

                            decorationHeight =
                                usableBounds.height * compositeSceneScale;

                            // Preserve the old authored-canvas centre as the
                            // instance anchor. Tightening the hit box therefore
                            // does not teleport the visible artwork.
                            decorationLeft =
                                (decoration.x * roomWidth) +
                                ((usableBounds.left -
                                        (composite.canvasWidth / 2)) *
                                    compositeSceneScale);

                            decorationTop =
                                (decoration.y * roomHeight) +
                                ((usableBounds.top -
                                        (composite.canvasHeight / 2)) *
                                    compositeSceneScale);
                          } else if (bagItem.hasAuthoredSize) {
                            // Map the authored coordinate space into this
                            // room with one uniform scene scale so the asset
                            // keeps the proportions established in Workspace.
                            final roomScaleX =
                                roomWidth / bagItem.authoredCanvasWidth!;

                            final roomScaleY =
                                roomHeight / bagItem.authoredCanvasHeight!;

                            final authoredSceneScale = roomScaleX < roomScaleY
                                ? roomScaleX
                                : roomScaleY;

                            decorationWidth =
                                bagItem.authoredWidth! * authoredSceneScale;

                            decorationHeight =
                                bagItem.authoredHeight! * authoredSceneScale;

                            decorationLeft =
                                (decoration.x * roomWidth) -
                                (decorationWidth / 2);

                            decorationTop =
                                (decoration.y * roomHeight) -
                                (decorationHeight / 2);
                          } else {
                            // Backward compatibility for Bag assets created
                            // before authored-size metadata existed.
                            decorationWidth =
                                roomWidth * 0.18 * decoration.scale;

                            decorationHeight =
                                roomHeight * 0.18 * decoration.scale;

                            decorationLeft =
                                (decoration.x * roomWidth) -
                                (decorationWidth / 2);

                            decorationTop =
                                (decoration.y * roomHeight) -
                                (decorationHeight / 2);
                          }

                          final selected =
                              _decorateMode &&
                              _selectedDecorationId == decoration.id;

                          return Positioned(
                            left: decorationLeft,
                            top: decorationTop,
                            width: decorationWidth,
                            height: decorationHeight,
                            child: _AlphaHitTest(
                              mask: _bagItemsById[decoration.bagItemId]!.isImage
                                  ? _imageAlphaMasks[_bagItemsById[decoration
                                            .bagItemId]!
                                        .imagePath!]
                                  : null,
                              mirrored: decoration.mirrored,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapUp: !_decorateMode
                                    ? null
                                    : (details) {
                                        // Rooms Awaken #12:
                                        // Composites are sealed in Room Manager.
                                        // A tap selects the complete placed
                                        // asset rather than an authored child.
                                        setState(() {
                                          _selectedDecorationId = decoration.id;
                                        });
                                      },
                                onPanStart: !_decorateMode
                                    ? null
                                    : (details) {
                                        // Rooms Awaken #12:
                                        // Dragging begins on the whole asset.
                                        setState(() {
                                          _selectedDecorationId = decoration.id;
                                        });
                                      },
                                onPanUpdate: !_decorateMode
                                    ? null
                                    : (details) {
                                        if (_decorateTouchPointers.length > 1) {
                                          return;
                                        }

                                        // Rooms Awaken #12:
                                        // Never transform children of an
                                        // authored Composite in Room Manager.
                                        // Continue into normal whole-decoration
                                        // movement below.
                                        final currentIndex = _decorations
                                            .indexWhere(
                                              (candidate) =>
                                                  candidate.id == decoration.id,
                                            );

                                        if (currentIndex == -1) {
                                          return;
                                        }

                                        final current =
                                            _decorations[currentIndex];

                                        setState(() {
                                          _replaceDecoration(
                                            current.copyWith(
                                              x:
                                                  (current.x +
                                                          (details.delta.dx /
                                                              roomWidth))
                                                      .clamp(0.0, 1.0),
                                              y:
                                                  (current.y +
                                                          (details.delta.dy /
                                                              roomHeight))
                                                      .clamp(0.0, 1.0),
                                            ),
                                          );
                                        });
                                      },
                                onPanEnd: !_decorateMode
                                    ? null
                                    : (_) {
                                        if (_isEditingRoomContents &&
                                            decoration.id ==
                                                _editingRoomDecorationId &&
                                            bagItem.isComposite) {
                                          _saveDecorations();
                                          return;
                                        }

                                        _saveDecorations();
                                      },
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: selected
                                        ? Border.all(
                                            color:
                                                _isEditingRoomContents &&
                                                    decoration.id ==
                                                        _editingRoomDecorationId
                                                ? Colors.amberAccent
                                                : Colors.cyanAccent,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: Padding(
                                    padding: selected
                                        ? const EdgeInsets.all(2)
                                        : EdgeInsets.zero,
                                    child: Transform(
                                      alignment: Alignment.center,
                                      transform: Matrix4.diagonal3Values(
                                        decoration.mirrored ? -1.0 : 1.0,
                                        1.0,
                                        1.0,
                                      ),
                                      child: Builder(
                                        builder: (context) {
                                          if (bagItem.isImage) {
                                            return Image.file(
                                              File(bagItem.imagePath!),
                                              fit: BoxFit.contain,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                    return const Center(
                                                      child: Icon(
                                                        Icons
                                                            .broken_image_outlined,
                                                        color: Colors.white38,
                                                      ),
                                                    );
                                                  },
                                            );
                                          }

                                          if (bagItem.isComposite &&
                                              compositeVisibleBounds != null &&
                                              compositeSceneScale != null) {
                                            return _buildCroppedCompositeDecoration(
                                              bagItem,
                                              decoration: decoration,
                                              visibleBounds:
                                                  compositeVisibleBounds,
                                              sceneScale: compositeSceneScale,
                                            );
                                          }

                                          return CustomPaint(
                                            painter: BagItemPreviewPainter(
                                              strokes: _bagItemStrokes(bagItem),
                                            ),
                                            child: const SizedBox.expand(),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                  // DEVELOPMENT: RETURN TO HOME EXTERIOR
                  Positioned(
                    right: roomWidth * 0.025,
                    top: roomHeight * 0.035,
                    child: Tooltip(
                      message: 'Go outside',
                      child: Material(
                        color: const Color(0xCC1A1720),
                        shape: const CircleBorder(),
                        elevation: 6,
                        child: IconButton(
                          tooltip: 'Go outside',
                          icon: const Icon(
                            Icons.door_front_door_outlined,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute<void>(
                                builder: (_) => const WelcomeHomeScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  // PROJECT WALL
                  Positioned(
                    left: roomWidth * 0.39,
                    top: roomHeight * 0.18,
                    width: roomWidth * 0.31,
                    height: roomHeight * 0.39,
                    child: _roomHotspot(
                      tooltip: 'Project Wall',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ProjectLibraryScreen(),
                          ),
                        );
                      },
                    ),
                  ),

                  // CREATION DESK
                  Positioned(
                    left: roomWidth * 0.31,
                    top: roomHeight * 0.63,
                    width: roomWidth * 0.37,
                    height: roomHeight * 0.28,
                    child: _roomHotspot(
                      tooltip: 'Creation Desk',
                      onTap: () async {
                        final action = await showModalBottomSheet<String>(
                          context: context,
                          showDragHandle: true,
                          builder: (sheetContext) {
                            return SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  8,
                                  20,
                                  24,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const ListTile(
                                      leading: Icon(Icons.edit_outlined),
                                      title: Text('Creation Desk'),
                                      subtitle: Text('Start something new.'),
                                    ),
                                    const SizedBox(height: 4),
                                    ListTile(
                                      leading: const Icon(
                                        Icons.add_box_outlined,
                                      ),
                                      title: const Text('Blank Animation'),
                                      onTap: () {
                                        Navigator.pop(sheetContext, 'blank');
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(
                                        Icons.photo_library_outlined,
                                      ),
                                      title: const Text('Import a Memory'),
                                      onTap: () {
                                        Navigator.pop(sheetContext, 'import');
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );

                        if (!context.mounted) return;

                        if (action == 'blank') {
                          await _createBlankAnimation(context);
                        } else if (action == 'import') {
                          await _importMemory(context);
                        }
                      },
                    ),
                  ),

                  // BAG
                  Positioned(
                    left: roomWidth * 0.775,
                    top: roomHeight * 0.63,
                    width: roomWidth * 0.18,
                    height: roomHeight * 0.25,
                    child: _roomHotspot(
                      tooltip: 'The Bag',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const BagScreen(),
                          ),
                        );
                      },
                    ),
                  ),

                  // KITCHEN
                  Positioned(
                    left: roomWidth * 0.23,
                    top: roomHeight * 0.12,
                    width: roomWidth * 0.16,
                    height: roomHeight * 0.48,
                    child: _roomHotspot(
                      tooltip: 'Kitchen · Coming Soon',
                      onTap: () {
                        _showComingSoon(context, 'Kitchen');
                      },
                    ),
                  ),

                  // GARDEN
                  Positioned(
                    left: roomWidth * 0.70,
                    top: roomHeight * 0.16,
                    width: roomWidth * 0.17,
                    height: roomHeight * 0.47,
                    child: _roomHotspot(
                      tooltip: 'Garden · Coming Soon',
                      onTap: () {
                        _showComingSoon(context, 'Garden');
                      },
                    ),
                  ),

                  // SETTINGS
                  Positioned(
                    left: roomWidth * 0.795,
                    top: roomHeight * 0.855,
                    width: roomWidth * 0.19,
                    height: roomHeight * 0.12,
                    child: _roomHotspot(
                      tooltip: 'Options',
                      onTap: () {
                        _showComingSoon(context, 'Options');
                      },
                    ),
                  ),

                  // WINDOW
                  Positioned(
                    left: roomWidth * 0.015,
                    top: roomHeight * 0.18,
                    width: roomWidth * 0.20,
                    height: roomHeight * 0.42,
                    child: _roomHotspot(
                      tooltip: 'Window',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('A quiet view outside. 🌿'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          }

          final roomViewport = Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handleDecoratePointerDown,
            onPointerMove: _handleDecoratePointerMove,
            onPointerUp: _handleDecoratePointerUp,
            onPointerCancel: _handleDecoratePointerUp,
            child: isPortrait
                ? SingleChildScrollView(
                    controller: _homeScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: _decorateMode
                        ? const NeverScrollableScrollPhysics()
                        : const BouncingScrollPhysics(),
                    child: buildRoom(),
                  )
                : buildRoom(),
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              roomViewport,

              // Screen-space Decorate controls.
              // These stay fixed to the device while the room moves beneath them.
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth - 32,
                      ),
                      child: Material(
                        color: const Color(0xDD1A1720),
                        borderRadius: BorderRadius.circular(18),
                        elevation: 8,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Wrap(
                            spacing: 0,
                            runSpacing: 0,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              IconButton(
                                tooltip: _decorateMode
                                    ? 'Finish Decorating'
                                    : 'Decorate',
                                onPressed: () {
                                  setState(() {
                                    _decorateMode = !_decorateMode;

                                    if (!_decorateMode) {
                                      _selectedDecorationId = null;
                                      _editingRoomDecorationId = null;
                                    }
                                  });
                                },
                                icon: Icon(
                                  Icons.auto_awesome_mosaic_outlined,
                                  color: _decorateMode
                                      ? Colors.cyanAccent
                                      : Colors.white,
                                ),
                              ),
                              if (_decorateMode)
                                IconButton(
                                  tooltip: 'Choose from Bag',
                                  onPressed: _chooseDecoration,
                                  icon: const Icon(
                                    Icons.backpack_outlined,
                                    color: Colors.white,
                                  ),
                                ),
                              if (_decorateMode)
                                IconButton(
                                  tooltip: 'Placed Objects',
                                  onPressed: _showDecorationPicker,
                                  icon: const Icon(
                                    Icons.layers_outlined,
                                    color: Colors.white,
                                  ),
                                ),
                              if (_decorateMode &&
                                  !_isEditingRoomContents &&
                                  _selectedDecorationIsComposite)
                                IconButton(
                                  tooltip: 'Edit Contents',
                                  onPressed: _enterRoomContents,
                                  icon: const Icon(
                                    Icons.meeting_room_outlined,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              if (_decorateMode && _isEditingRoomContents)
                                IconButton(
                                  tooltip: _canGoBackRoomScope
                                      ? 'Back to Parent'
                                      : 'Exit Room',
                                  onPressed: _backRoomScope,
                                  icon: Icon(
                                    _canGoBackRoomScope
                                        ? Icons.arrow_back
                                        : Icons.exit_to_app,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              if (_decorateMode && _isEditingRoomContents)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: Chip(
                                    avatar: const Icon(
                                      Icons.account_tree_outlined,
                                      size: 18,
                                      color: Colors.cyanAccent,
                                    ),
                                    label: Text(
                                      _currentRoomScopeName,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    backgroundColor: Colors.black54,
                                    side: const BorderSide(
                                      color: Colors.cyanAccent,
                                    ),
                                    labelStyle: const TextStyle(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              if (_legacyRoomNodeEditingEnabled &&
                                  _isEditingRoomContents &&
                                  _selectedRoomNodeId != null &&
                                  _selectedRoomNodeName != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Chip(
                                    avatar: const Icon(
                                      Icons.chair_outlined,
                                      size: 18,
                                      color: Colors.amberAccent,
                                    ),
                                    label: Text(
                                      _selectedRoomNodeName!,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    backgroundColor: Colors.black54,
                                    side: const BorderSide(
                                      color: Colors.amberAccent,
                                    ),
                                    labelStyle: const TextStyle(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              if (_legacyRoomNodeEditingEnabled &&
                                  _isEditingRoomContents &&
                                  _currentRoomScopeChildren.isNotEmpty) ...[
                                IconButton(
                                  tooltip: 'Previous Item',
                                  onPressed: () => _cycleRoomScopeSelection(-1),
                                  icon: const Icon(
                                    Icons.skip_previous,
                                    color: Colors.cyanAccent,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Next Item',
                                  onPressed: () => _cycleRoomScopeSelection(1),
                                  icon: const Icon(
                                    Icons.skip_next,
                                    color: Colors.cyanAccent,
                                  ),
                                ),
                              ],
                              if (_legacyRoomNodeEditingEnabled &&
                                  _isEditingRoomContents &&
                                  _canEnterSelectedRoomNode)
                                IconButton(
                                  tooltip: 'Enter Group',
                                  onPressed: _enterSelectedRoomNode,
                                  icon: const Icon(
                                    Icons.login,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              if (_isEditingRoomContents)
                                for (final variantNode
                                    in _selectedRoomVariantNodes)
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 240,
                                    ),
                                    child: ActionChip(
                                      avatar: const Icon(
                                        Icons.auto_awesome_mosaic_outlined,
                                        size: 18,
                                        color: Colors.amberAccent,
                                      ),
                                      label: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              _roomVariantLabel(variantNode),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.expand_more,
                                            size: 18,
                                            color: Colors.amberAccent,
                                          ),
                                        ],
                                      ),
                                      tooltip:
                                          'Choose ${_roomVariantSlotName(variantNode)}',
                                      onPressed: () =>
                                          _showRoomVariantPicker(variantNode),
                                      backgroundColor: Colors.black54,
                                      side: const BorderSide(
                                        color: Colors.amberAccent,
                                      ),
                                      labelStyle: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              if (_legacyRoomNodeEditingEnabled &&
                                  _isEditingRoomContents &&
                                  _selectedRoomNodeId != null) ...[
                                IconButton(
                                  tooltip: 'Move Left',
                                  onPressed: () =>
                                      _nudgeSelectedRoomNode(-24, 0),
                                  icon: const Icon(
                                    Icons.arrow_left,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Move Right',
                                  onPressed: () =>
                                      _nudgeSelectedRoomNode(24, 0),
                                  icon: const Icon(
                                    Icons.arrow_right,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Move Up',
                                  onPressed: () =>
                                      _nudgeSelectedRoomNode(0, -24),
                                  icon: const Icon(
                                    Icons.arrow_drop_up,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Move Down',
                                  onPressed: () =>
                                      _nudgeSelectedRoomNode(0, 24),
                                  icon: const Icon(
                                    Icons.arrow_drop_down,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Scale Down',
                                  onPressed: () => _scaleSelectedRoomNode(0.9),
                                  icon: const Icon(
                                    Icons.zoom_out,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Scale Up',
                                  onPressed: () => _scaleSelectedRoomNode(1.1),
                                  icon: const Icon(
                                    Icons.zoom_in,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Mirror',
                                  onPressed: _mirrorSelectedRoomNode,
                                  icon: const Icon(
                                    Icons.flip,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Reset Item',
                                  onPressed: _resetSelectedRoomNodeOverride,
                                  icon: const Icon(
                                    Icons.restart_alt,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              ],
                              if (_decorateMode &&
                                  !_isEditingRoomContents &&
                                  _selectedDecoration != null) ...[
                                IconButton(
                                  tooltip: 'Reset Transform',
                                  onPressed: _resetSelectedDecoration,
                                  icon: const Icon(
                                    Icons.restart_alt,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Duplicate Instance',
                                  onPressed:
                                      _duplicateSelectedDecorationAsInstance,
                                  icon: const Icon(
                                    Icons.copy_outlined,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                              if (_decorateMode &&
                                  !_isEditingRoomContents &&
                                  _selectedDecoration != null)
                                IconButton(
                                  tooltip: 'Delete decoration',
                                  onPressed: _deleteSelectedDecoration,
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.white70,
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
            ],
          );
        },
      ),
    );
  }
}

class _CreateAnimationDialog extends StatefulWidget {
  const _CreateAnimationDialog({
    required this.title,
    required this.initialName,
    required this.initialPortrait,
    this.showFps = false,
    this.initialFps = 8,
  });

  final String title;
  final String initialName;
  final bool initialPortrait;
  final bool showFps;
  final double initialFps;

  @override
  State<_CreateAnimationDialog> createState() => _CreateAnimationDialogState();
}

class _CreateAnimationDialogState extends State<_CreateAnimationDialog> {
  late final TextEditingController _controller;
  late bool _isPortrait;
  late double _fps;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _isPortrait = widget.initialPortrait;
    _fps = widget.initialFps;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.55,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Animation name',
                    hintText: 'e.g. Bouncing Ball',
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Canvas orientation',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.crop_landscape),
                      label: Text('Landscape'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.crop_portrait),
                      label: Text('Portrait'),
                    ),
                  ],
                  selected: {_isPortrait},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _isPortrait = selection.first;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  _isPortrait ? '1080 × 1920' : '1920 × 1080',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (widget.showFps) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Rotoscope FPS',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text('${_fps.round()} FPS'),
                    ],
                  ),
                  Slider(
                    value: _fps,
                    min: 6,
                    max: 24,
                    divisions: 18,
                    label: '${_fps.round()} FPS',
                    onChanged: (value) {
                      setState(() {
                        _fps = value;
                      });
                    },
                  ),
                  Text(
                    _fps == 12
                        ? '12 FPS · Classic smooth rotoscoping'
                        : '${_fps.round()} drawing frames per second',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _controller.text.trim();

            if (name.isEmpty) return;

            Navigator.pop(context, (
              name: name,
              portrait: _isPortrait,
              fps: _fps,
            ));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
