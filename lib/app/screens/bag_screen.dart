import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
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

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.name} removed from your Bag')),
    );

    await _loadItems();
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
                trailing: IconButton(
                  tooltip: 'Delete from Bag',
                  icon: const Icon(Icons.delete_outline, color: Colors.white54),
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await _deleteItem(item);
                  },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/inkdframes_bag_open_v1.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),

              // Painted BACK sign in the lower-right corner.
              Positioned(
                left: width * 0.765,
                top: height * 0.905,
                width: width * 0.145,
                height: height * 0.075,
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

              // Temporary inventory access while the physical Pocket
              // interactions are being built.
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
                              _loading
                                  ? 'Loading...'
                                  : 'Items ${_items.length}',
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
          );
        },
      ),
    );
  }
}
