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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close Bag',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.backpack_outlined),
            SizedBox(width: 10),
            Text('Bag'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
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
                  Text(
                    'Your Bag is empty.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Add a layer group to start your inventory.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _items[index];

                final strokeCount = item.layers.fold<int>(
                  0,
                  (total, layer) => total + layer.strokes.length,
                );

                return ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.layers.length} layers · '
                    '$strokeCount strokes',
                  ),
                  trailing: IconButton(
                    tooltip: 'Delete from Bag',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteItem(item),
                  ),
                  onTap: () => Navigator.pop(context, item),
                );
              },
            ),
    );
  }
}
