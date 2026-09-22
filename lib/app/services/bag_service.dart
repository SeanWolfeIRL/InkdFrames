import 'dart:convert';
import 'dart:io';

import '../models/bag_item.dart';
import 'inkdframes_storage.dart';

class BagService {
  Future<File> _fileFor(String itemId) async {
    await InkdFramesStorage.ensureDirectories();

    final safeId = InkdFramesStorage.safeFileName(itemId);

    return File('${InkdFramesStorage.bagItemsDirectory.path}/$safeId.json');
  }

  Future<List<BagItem>> loadItems() async {
    await InkdFramesStorage.ensureDirectories();

    final items = <BagItem>[];

    await for (final entity in InkdFramesStorage.bagItemsDirectory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }

      try {
        final raw = await entity.readAsString();
        final decoded = jsonDecode(raw);

        if (decoded is Map) {
          items.add(BagItem.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {
        // One malformed asset must not prevent the Bag from opening.
      }
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return items;
  }

  Future<void> saveItems(List<BagItem> items) async {
    await InkdFramesStorage.ensureDirectories();

    final desiredIds = items.map((item) => item.id).toSet();

    // Write/replace every requested asset first.
    for (final item in items) {
      await _writeItem(item);
    }

    // Only after all writes succeed do we remove stale Bag files.
    await for (final entity in InkdFramesStorage.bagItemsDirectory.list()) {
      if (entity is! File ||
          !entity.path.endsWith('.json') ||
          entity.path.endsWith('.json.tmp')) {
        continue;
      }

      final filename = entity.uri.pathSegments.last;
      final safeId = filename.substring(0, filename.length - '.json'.length);

      final shouldKeep = desiredIds.any(
        (id) => InkdFramesStorage.safeFileName(id) == safeId,
      );

      if (!shouldKeep) {
        await entity.delete();
      }
    }
  }

  Future<void> _writeItem(BagItem item) async {
    final file = await _fileFor(item.id);
    final tempFile = File('${file.path}.tmp');

    final encoded = jsonEncode(item.toJson());

    await tempFile.writeAsString(encoded, flush: true);

    // Read and parse it before replacing an existing asset.
    final verification = await tempFile.readAsString();
    final decoded = jsonDecode(verification);

    if (decoded is! Map) {
      await tempFile.delete();
      throw const FormatException('Bag item JSON root was not an object.');
    }

    if (await file.exists()) {
      await file.delete();
    }

    await tempFile.rename(file.path);
  }

  Future<void> addItem(BagItem item) async {
    // Preserve the existing rule that a same-name asset replaces the old one.
    final items = await loadItems();
    final normalizedName = item.name.trim().toLowerCase();

    for (final existing in items) {
      if (existing.id == item.id ||
          existing.name.trim().toLowerCase() == normalizedName) {
        if (existing.id != item.id) {
          await deleteItem(existing.id);
        }
      }
    }

    await _writeItem(item);
  }

  Future<void> deleteItem(String itemId) async {
    final file = await _fileFor(itemId);

    if (await file.exists()) {
      await file.delete();
    }

    final tempFile = File('${file.path}.tmp');

    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  }
}
