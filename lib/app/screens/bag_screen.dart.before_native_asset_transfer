import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bag_item.dart';
import '../models/vector_stroke.dart';
import '../painters/bag_item_preview_painter.dart';
import '../painters/frame_thumbnail_painter.dart';
import '../services/bag_service.dart';

class _BagPocket {
  const _BagPocket({
    required this.id,
    required this.name,
    required this.isBuiltIn,
  });

  final String id;
  final String name;
  final bool isBuiltIn;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'id': id, 'name': name, 'isBuiltIn': isBuiltIn};
  }

  factory _BagPocket.fromJson(Map<String, dynamic> json) {
    return _BagPocket(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Pocket',
      isBuiltIn: json['isBuiltIn'] == true,
    );
  }
}

class BagScreen extends StatefulWidget {
  const BagScreen({super.key, this.selectionMode = false});

  final bool selectionMode;

  @override
  State<BagScreen> createState() => _BagScreenState();
}

class _BagScreenState extends State<BagScreen> {
  final BagService _bagService = BagService();

  List<BagItem> _items = <BagItem>[];
  bool _loading = true;

  Map<String, String> _pocketAssignments = {};
  List<_BagPocket> _customPockets = <_BagPocket>[];

  static const String _customPocketsKey = 'inkdframes_bag_custom_pockets_v1';

  List<_BagPocket> get _allPockets => <_BagPocket>[
    ..._builtInPockets,
    ..._customPockets,
  ];

  static const List<_BagPocket> _builtInPockets = <_BagPocket>[
    _BagPocket(id: 'built_in_sketches', name: 'Sketches', isBuiltIn: true),
    _BagPocket(id: 'built_in_characters', name: 'Characters', isBuiltIn: true),
    _BagPocket(id: 'built_in_textures', name: 'Textures', isBuiltIn: true),
    _BagPocket(id: 'built_in_props', name: 'Props', isBuiltIn: true),
    _BagPocket(id: 'built_in_brushes', name: 'Brushes', isBuiltIn: true),
    _BagPocket(id: 'built_in_misc', name: 'Misc.', isBuiltIn: true),
  ];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  static const String _pocketAssignmentsKey =
      'inkdframes_bag_pocket_assignments_v1';

