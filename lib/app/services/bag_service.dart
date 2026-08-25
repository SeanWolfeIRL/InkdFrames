import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bag_item.dart';

class BagService {
  static const String _storageKey = 'inkdframes_bag_items';

  Future<List<BagItem>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final rawItems = prefs.getStringList(_storageKey) ?? const <String>[];

    final items = <BagItem>[];

    for (final rawItem in rawItems) {
      try {
        final decoded = jsonDecode(rawItem);

        if (decoded is Map) {
          items.add(BagItem.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {
        // Ignore malformed Bag entries instead of breaking the whole Bag.
      }
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return items;
  }

  Future<void> saveItems(List<BagItem> items) async {
    final prefs = await SharedPreferences.getInstance();

    final encoded = items.map((item) => jsonEncode(item.toJson())).toList();

    await prefs.setStringList(_storageKey, encoded);
  }

  Future<void> addItem(BagItem item) async {
    final items = await loadItems();

    final normalizedName = item.name.trim().toLowerCase();

    items.removeWhere(
      (existing) =>
          existing.id == item.id ||
          existing.name.trim().toLowerCase() == normalizedName,
    );

    items.insert(0, item);

    await saveItems(items);
  }

  Future<void> deleteItem(String itemId) async {
    final items = await loadItems();

    items.removeWhere((item) => item.id == itemId);

    await saveItems(items);
  }
}
