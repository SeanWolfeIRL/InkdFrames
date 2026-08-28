import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bag_item.dart';
import '../services/bag_service.dart';

class BagScreen extends StatefulWidget {
  const BagScreen({super.key});

  @override
  State<BagScreen> createState() => _BagScreenState();
}

class _BagScreenState extends State<BagScreen> {
  final BagService _bagService = BagService();

  List<BagItem> _items = <BagItem>[];
  bool _loading = true;

  Map<String, String> _pocketAssignments = {};

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  static const String _pocketAssignmentsKey =
      'inkdframes_bag_pocket_assignments_v1';

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
                  'Put "${item.name}" in which Pocket?',
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
                  trailing: _pocketAssignments[item.id] == pocket
                      ? const Icon(Icons.check, color: Color(0xFFF1D3A2))
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext, pocket);
                  },
                ),
            ],
          ),
        );
      },
    );

    if (selectedPocket == null || !mounted) {
      return;
    }

    setState(() {
      _pocketAssignments[item.id] = selectedPocket;
    });

    await _savePocketAssignments();
  }

  Future<void> _showTemporaryInventory() async {
    if (_loading) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF21160F),
      showDragHandle: true,
      builder: (sheetContext) {
        if (_items.isEmpty) {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Your Bag is empty.',
                  style: TextStyle(color: Color(0xFFF1D3A2), fontSize: 16),
                ),
              ),
            ),
          );
        }

        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: _items.length,
            separatorBuilder: (_, _) => const Divider(color: Colors.white12),
            itemBuilder: (context, index) {
              final item = _items[index];

              final strokeCount = item.layers.fold<int>(
                0,
                (total, layer) => total + layer.strokes.length,
              );

              return ListTile(
                leading: const Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFFF1D3A2),
                ),
                title: Text(
                  item.name,
                  style: const TextStyle(color: Color(0xFFF4E5CF)),
                ),
                subtitle: Text(
                  '${item.layers.length} layers · $strokeCount strokes',
                  style: const TextStyle(color: Colors.white54),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Choose Pocket',
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
        );
      },
    );
  }

  Future<void> _openPocket(String pocketName) async {
    final pocketItems = _items
        .where((item) => _pocketAssignments[item.id] == pocketName)
        .toList();

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
                  pocketName.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFF1D3A2),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                if (pocketItems.isEmpty)
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
                      itemCount: pocketItems.length,
                      separatorBuilder: (_, _) =>
                          const Divider(color: Colors.white12),
                      itemBuilder: (context, index) {
                        final item = pocketItems[index];

                        return ListTile(
                          leading: const Icon(
                            Icons.inventory_2_outlined,
                            color: Color(0xFFF1D3A2),
                          ),
                          title: Text(
                            item.name,
                            style: const TextStyle(color: Color(0xFFF4E5CF)),
                          ),
                          subtitle: const Text(
                            'Tap to use in Workspace',
                            style: TextStyle(color: Colors.white54),
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
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The entire Bag environment lives in the artwork's native
          // 1536 x 1024 coordinate space. Artwork and hotspots therefore
          // scale together on every screen.
          Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
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

                    // SKETCHES
                    Positioned(
                      left: 435,
                      top: 385,
                      width: 145,
                      height: 70,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openPocket('Sketches'),
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
                        onTap: () => _openPocket('Characters'),
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
                        onTap: () => _openPocket('Textures'),
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
                        onTap: () => _openPocket('Props'),
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
                        onTap: () => _openPocket('Brushes'),
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
                        onTap: () => _openPocket('Misc.'),
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
              ),
            ),
          ),

          // Temporary escape hatch until items physically live in Pockets.
          Positioned(
            right: 18,
            top: 18,
            child: SafeArea(
              child: Material(
                color: const Color(0xCC21160F),
                borderRadius: BorderRadius.circular(14),
                elevation: 6,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _showTemporaryInventory,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.inventory_2_outlined,
                          size: 18,
                          color: Color(0xFFF1D3A2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _loading ? 'Loading...' : 'Items ${_items.length}',
                          style: const TextStyle(
                            color: Color(0xFFF1D3A2),
                            fontWeight: FontWeight.w600,
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
      ),
    );
  }
}
