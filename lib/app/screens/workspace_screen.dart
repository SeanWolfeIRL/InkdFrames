import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Project saved!')));
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

  void _eraseAt(Offset position) {
    final double currentScale = _transformationController.value
        .getMaxScaleOnAxis();

    final double eraserRadius = 8 / currentScale;
    final double eraserRadiusSquared = eraserRadius * eraserRadius;

    _frames[_selectedFrameIndex].removeWhere((stroke) {
      return stroke.points.any((point) {
        final double dx = point.dx - position.dx;
        final double dy = point.dy - position.dy;
        final double distanceSquared = (dx * dx) + (dy * dy);

        return distanceSquared <= eraserRadiusSquared;
      });
    });
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
    const maximumPointSpacing = 6.0;

    if (distanceSquared < minimumDistanceSquared) {
      return;
    }

    final distance = math.sqrt(distanceSquared);
    final steps = (distance / maximumPointSpacing).ceil();

    setState(() {
      for (var step = 1; step <= steps; step++) {
        final t = step / steps;

        _draftStroke.add(
          VectorPoint(
            dx: lastPoint.dx + (dx * t),
            dy: lastPoint.dy + (dy * t),
            pressure:
                lastPoint.pressure +
                ((event.pressure - lastPoint.pressure) * t),
          ),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final previousFrameStrokes = _getPreviousFrameStrokes();

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
                return Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
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
                                        onionSkinStrokes: _showOnionSkin
                                            ? previousFrameStrokes
                                            : const <VectorStroke>[],
                                        strokeColor: _brushColor,
                                        strokeWidth: _brushSize,
                                        onionSkinColor: Colors.redAccent
                                            .withValues(alpha: 0.45),
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
                                tooltip: 'Add Frame',
                                visualDensity: VisualDensity.compact,
                                onPressed: _isPlaying ? null : _addFrame,
                                icon: const Icon(Icons.add),
                              ),
                              IconButton(
                                tooltip: 'Duplicate Frame',
                                visualDensity: VisualDensity.compact,
                                onPressed: _isPlaying ? null : _duplicateFrame,
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
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      top: 110,
                      left: 16,
                      child: Material(
                        elevation: 8,
                        color: const Color(0xE61A1720),
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: Container(
                          width: (!_timingExpanded && !_drawingExpanded)
                              ? 126
                              : 300,
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  setState(() {
                                    _timingExpanded = !_timingExpanded;
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.schedule, size: 18),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          'Timing',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (_timingExpanded || _drawingExpanded)
                                        Icon(
                                          _timingExpanded
                                              ? Icons.keyboard_arrow_down
                                              : Icons.keyboard_arrow_right,
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_timingExpanded) ...[
                                const SizedBox(height: 4),
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
                                          setState(() => _fps = value);
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
                              const Divider(height: 20),
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  setState(() {
                                    _drawingExpanded = !_drawingExpanded;
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.brush, size: 18),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          'Drawing',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (_timingExpanded || _drawingExpanded)
                                        Icon(
                                          _drawingExpanded
                                              ? Icons.keyboard_arrow_down
                                              : Icons.keyboard_arrow_right,
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_drawingExpanded) ...[
                                const SizedBox(height: 4),
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
                                        label: _brushSize.toStringAsFixed(0),
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
                                        _brushSize.toStringAsFixed(0),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(
                                      width: 70,
                                      child: Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Text('Colour'),
                                      ),
                                    ),
                                    Expanded(
                                      child: Wrap(
                                        spacing: 5,
                                        runSpacing: 7,
                                        children: [
                                          for (final color in const [
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
                                                  _brushColor = color;
                                                });
                                              },
                                              child: Container(
                                                width: 24,
                                                height: 24,
                                                decoration: BoxDecoration(
                                                  color: color,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: _brushColor == color
                                                        ? Colors
                                                              .deepPurpleAccent
                                                        : Colors.white38,
                                                    width: _brushColor == color
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
                            ],
                          ),
                        ),
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
                              IconButton(
                                tooltip: 'Undo',
                                onPressed: _undo,
                                icon: const Icon(Icons.undo),
                              ),
                              IconButton(
                                tooltip: 'Redo',
                                onPressed: _redo,
                                icon: const Icon(Icons.redo),
                              ),
                              IconButton(
                                tooltip: 'Onion Skin',
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
                                onPressed: _resetCanvasView,
                                icon: const Icon(Icons.center_focus_strong),
                              ),
                              IconButton(
                                tooltip: 'Eraser',
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
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth < 392
                              ? constraints.maxWidth - 32
                              : 360,
                          maxWidth: constraints.maxWidth < 392
                              ? constraints.maxWidth - 32
                              : 360,
                        ),
                        child: Material(
                          elevation: 8,
                          color: const Color(0xE61A1720),
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 72,
                                  child: ReorderableListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    itemCount: _frames.length,
                                    onReorderItem: _reorderFrame,
                                    itemBuilder: (context, index) {
                                      final isSelected =
                                          index == _selectedFrameIndex;
                                      return Padding(
                                        key: Key('frame-$index'),
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: InkWell(
                                          onTap: () => _selectFrame(index),
                                          child: Container(
                                            width: 72,
                                            clipBehavior: Clip.antiAlias,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: isSelected
                                                    ? Colors.deepPurpleAccent
                                                    : Colors.white12,
                                                width: isSelected ? 3 : 1,
                                              ),
                                            ),
                                            child: Stack(
                                              children: [
                                                CustomPaint(
                                                  painter:
                                                      FrameThumbnailPainter(
                                                        strokes: _frames[index],
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
                                                      color: const Color(
                                                        0xCC121016,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                      border: Border.all(
                                                        color: isSelected
                                                            ? Colors
                                                                  .deepPurpleAccent
                                                            : Colors.white12,
                                                        width: 1,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '${_frameDurations[index]}x',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.white,
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
                                // frame controls will go here
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