  Future<void> _loadCustomPockets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customPocketsKey);

    if (raw == null || raw.isEmpty) {
      _customPockets = <_BagPocket>[];
      return;
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        _customPockets = <_BagPocket>[];
        return;
      }

      _customPockets = decoded
          .whereType<Map>()
          .map(
            (entry) => _BagPocket.fromJson(
              entry.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .where((pocket) => pocket.id.isNotEmpty)
          .toList();
    } catch (_) {
      _customPockets = <_BagPocket>[];
    }
  }

  Future<void> _saveCustomPockets() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _customPocketsKey,
      jsonEncode(_customPockets.map((pocket) => pocket.toJson()).toList()),
    );
  }

  bool _pocketNameExists(String name, {String? excludingId}) {
    final normalized = name.trim().toLowerCase();

    return _allPockets.any(
      (pocket) =>
          pocket.id != excludingId &&
          pocket.name.trim().toLowerCase() == normalized,
    );
  }

  Future<bool> _createCustomPocket() async {
    var draftName = '';

    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        String? errorText;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
              backgroundColor: const Color(0xFFF0D9AD),
              title: const Text(
                'CREATE A POCKET',
                style: TextStyle(
                  color: Color(0xFF4A2E1E),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              content: TextField(
                autofocus: true,
                maxLength: 32,
                style: const TextStyle(color: Color(0xFF3E2A1D)),
                cursorColor: const Color(0xFF5A3924),
                decoration: InputDecoration(
                  labelText: 'Pocket name',
                  hintText: 'Outfits',
                  errorText: errorText,
                  labelStyle: const TextStyle(color: Color(0xFF795232)),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0x80795232)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF5A3924), width: 2),
                  ),
                ),
                onChanged: (value) {
                  draftName = value;
                },
                onSubmitted: (_) {
                  final name = draftName.trim();

                  if (name.isEmpty) {
                    setDialogState(() {
                      errorText = 'Give your Pocket a name.';
                    });
                    return;
                  }

                  if (_pocketNameExists(name)) {
                    setDialogState(() {
                      errorText = 'A Pocket with that name already exists.';
                    });
                    return;
                  }

                  Navigator.pop(dialogContext, name);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF795232)),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5A3924),
                    foregroundColor: const Color(0xFFF7E8C8),
                  ),
                  onPressed: () {
                    final name = draftName.trim();

                    if (name.isEmpty) {
                      setDialogState(() {
                        errorText = 'Give your Pocket a name.';
                      });
                      return;
                    }

                    if (_pocketNameExists(name)) {
                      setDialogState(() {
                        errorText = 'A Pocket with that name already exists.';
                      });
                      return;
                    }

                    Navigator.pop(dialogContext, name);
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) {
      return false;
    }

    final pocket = _BagPocket(
      id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
      name: result.trim(),
      isBuiltIn: false,
    );

    setState(() {
      _customPockets.add(pocket);
    });

    await _saveCustomPockets();

    return true;
  }

  Future<bool> _renameCustomPocket(_BagPocket pocket) async {
    var draftName = pocket.name;

    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        String? errorText;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
              backgroundColor: const Color(0xFFF0D9AD),
              title: const Text(
                'RENAME POCKET',
                style: TextStyle(
                  color: Color(0xFF4A2E1E),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              content: TextFormField(
                initialValue: pocket.name,
                autofocus: true,
                maxLength: 32,
                style: const TextStyle(color: Color(0xFF3E2A1D)),
                cursorColor: const Color(0xFF5A3924),
                decoration: InputDecoration(
                  labelText: 'Pocket name',
                  errorText: errorText,
                  labelStyle: const TextStyle(color: Color(0xFF795232)),
                ),
                onChanged: (value) {
                  draftName = value;
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF795232)),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5A3924),
                    foregroundColor: const Color(0xFFF7E8C8),
                  ),
                  onPressed: () {
                    final name = draftName.trim();

                    if (name.isEmpty) {
                      setDialogState(() {
                        errorText = 'Give your Pocket a name.';
                      });
                      return;
                    }

                    if (_pocketNameExists(name, excludingId: pocket.id)) {
                      setDialogState(() {
                        errorText = 'A Pocket with that name already exists.';
                      });
                      return;
                    }

                    Navigator.pop(dialogContext, name);
                  },
                  child: const Text('Rename'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) {
      return false;
    }

    final index = _customPockets.indexWhere(
      (candidate) => candidate.id == pocket.id,
    );

    if (index == -1) {
      return false;
    }

    setState(() {
      _customPockets[index] = _BagPocket(
        id: pocket.id,
        name: result.trim(),
        isBuiltIn: false,
      );
    });

    await _saveCustomPockets();

    return true;
  }

  Future<bool> _deleteCustomPocket(_BagPocket pocket) async {
    final itemCount = _pocketAssignments.values
        .where((pocketId) => pocketId == pocket.id)
        .length;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFFF0D9AD),
          title: Text(
            'Delete "${pocket.name}"?',
            style: const TextStyle(
              color: Color(0xFF4A2E1E),
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            itemCount == 0
                ? 'This removes the Pocket. No Bag items will be deleted.'
                : '$itemCount ${itemCount == 1 ? 'item' : 'items'} will become Unsorted. The items themselves will remain safely in your Bag.',
            style: const TextStyle(color: Color(0xFF5A3924), height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF795232)),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6B3027),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete Pocket'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return false;
    }

    setState(() {
      _customPockets.removeWhere((candidate) => candidate.id == pocket.id);

      _pocketAssignments.removeWhere((_, pocketId) => pocketId == pocket.id);
    });

    await _saveCustomPockets();
    await _savePocketAssignments();

    return true;
  }

  Future<void> _loadPocketAssignments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pocketAssignmentsKey);

    if (raw == null || raw.isEmpty) {
      _pocketAssignments = {};
      return;
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        _pocketAssignments = {};
        return;
      }

      _pocketAssignments = decoded.map<String, String>(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );

      // Migrate the original name-based assignments to stable Pocket IDs.
      final legacyPocketIds = <String, String>{
        'Sketches': 'built_in_sketches',
        'Characters': 'built_in_characters',
        'Textures': 'built_in_textures',
        'Props': 'built_in_props',
        'Brushes': 'built_in_brushes',
        'Misc.': 'built_in_misc',
      };

      var migrated = false;

      for (final entry in _pocketAssignments.entries.toList()) {
        final stableId = legacyPocketIds[entry.value];

        if (stableId != null) {
          _pocketAssignments[entry.key] = stableId;
          migrated = true;
        }
      }

      if (migrated) {
        await prefs.setString(
          _pocketAssignmentsKey,
          jsonEncode(_pocketAssignments),
        );
      }
    } catch (_) {
      _pocketAssignments = {};
    }
  }

  Future<void> _savePocketAssignments() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _pocketAssignmentsKey,
      jsonEncode(_pocketAssignments),
    );
  }

  Future<void> _loadItems() async {
    await _loadCustomPockets();
    await _loadPocketAssignments();
    final items = await _bagService.loadItems();

    if (!mounted) return;

    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _deleteItem(BagItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Bag item?'),
          content: Text('Remove "${item.name}" from your Bag?'),
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

    if (confirmed != true) return;

    await _bagService.deleteItem(item.id);

    _pocketAssignments.remove(item.id);
    await _savePocketAssignments();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.name} removed from your Bag')),
    );

    await _loadItems();
  }

  Future<void> _assignItemToPocket(BagItem item) async {
    const unsortedValue = '__unsorted__';

    final selectedPocketId = await showModalBottomSheet<String>(
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
                  'Move "${item.name}" to which Pocket?',
                  style: const TextStyle(
                    color: Color(0xFFF1D3A2),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final pocket in _allPockets)
                ListTile(
                  leading: const Icon(
                    Icons.inventory_2_outlined,
                    color: Color(0xFFF1D3A2),
                  ),
                  title: Text(
                    pocket.name,
                    style: const TextStyle(color: Color(0xFFF4E5CF)),
                  ),
                  trailing: _pocketAssignments[item.id] == pocket.id
                      ? const Icon(Icons.check, color: Color(0xFFF1D3A2))
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext, pocket.id);
                  },
                ),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(
                  Icons.inbox_outlined,
                  color: Colors.white54,
                ),
                title: const Text(
                  'Unsorted',
                  style: TextStyle(color: Color(0xFFCFB997)),
                ),
                trailing: !_pocketAssignments.containsKey(item.id)
                    ? const Icon(Icons.check, color: Color(0xFFF1D3A2))
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext, unsortedValue);
                },
              ),
            ],
          ),
        );
      },
    );

    if (selectedPocketId == null || !mounted) {
      return;
    }

    setState(() {
      if (selectedPocketId == unsortedValue) {
        _pocketAssignments.remove(item.id);
      } else {
        _pocketAssignments[item.id] = selectedPocketId;
      }
    });

    await _savePocketAssignments();
  }

  List<VectorStroke> _bagItemPreviewStrokes(BagItem item) {
    final strokes = <VectorStroke>[];

    // Match Workspace composition order:
    // the layer list is top-to-bottom, so paint bottom layers first.
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

  Widget _bagItemThumbnail(BagItem item) {
    final strokes = _bagItemPreviewStrokes(item);

    return SizedBox(
      width: 64,
      height: 64,
      child: CustomPaint(
        painter: strokes.isEmpty
            ? null
            : FrameThumbnailPainter(strokes: strokes),
        child: strokes.isEmpty
            ? const Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.white38,
                ),
              )
            : const SizedBox.expand(),
      ),
    );
  }

  Future<void> _viewBagItem(BagItem item) async {
    final strokes = _bagItemPreviewStrokes(item);

    if (strokes.isEmpty) {
      return;
    }

    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        barrierDismissible: true,
        pageBuilder: (viewerContext, animation, secondaryAnimation) {
          return _BagItemViewer(item: item, strokes: strokes);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _openUnsorted() async {
    final unsortedItems = _items
        .where((item) => !_pocketAssignments.containsKey(item.id))
        .toList();

    await _showPocketItems(title: 'Unsorted', items: unsortedItems);
  }

  Future<void> _showPocketItems({
    required String title,
    required List<BagItem> items,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF21160F),
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFF1D3A2),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Text(
                      'This Pocket is empty.',
                      style: TextStyle(color: Color(0xFFCFB997), fontSize: 15),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const Divider(color: Colors.white12),
                      itemBuilder: (context, index) {
                        final item = items[index];

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          leading: _bagItemThumbnail(item),
                          title: Text(
                            item.name,
                            style: const TextStyle(color: Color(0xFFF4E5CF)),
                          ),
                          subtitle: Text(
                            widget.selectionMode
                                ? 'Tap to place in Home'
                                : 'Tap to use in Workspace',
                            style: const TextStyle(color: Colors.white54),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'View item',
                                icon: const Icon(
                                  Icons.zoom_in_rounded,
                                  color: Color(0xFFF1D3A2),
                                ),
                                onPressed: () async {
                                  Navigator.pop(sheetContext);
                                  await _viewBagItem(item);
                                },
                              ),
                              IconButton(
                                tooltip: 'Move to another Pocket',
                                icon: const Icon(
                                  Icons.drive_file_move_outline,
                                  color: Color(0xFFF1D3A2),
                                ),
                                onPressed: () async {
                                  Navigator.pop(sheetContext);
                                  await _assignItemToPocket(item);
                                },
                              ),
                              IconButton(
                                tooltip: 'Delete from Bag',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.white54,
                                ),
                                onPressed: () async {
                                  Navigator.pop(sheetContext);
                                  await _deleteItem(item);
                                },
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            Navigator.pop(context, item);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPocket(String pocketId) async {
    final pocket = _allPockets.firstWhere(
      (candidate) => candidate.id == pocketId,
    );

    final pocketItems = _items
        .where((item) => _pocketAssignments[item.id] == pocket.id)
        .toList();

    await _showPocketItems(title: pocket.name, items: pocketItems);
  }

  Future<void> _openPocketIndex() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF21160F),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.78,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'YOUR POCKETS',
                              style: TextStyle(
                                color: Color(0xFFF1D3A2),
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF6D482C),
                              foregroundColor: const Color(0xFFF7E8C8),
                            ),
                            onPressed: () async {
                              final created = await _createCustomPocket();

                              if (created && sheetContext.mounted) {
                                setSheetState(() {});
                              }
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Create Pocket'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white12),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(8, 8, 8, 6),
                              child: Text(
                                'BUILT-IN',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            for (final pocket in _builtInPockets)
                              ListTile(
                                leading: const Icon(
                                  Icons.inventory_2_outlined,
                                  color: Color(0xFFF1D3A2),
                                ),
                                title: Text(
                                  pocket.name,
                                  style: const TextStyle(
                                    color: Color(0xFFF4E5CF),
                                  ),
                                ),
                                trailing: Text(
                                  '${_pocketAssignments.values.where((id) => id == pocket.id).length}',
                                  style: const TextStyle(color: Colors.white54),
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _openPocket(pocket.id);
                                },
                              ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(8, 18, 8, 6),
                              child: Text(
                                'CUSTOM',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            if (_customPockets.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 18,
                                ),
                                child: Text(
                                  'No custom Pockets yet. Create one and make the Bag your own.',
                                  style: TextStyle(
                                    color: Color(0xFFCFB997),
                                    height: 1.4,
                                  ),
                                ),
                              )
                            else
                              for (final pocket in _customPockets)
                                ListTile(
                                  leading: const Icon(
                                    Icons.folder_outlined,
                                    color: Color(0xFFF1D3A2),
                                  ),
                                  title: Text(
                                    pocket.name,
                                    style: const TextStyle(
                                      color: Color(0xFFF4E5CF),
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${_pocketAssignments.values.where((id) => id == pocket.id).length} items',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Rename Pocket',
                                        onPressed: () async {
                                          final renamed =
                                              await _renameCustomPocket(pocket);

                                          if (renamed && sheetContext.mounted) {
                                            setSheetState(() {});
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          color: Color(0xFFF1D3A2),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete Pocket',
                                        onPressed: () async {
                                          final deleted =
                                              await _deleteCustomPocket(pocket);

                                          if (deleted && sheetContext.mounted) {
                                            setSheetState(() {});
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _openPocket(pocket.id);
                                  },
                                ),
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
                            ListTile(
                              leading: const Icon(
                                Icons.inbox_outlined,
                                color: Color(0xFFCFB997),
                              ),
                              title: const Text(
                                'Unsorted',
                                style: TextStyle(color: Color(0xFFF4E5CF)),
                              ),
                              subtitle: const Text(
                                'Items not currently assigned to a Pocket',
                                style: TextStyle(color: Colors.white54),
                              ),
                              trailing: Text(
                                '${_items.where((item) => !_pocketAssignments.containsKey(item.id)).length}',
                                style: const TextStyle(color: Colors.white54),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _openUnsorted();
                              },
                            ),
                          ],
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
  }

  Future<void> _openNotes() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) {
      return;
    }

    const notesKey = 'inkdframes_bag_notes_v1';
    final savedText = prefs.getString(notesKey) ?? '';
    var draftText = savedText;

    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        final screenHeight = MediaQuery.sizeOf(dialogContext).height;
        final keyboardHeight = MediaQuery.viewInsetsOf(dialogContext).bottom;

        final availableHeight = screenHeight - keyboardHeight - 48;

        final dialogMaxHeight = availableHeight < 220
            ? 220.0
            : availableHeight > 620
            ? 620.0
            : availableHeight;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: dialogMaxHeight,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF0D9AD),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF795232), width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.menu_book_rounded,
                        color: Color(0xFF5A3924),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'NOTES',
                          style: TextStyle(
                            color: Color(0xFF4A2E1E),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close, color: Color(0xFF5A3924)),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0x80795232)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: savedText,
                      autofocus: true,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      onChanged: (value) {
                        draftText = value;
                      },
                      style: const TextStyle(
                        color: Color(0xFF3E2A1D),
                        fontSize: 17,
                        height: 1.45,
                      ),
                      cursorColor: const Color(0xFF5A3924),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText:
                            'Ideas, reminders, strange little thoughts...',
                        hintStyle: TextStyle(color: Color(0x885A3924)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF5A3924),
                        foregroundColor: const Color(0xFFF7E8C8),
                      ),
                      onPressed: () {
                        Navigator.pop(dialogContext, draftText);
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (result == null) {
      return;
    }

    await prefs.setString(notesKey, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isPortrait = constraints.maxHeight > constraints.maxWidth;

          // The Bag always exists in its native 1536 x 1024 world.
          // All painted hotspots remain attached to these coordinates.
          Widget buildBagWorld() {
            return SizedBox(
              width: 1536,
              height: 1024,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/inkdframes_bag_open_v1.png',
                      fit: BoxFit.fill,
                    ),
                  ),

                  // Painted CREATE POCKET + card.
                  Positioned(
                    left: 1235,
                    top: 50,
                    width: 250,
                    height: 215,
                    child: Semantics(
                      button: true,
                      label: 'Open Pocket Index',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openPocketIndex,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),

                  // SKETCHES
                  Positioned(
                    left: 435,
                    top: 385,
                    width: 145,
                    height: 70,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openPocket('built_in_sketches'),
                      child: Semantics(
                        button: true,
                        label: 'Open Sketches Pocket',
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),

                  // CHARACTERS
                  Positioned(
                    left: 725,
                    top: 380,
                    width: 160,
                    height: 75,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openPocket('built_in_characters'),
                      child: Semantics(
                        button: true,
                        label: 'Open Characters Pocket',
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),

                  // TEXTURES
                  Positioned(
                    left: 1010,
                    top: 380,
                    width: 155,
                    height: 75,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openPocket('built_in_textures'),
                      child: Semantics(
                        button: true,
                        label: 'Open Textures Pocket',
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),

                  // PROPS
                  Positioned(
                    left: 1010,
                    top: 570,
                    width: 140,
                    height: 70,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openPocket('built_in_props'),
                      child: Semantics(
                        button: true,
                        label: 'Open Props Pocket',
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),

                  // BRUSHES
                  Positioned(
                    left: 730,
                    top: 670,
                    width: 135,
                    height: 75,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openPocket('built_in_brushes'),
                      child: Semantics(
                        button: true,
                        label: 'Open Brushes Pocket',
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),

                  // MISC.
                  Positioned(
                    left: 975,
                    top: 745,
                    width: 130,
                    height: 70,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openPocket('built_in_misc'),
                      child: Semantics(
                        button: true,
                        label: 'Open Misc Pocket',
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),

                  // Painted NOTES notebook.
                  Positioned(
                    left: 20,
                    top: 600,
                    width: 260,
                    height: 270,
                    child: Semantics(
                      button: true,
                      label: 'Open Bag notes',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openNotes,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),

                  // Painted BACK control.
                  Positioned(
                    left: 1280,
                    top: 905,
                    width: 220,
                    height: 90,
                    child: Semantics(
                      button: true,
                      label: 'Return to workspace',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(context),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // Wide screens keep the full satchel visible as before.
          if (!isPortrait) {
            return Center(
              child: FittedBox(fit: BoxFit.contain, child: buildBagWorld()),
            );
          }

          // Portrait becomes a camera looking into the Bag.
          // Fill the screen vertically, then pan horizontally through
          // the wider 3:2 environment instead of shrinking it down.
          final cameraHeight = constraints.maxHeight;
          final cameraWidth = cameraHeight * (1536 / 1024);

          return InteractiveViewer(
            constrained: false,
            panEnabled: true,
            scaleEnabled: false,
            boundaryMargin: EdgeInsets.zero,
            clipBehavior: Clip.hardEdge,
            alignment: Alignment.center,
            child: SizedBox(
              width: cameraWidth,
              height: cameraHeight,
              child: FittedBox(fit: BoxFit.fill, child: buildBagWorld()),
            ),
          );
        },
      ),
    );
  }
}

class _BagItemViewer extends StatefulWidget {
  const _BagItemViewer({required this.item, required this.strokes});

  final BagItem item;
  final List<VectorStroke> strokes;

  @override
  State<_BagItemViewer> createState() => _BagItemViewerState();
}

class _BagItemViewerState extends State<_BagItemViewer> {
  double _scale = 1.0;
  double _rotation = 0.0;
  Offset _position = Offset.zero;

  double _startScale = 1.0;
  double _startRotation = 0.0;
  Offset _startPosition = Offset.zero;
  Offset _startFocalPoint = Offset.zero;

  void _reset() {
    setState(() {
      _scale = 1.0;
      _rotation = 0.0;
      _position = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(color: Colors.black.withValues(alpha: 0.42)),
            ),
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: (details) {
                  _startScale = _scale;
                  _startRotation = _rotation;
                  _startPosition = _position;
                  _startFocalPoint = details.focalPoint;
                },
                onScaleUpdate: (details) {
                  setState(() {
                    _scale = (_startScale * details.scale).clamp(0.35, 6.0);
                    _rotation = _startRotation + details.rotation;

                    final movement = details.focalPoint - _startFocalPoint;

                    _position = _startPosition + movement;
                  });
                },
                child: Transform.translate(
                  offset: _position,
                  child: Transform.rotate(
                    angle: _rotation,
                    child: Transform.scale(
                      scale: _scale,
                      child: SizedBox(
                        width: MediaQuery.sizeOf(context).width * 0.65,
                        height: MediaQuery.sizeOf(context).height * 0.65,
                        child: CustomPaint(
                          painter: BagItemPreviewPainter(
                            strokes: widget.strokes,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              top: 16,
              child: Text(
                widget.item.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: 8,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Reset view',
                    onPressed: _reset,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
