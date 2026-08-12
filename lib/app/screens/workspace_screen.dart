import 'dart:async';

import 'package:flutter/material.dart';

import '../models/vector_point.dart';
import '../models/vector_stroke.dart';
import '../painters/animation_canvas_painter.dart';
import '../painters/frame_thumbnail_painter.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  static const routeName = '/workspace';

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final List<List<VectorStroke>> _frames = [<VectorStroke>[]];
  int _selectedFrameIndex = 0;
  List<VectorPoint> _draftStroke = const <VectorPoint>[];
  Timer? _playbackTimer;
  bool _isPlaying = false;
  bool _showOnionSkin = true;
  bool _isEraserActive = false;
  double _fps = 8;
  double _brushSize = 4.0;
  Color _brushColor = Colors.white;
  final List<List<List<VectorStroke>>> _undoStacks = [[]];
  final List<List<List<VectorStroke>>> _redoStacks = [[]];

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  void _addFrame() {
    setState(() {
      _frames.add(<VectorStroke>[]);
      _undoStacks.add([]);
      _redoStacks.add([]);

      _selectedFrameIndex = _frames.length - 1;
      _draftStroke = const <VectorPoint>[];
    });
  }

  void _duplicateFrame() {
    setState(() {
      final copiedFrame = _frames[_selectedFrameIndex]
          .map((stroke) => stroke.copy())
          .toList();

      _frames.add(copiedFrame);
      _undoStacks.add([]);
      _redoStacks.add([]);

      _selectedFrameIndex = _frames.length - 1;
      _draftStroke = const <VectorPoint>[];
    });
  }

  void _deleteFrame() {
    if (_frames.length <= 1) return;

    setState(() {
      _frames.removeAt(_selectedFrameIndex);
      _undoStacks.removeAt(_selectedFrameIndex);
      _redoStacks.removeAt(_selectedFrameIndex);

      if (_selectedFrameIndex >= _frames.length) {
        _selectedFrameIndex = _frames.length - 1;
      }

      _draftStroke = const <VectorPoint>[];
    });
  }

  void _toggleOnionSkin() {
    setState(() {
      _showOnionSkin = !_showOnionSkin;
    });
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

    _playbackTimer = Timer.periodic(
      Duration(milliseconds: (1000 / _fps).round().clamp(40, 1000)),
      (_) {
        if (!mounted) return;

        setState(() {
          if (_selectedFrameIndex < _frames.length - 1) {
            _selectedFrameIndex += 1;
          } else {
            _selectedFrameIndex = 0;
          }
        });
      },
    );
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
    const double eraserRadius = 20;
    const double eraserRadiusSquared = eraserRadius * eraserRadius;

    _frames[_selectedFrameIndex].removeWhere((stroke) {
      return stroke.points.any((point) {
        final double dx = point.dx - position.dx;
        final double dy = point.dy - position.dy;
        final double distanceSquared = (dx * dx) + (dy * dy);

        return distanceSquared <= eraserRadiusSquared;
      });
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_isPlaying) {
      return;
    }

    if (_isEraserActive) {
      setState(() {
        _eraseAt(event.localPosition);
      });
      return;
    }

    setState(() {
      _draftStroke = <VectorPoint>[
        VectorPoint(
          dx: event.localPosition.dx,
          dy: event.localPosition.dy,
          pressure: event.pressure,
        ),
      ];
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_isPlaying) {
      return;
    }

    if (_isEraserActive) {
      setState(() {
        _eraseAt(event.localPosition);
      });
      return;
    }

    if (_draftStroke.isEmpty) {
      return;
    }

    setState(() {
      _draftStroke = <VectorPoint>[
        ..._draftStroke,
        VectorPoint(
          dx: event.localPosition.dx,
          dy: event.localPosition.dy,
          pressure: event.pressure,
        ),
      ];
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
  }

  void _handlePointerUp(PointerUpEvent event) {
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
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_isPlaying) {
      return;
    }
    setState(() {
      _draftStroke = const <VectorPoint>[];
    });
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
      appBar: AppBar(title: const Text('Workspace'), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _addFrame,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Frame'),
                ),
                OutlinedButton.icon(
                  onPressed: _duplicateFrame,
                  icon: const Icon(Icons.copy),
                  label: const Text('Duplicate'),
                ),
                OutlinedButton.icon(
                  onPressed: _deleteFrame,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
                OutlinedButton.icon(
                  onPressed: _clearCurrentFrame,
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear Frame'),
                ),
                OutlinedButton.icon(
                  onPressed: _undo,
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo'),
                ),
                OutlinedButton.icon(
                  onPressed: _redo,
                  icon: const Icon(Icons.redo),
                  label: const Text('Redo'),
                ),
                OutlinedButton.icon(
                  onPressed: _togglePlayback,
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(_isPlaying ? 'Pause' : 'Play'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isEraserActive = !_isEraserActive;
                    });
                  },
                  icon: Icon(
                    Icons.auto_fix_off,
                    color: _isEraserActive
                        ? Colors.deepPurpleAccent
                        : Colors.white38,
                  ),
                  label: Text(_isEraserActive ? 'Eraser On' : 'Eraser Off'),
                ),
                OutlinedButton.icon(
                  onPressed: _toggleOnionSkin,
                  icon: Icon(
                    Icons.layers,
                    color: _showOnionSkin
                        ? Colors.deepPurpleAccent
                        : Colors.white38,
                  ),
                  label: Text(_showOnionSkin ? 'Onion On' : 'Onion Off'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('FPS'),
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
                Text(_fps.toStringAsFixed(0)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Brush'),
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
                Text(_brushSize.toStringAsFixed(0)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Colour'),
                const SizedBox(width: 12),

                GestureDetector(
                  onTap: () {
                    setState(() {
                      _brushColor = Colors.red;
                    });
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _brushColor == Colors.red
                            ? Colors.deepPurpleAccent
                            : Colors.white38,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _brushColor = Colors.white;
                    });
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _brushColor == Colors.white
                            ? Colors.deepPurpleAccent
                            : Colors.white38,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _brushColor = Colors.blue;
                    });
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _brushColor == Colors.blue
                            ? Colors.deepPurpleAccent
                            : Colors.white38,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _brushColor = Colors.green;
                    });
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _brushColor == Colors.green
                            ? Colors.deepPurpleAccent
                            : Colors.white38,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _brushColor = Colors.yellow;
                    });
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.yellow,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _brushColor == Colors.yellow
                            ? Colors.deepPurpleAccent
                            : Colors.white38,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _brushColor = Colors.purple;
                    });
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.purple,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _brushColor == Colors.purple
                            ? Colors.deepPurpleAccent
                            : Colors.white38,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _brushColor = Colors.black;
                    });
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _brushColor == Colors.black
                            ? Colors.deepPurpleAccent
                            : Colors.white38,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _frames.length,
              itemBuilder: (context, index) {
                final isSelected = index == _selectedFrameIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    key: Key('frame-$index'),
                    onTap: () => _selectFrame(index),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 72,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : const Color(0xFF2A2439),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? Colors.cyanAccent
                              : Colors.white24,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: CustomPaint(
                        painter: FrameThumbnailPainter(strokes: _frames[index]),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Listener(
                onPointerDown: _handlePointerDown,
                onPointerMove: _handlePointerMove,
                onPointerUp: _handlePointerUp,
                onPointerCancel: _handlePointerCancel,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: CustomPaint(
                    painter: AnimationCanvasPainter(
                      strokes: _frames[_selectedFrameIndex],
                      currentStroke: _draftStroke.isEmpty ? null : _draftStroke,
                      onionSkinStrokes: _showOnionSkin
                          ? previousFrameStrokes
                          : const <VectorStroke>[],
                      strokeColor: _brushColor,
                      strokeWidth: _brushSize,
                      onionSkinColor: Colors.redAccent.withValues(alpha: 0.45),
                    ),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
