import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'project_library_screen.dart';
import 'welcome_home_screen.dart';
import 'workspace_screen.dart';
import 'bag_screen.dart';
import '../models/bag_item.dart';
import '../models/placed_decoration.dart';
import '../models/vector_stroke.dart';
import '../painters/bag_item_preview_painter.dart';
import '../services/bag_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _decorationsKey = 'inkdframes_home_decorations_v1';

  final BagService _bagService = BagService();

  List<PlacedDecoration> _decorations = <PlacedDecoration>[];

  Map<String, BagItem> _bagItemsById = <String, BagItem>{};

  bool _decorateMode = false;
  String? _selectedDecorationId;

  final ScrollController _homeScrollController = ScrollController();

  final Map<int, Offset> _decorateTouchPointers = <int, Offset>{};
  Offset? _decoratePanCentroid;

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

    _decorateTouchPointers.remove(event.pointer);

    if (_decorateTouchPointers.length >= 2) {
      _decoratePanCentroid = _touchCentroid();
    } else {
      _decoratePanCentroid = null;
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

    setState(() {
      _decorations = decorations;
      _bagItemsById = <String, BagItem>{
        for (final item in items) item.id: item,
      };
    });
  }

  Future<void> _saveDecorations() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _decorationsKey,
      jsonEncode(
        _decorations.map((decoration) => decoration.toJson()).toList(),
      ),
    );
  }

  List<VectorStroke> _bagItemStrokes(BagItem item) {
    return item.layers
        .where((layer) => layer.visible)
        .expand((layer) => layer.strokes)
        .toList();
  }

  Future<void> _chooseDecoration() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _bagService.loadItems();

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
                                          child: CustomPaint(
                                            painter: BagItemPreviewPainter(
                                              strokes: _bagItemStrokes(item),
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

  Future<void> _scaleSelectedDecoration(double factor) async {
    final selected = _selectedDecoration;
    if (selected == null) return;

    setState(() {
      _replaceDecoration(
        selected.copyWith(scale: (selected.scale * factor).clamp(0.15, 8.0)),
      );
    });

    await _saveDecorations();
  }

  Future<void> _mirrorSelectedDecoration() async {
    final selected = _selectedDecoration;
    if (selected == null) return;

    setState(() {
      _replaceDecoration(selected.copyWith(mirrored: !selected.mirrored));
    });

    await _saveDecorations();
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
                      Positioned(
                        left: (decoration.x * roomWidth) - (roomWidth * 0.09),
                        top: (decoration.y * roomHeight) - (roomHeight * 0.09),
                        width: roomWidth * 0.18,
                        height: roomHeight * 0.18,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _decorateMode
                              ? () {
                                  setState(() {
                                    _selectedDecorationId = decoration.id;
                                  });
                                }
                              : null,
                          onPanStart: !_decorateMode
                              ? null
                              : (_) {
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

                                  setState(() {
                                    _replaceDecoration(
                                      decoration.copyWith(
                                        x:
                                            (decoration.x +
                                                    (details.delta.dx /
                                                        roomWidth))
                                                .clamp(0.0, 1.0),
                                        y:
                                            (decoration.y +
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
                                  _saveDecorations();
                                },
                          child: Transform.scale(
                            scaleX: decoration.mirrored
                                ? -decoration.scale
                                : decoration.scale,
                            scaleY: decoration.scale,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border:
                                    _decorateMode &&
                                        _selectedDecorationId == decoration.id
                                    ? Border.all(
                                        color: Colors.cyanAccent,
                                        width: 2,
                                      )
                                    : null,
                              ),
                              child: CustomPaint(
                                painter: BagItemPreviewPainter(
                                  strokes: _bagItemStrokes(
                                    _bagItemsById[decoration.bagItemId]!,
                                  ),
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
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
                    child: Material(
                      color: const Color(0xDD1A1720),
                      borderRadius: BorderRadius.circular(18),
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
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
                            if (_decorateMode &&
                                _selectedDecoration != null) ...[
                              IconButton(
                                tooltip: 'Scale down',
                                onPressed: () {
                                  _scaleSelectedDecoration(0.9);
                                },
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.white,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Scale up',
                                onPressed: () {
                                  _scaleSelectedDecoration(1.1);
                                },
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.white,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Mirror horizontally',
                                onPressed: _mirrorSelectedDecoration,
                                icon: const Icon(
                                  Icons.flip,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                            if (_decorateMode && _selectedDecoration != null)
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
