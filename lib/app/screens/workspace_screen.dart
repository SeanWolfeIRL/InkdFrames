import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/inkdframes_project.dart';
import '../models/vector_point.dart';
import '../models/vector_stroke.dart';
import '../painters/animation_canvas_painter.dart';
import '../painters/frame_thumbnail_painter.dart';
import '../services/animation_export_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, this.projectId, this.projectName});

  final String? projectId;
  final String? projectName;

  static const routeName = '/workspace';

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final List<List<VectorStroke>> _frames = [<VectorStroke>[]];
  final List<int> _frameDurations = [1];
  int _selectedFrameIndex = 0;
  int _activePointerCount = 0;
  List<VectorPoint> _draftStroke = const <VectorPoint>[];
  Timer? _playbackTimer;
  Timer? _autosaveTimer;
  bool _isPlaying = false;
  bool _showOnionSkin = true;
  bool _isEraserActive = false;
  bool _timingExpanded = true;
  bool _drawingExpanded = true;
  bool _timelineExpanded = true;
  bool? _frameToolbarExpanded;
  bool? _editToolbarExpanded;
  bool _isExporting = false;
  double _fps = 8;
  double _brushSize = 4.0;
  double _canvasWidth = 1920;
  double _canvasHeight = 1080;
  Color _brushColor = Colors.white;
  final List<List<List<VectorStroke>>> _undoStacks = [[]];
  final List<List<List<VectorStroke>>> _redoStacks = [[]];

  final TransformationController _transformationController =
      TransformationController();

  String _projectId = '';
  String _projectName = 'Untitled Animation';

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _autosaveTimer?.cancel();
    _transformationController.dispose();
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
    }
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();

    _autosaveTimer = Timer(const Duration(seconds: 2), _saveProject);
  }

  Future<void> _saveProject() async {
    final project = InkdFramesProject(
      id: _projectId,
      name: _projectName,
      fps: _fps,
      frames: _frames,
      frameDurations: _frameDurations,
      canvasWidth: _canvasWidth,
      canvasHeight: _canvasHeight,
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

  Future<void> _loadProject() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('project_$_projectId');

    if (jsonString == null) {
      return;
    }

    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    final project = InkdFramesProject.fromJson(json);
    _projectId = project.id;
    _projectName = project.name;

    setState(() {
      _frames
        ..clear()
        ..addAll(
          project.frames
              .map((frame) => frame.map((stroke) => stroke.copy()).toList())
              .toList(),
        );

      _frameDurations
        ..clear()
        ..addAll(project.frameDurations);
      _undoStacks
        ..clear()
        ..addAll(
          List.generate(project.frames.length, (_) => <List<VectorStroke>>[]),
        );

      _redoStacks
        ..clear()
        ..addAll(
          List.generate(project.frames.length, (_) => <List<VectorStroke>>[]),
        );

      _fps = project.fps;
      _canvasWidth = project.canvasWidth;
      _canvasHeight = project.canvasHeight;
      _selectedFrameIndex = 0;
      _draftStroke = const <VectorPoint>[];
    });
  }

  void _resetCanvasView() {
    _transformationController.value = Matrix4.identity();
  }

  void _addFrame() {
    setState(() {
      _frames.add(<VectorStroke>[]);
      _frameDurations.add(1);
      _undoStacks.add([]);
      _redoStacks.add([]);

      _selectedFrameIndex = _frames.length - 1;
      _draftStroke = const <VectorPoint>[];
    });
    _scheduleAutosave();
  }

  void _duplicateFrame() {
    setState(() {
      final copiedFrame = _frames[_selectedFrameIndex]
          .map((stroke) => stroke.copy())
          .toList();

      _frames.add(copiedFrame);
      _frameDurations.add(_frameDurations[_selectedFrameIndex]);
      _undoStacks.add([]);
      _redoStacks.add([]);

      _selectedFrameIndex = _frames.length - 1;
      _draftStroke = const <VectorPoint>[];
    });
    _scheduleAutosave();
  }

  void _deleteFrame() {
    if (_frames.length <= 1) return;

    setState(() {
      _frames.removeAt(_selectedFrameIndex);
      _frameDurations.removeAt(_selectedFrameIndex);
      _undoStacks.removeAt(_selectedFrameIndex);
      _redoStacks.removeAt(_selectedFrameIndex);

      if (_selectedFrameIndex >= _frames.length) {
        _selectedFrameIndex = _frames.length - 1;
      }

      _draftStroke = const <VectorPoint>[];
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
      final frame = _frames.removeAt(oldIndex);
      final undoStack = _undoStacks.removeAt(oldIndex);
      final redoStack = _redoStacks.removeAt(oldIndex);
      final frameDuration = _frameDurations.removeAt(oldIndex);

      _frames.insert(newIndex, frame);
      _undoStacks.insert(newIndex, undoStack);
      _redoStacks.insert(newIndex, redoStack);
      _frameDurations.insert(newIndex, frameDuration);

      if (_selectedFrameIndex == oldIndex) {
        _selectedFrameIndex = newIndex;
      } else if (oldIndex < _selectedFrameIndex &&
          _selectedFrameIndex <= newIndex) {
        _selectedFrameIndex -= 1;
      } else if (newIndex <= _selectedFrameIndex &&
          _selectedFrameIndex < oldIndex) {
        _selectedFrameIndex += 1;
      }
    });

    _scheduleAutosave();
  }

  void _selectFrame(int index) {
    if (index < 0 || index >= _frames.length) {
      return;
    }
    setState(() {
      _selectedFrameIndex = index;
      _draftStroke = const <VectorPoint>[];
    });
  }

  void _clearCurrentFrame() {
    setState(() {
      _frames[_selectedFrameIndex] = <VectorStroke>[];
      _draftStroke = const <VectorPoint>[];
    });
    _scheduleAutosave();
  }

  void _saveUndoState() {
    final snapshot = _frames[_selectedFrameIndex]
        .map((stroke) => stroke.copy())
        .toList();

    _undoStacks[_selectedFrameIndex].add(snapshot);
    _redoStacks[_selectedFrameIndex].clear();
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

      _startPlaybackTimer();
    });
  }

  void _togglePlayback() {
    if (_frames.length < 2) {
      return;
    }

    if (_isPlaying) {
      _playbackTimer?.cancel();
      setState(() => _isPlaying = false);
      return;
    }

    setState(() {
      _isPlaying = true;
      _draftStroke = const <VectorPoint>[];
    });

    _startPlaybackTimer();
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

    for (final stroke in _frames[_selectedFrameIndex]) {
      if (stroke.points.isEmpty) {
        continue;
      }

      final eraserRadius = (10 + (stroke.strokeWidth / 2)) / currentScale;
      final eraserRadiusSquared = eraserRadius * eraserRadius;

      var currentChunk = <VectorPoint>[];

      void saveCurrentChunk() {
        if (currentChunk.isEmpty) {
          return;
        }

        updatedStrokes.add(
          VectorStroke(
            points: currentChunk,
            strokeWidth: stroke.strokeWidth,
            color: stroke.color,
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

    _frames[_selectedFrameIndex] = updatedStrokes;
  }

  void _handlePointerDown(PointerDownEvent event, BuildContext canvasContext) {
    _activePointerCount += 1;
    if (_activePointerCount > 1) {
      setState(() {
        _draftStroke = const <VectorPoint>[];
      });
      return;
    }
    if (_isPlaying) {
      return;
    }

    final renderBox = canvasContext.findRenderObject() as RenderBox;
    final canvasPosition = renderBox.globalToLocal(event.position);

    if (_isEraserActive) {
      _saveUndoState();
      setState(() {
        _eraseAt(canvasPosition);
      });
      return;
    }

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

    if (_isEraserActive) {
      setState(() {
        _eraseAt(canvasPosition);
      });
      return;
    }

    if (_draftStroke.isEmpty) {
      return;
    }

    final lastPoint = _draftStroke.last;
    final dx = canvasPosition.dx - lastPoint.dx;
    final dy = canvasPosition.dy - lastPoint.dy;
    final distanceSquared = (dx * dx) + (dy * dy);

    const minimumDistanceSquared = 2.25;

    if (distanceSquared < minimumDistanceSquared) {
      return;
    }

    setState(() {
      _draftStroke.add(
        VectorPoint(
          dx: canvasPosition.dx,
          dy: canvasPosition.dy,
          pressure: event.pressure,
        ),
      );
    });
  }

  void _undo() {
    final undoStack = _undoStacks[_selectedFrameIndex];
    final redoStack = _redoStacks[_selectedFrameIndex];

    if (undoStack.isEmpty) return;

    setState(() {
      final currentSnapshot = _frames[_selectedFrameIndex]
          .map((stroke) => stroke.copy())
          .toList();

      redoStack.add(currentSnapshot);

      _frames[_selectedFrameIndex] = undoStack.removeLast();
    });
    _scheduleAutosave();
  }

  void _redo() {
    final undoStack = _undoStacks[_selectedFrameIndex];
    final redoStack = _redoStacks[_selectedFrameIndex];

    if (redoStack.isEmpty) return;

    setState(() {
      final currentSnapshot = _frames[_selectedFrameIndex]
          .map((stroke) => stroke.copy())
          .toList();

      undoStack.add(currentSnapshot);

      _frames[_selectedFrameIndex] = redoStack.removeLast();
    });
    _scheduleAutosave();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_activePointerCount > 0) {
      _activePointerCount -= 1;
    }
    if (_isPlaying || _draftStroke.isEmpty) {
      return;
    }

    _saveUndoState();

    final stroke = VectorStroke(
      points: List<VectorPoint>.from(_draftStroke),
      strokeWidth: _brushSize,
      color: _brushColor,
    );
    setState(() {
      _frames[_selectedFrameIndex] = <VectorStroke>[
        ..._frames[_selectedFrameIndex],
        stroke,
      ];
      _draftStroke = const <VectorPoint>[];
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
    });
  }

  Future<void> _exportAnimation() async {
    if (_isExporting) {
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final outputPath = await const AnimationExportService().exportMp4(
        projectName: _projectName,
        frames: _frames,
        frameDurations: _frameDurations,
        fps: _fps,
        canvasWidth: _canvasWidth,
        canvasHeight: _canvasHeight,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Animation exported to $outputPath'),
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

  @override
  Widget build(BuildContext context) {
    final previousFrameStrokes = _getPreviousFrameStrokes();
    final nextFrameStrokes = _getNextFrameStrokes();

    return Scaffold(
      appBar: AppBar(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [const SizedBox(width: 8)],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrowToolbarLayout = constraints.maxWidth < 700;
                final isPortraitWorkspace =
                    constraints.maxHeight > constraints.maxWidth;

                final frameToolbarExpanded =
                    _frameToolbarExpanded ?? !isNarrowToolbarLayout;

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
                                    child: CustomPaint(
                                      painter: AnimationCanvasPainter(
                                        strokes: _frames[_selectedFrameIndex],
                                        currentStroke: _draftStroke.isEmpty
                                            ? null
                                            : _draftStroke,
                                        previousOnionSkinStrokes: _showOnionSkin
                                            ? previousFrameStrokes
                                            : const <VectorStroke>[],
                                        nextOnionSkinStrokes: _showOnionSkin
                                            ? nextFrameStrokes
                                            : const <VectorStroke>[],
                                        strokeColor: _brushColor,
                                        strokeWidth: _brushSize,
                                        previousOnionSkinColor: Colors.redAccent
                                            .withValues(alpha: 0.40),
                                        nextOnionSkinColor: Colors.greenAccent
                                            .withValues(alpha: 0.40),
                                      ),
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
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
                                tooltip: frameToolbarExpanded
                                    ? 'Hide Frame Tools'
                                    : 'Show Frame Tools',
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  setState(() {
                                    final next = !frameToolbarExpanded;
                                    _frameToolbarExpanded = next;

                                    if (isNarrowToolbarLayout && next) {
                                      _editToolbarExpanded = false;
                                    }
                                  });
                                },
                                icon: Icon(
                                  frameToolbarExpanded
                                      ? Icons.chevron_left
                                      : Icons.video_collection_outlined,
                                ),
                              ),
                              if (frameToolbarExpanded) ...[
                                IconButton(
                                  tooltip: 'Add Frame',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _isPlaying ? null : _addFrame,
                                  icon: const Icon(Icons.add),
                                ),
                                IconButton(
                                  tooltip: 'Duplicate Frame',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _isPlaying
                                      ? null
                                      : _duplicateFrame,
                                  icon: const Icon(Icons.copy),
                                ),
                                IconButton(
                                  tooltip: 'Delete Frame',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _isPlaying ? null : _deleteFrame,
                                  icon: const Icon(Icons.delete_outline),
                                ),
                                IconButton(
                                  tooltip: 'Clear Frame',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _isPlaying
                                      ? null
                                      : _clearCurrentFrame,
                                  icon: const Icon(Icons.clear),
                                ),
                                IconButton(
                                  tooltip: _isPlaying ? 'Pause' : 'Play',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _togglePlayback,
                                  icon: Icon(
                                    _isPlaying ? Icons.pause : Icons.play_arrow,
                                    color: _isPlaying
                                        ? Colors.deepPurpleAccent
                                        : Colors.white70,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

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
                                    tooltip: _timingExpanded
                                        ? 'Hide Timing'
                                        : 'Show Timing',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      setState(() {
                                        final next = !_timingExpanded;
                                        _timingExpanded = next;

                                        if (next) {
                                          _drawingExpanded = false;
                                        }
                                      });
                                    },
                                    icon: Icon(
                                      Icons.schedule,
                                      color: _timingExpanded
                                          ? Colors.deepPurpleAccent
                                          : Colors.white70,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: _drawingExpanded
                                        ? 'Hide Drawing'
                                        : 'Show Drawing',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      setState(() {
                                        final next = !_drawingExpanded;
                                        _drawingExpanded = next;

                                        if (next) {
                                          _timingExpanded = false;
                                        }
                                      });
                                    },
                                    icon: Icon(
                                      Icons.brush,
                                      color: _drawingExpanded
                                          ? Colors.deepPurpleAccent
                                          : Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_timingExpanded || _drawingExpanded) ...[
                            const SizedBox(width: 8),
                            Material(
                              elevation: 8,
                              color: const Color(0xE61A1720),
                              borderRadius: BorderRadius.circular(16),
                              clipBehavior: Clip.antiAlias,
                              child: SizedBox(
                                width: constraints.maxWidth < 420
                                    ? constraints.maxWidth - 96
                                    : 300,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    10,
                                    14,
                                    12,
                                  ),
                                  child: _timingExpanded
                                      ? Column(
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
                                                    label: _fps.toStringAsFixed(
                                                      0,
                                                    ),
                                                    onChanged: (value) {
                                                      setState(
                                                        () => _fps = value,
                                                      );

                                                      if (_isPlaying) {
                                                        _startPlaybackTimer();
                                                      }
                                                    },
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 28,
                                                  child: Text(
                                                    _fps.toStringAsFixed(0),
                                                  ),
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
                                        )
                                      : Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Row(
                                              children: [
                                                const SizedBox(
                                                  width: 70,
                                                  child: Text('Brush'),
                                                ),
                                                Expanded(
                                                  child: Slider(
                                                    value: _brushSize,
                                                    min: 1,
                                                    max: 20,
                                                    divisions: 19,
                                                    label: _brushSize
                                                        .toStringAsFixed(0),
                                                    onChanged: (value) {
                                                      setState(() {
                                                        _brushSize = value;
                                                      });
                                                    },
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 28,
                                                  child: Text(
                                                    _brushSize.toStringAsFixed(
                                                      0,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                const SizedBox(
                                                  width: 70,
                                                  child: Text('Colour'),
                                                ),
                                                Expanded(
                                                  child: Wrap(
                                                    spacing: 7,
                                                    runSpacing: 7,
                                                    children: [
                                                      for (final color
                                                          in const [
                                                            Colors.red,
                                                            Colors.white,
                                                            Colors.blue,
                                                            Colors.green,
                                                            Colors.yellow,
                                                            Colors.purple,
                                                            Colors.black,
                                                          ])
                                                        GestureDetector(
                                                          onTap: () {
                                                            setState(() {
                                                              _brushColor =
                                                                  color;
                                                            });
                                                          },
                                                          child: Container(
                                                            width: 24,
                                                            height: 24,
                                                            decoration: BoxDecoration(
                                                              color: color,
                                                              shape: BoxShape
                                                                  .circle,
                                                              border: Border.all(
                                                                color:
                                                                    _brushColor ==
                                                                        color
                                                                    ? Colors
                                                                          .deepPurpleAccent
                                                                    : Colors
                                                                          .white38,
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
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    Positioned(
                      top: 16,
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
                                  tooltip: 'Undo',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _undo,
                                  icon: const Icon(Icons.undo),
                                ),
                                IconButton(
                                  tooltip: 'Redo',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _redo,
                                  icon: const Icon(Icons.redo),
                                ),
                                IconButton(
                                  tooltip: 'Onion Skin',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _toggleOnionSkin,
                                  icon: Icon(
                                    Icons.layers,
                                    color: _showOnionSkin
                                        ? Colors.deepPurpleAccent
                                        : Colors.white70,
                                  ),
                                ),
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
                                    });
                                  },
                                  icon: Icon(
                                    Icons.auto_fix_off,
                                    color: _isEraserActive
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

                                    if (isNarrowToolbarLayout && next) {
                                      _frameToolbarExpanded = false;
                                    }
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
                                        child: SizedBox(
                                          height: 64,
                                          child: ReorderableListView.builder(
                                            scrollDirection: Axis.horizontal,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            itemCount: _frames.length,
                                            onReorderItem: _reorderFrame,
                                            itemBuilder: (context, index) {
                                              final isSelected =
                                                  index == _selectedFrameIndex;

                                              return Padding(
                                                key: Key('frame-$index'),
                                                padding: const EdgeInsets.only(
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
                                                            : Colors.white12,
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
                                                                  horizontal: 6,
                                                                  vertical: 2,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                    0xCC121016,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    10,
                                                                  ),
                                                              border: Border.all(
                                                                color:
                                                                    isSelected
                                                                    ? Colors
                                                                          .deepPurpleAccent
                                                                    : Colors
                                                                          .white12,
                                                                width: 1,
                                                              ),
                                                            ),
                                                            child: Text(
                                                              '${_frameDurations[index]}x',
                                                              style:
                                                                  const TextStyle(
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
                                icon: const Icon(Icons.view_timeline_outlined),
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
