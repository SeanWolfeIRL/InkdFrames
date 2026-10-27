import 'dart:convert';
import 'dart:io';

import '../models/bag_item.dart';
import '../models/bag_item_reference.dart';
import 'inkdframes_storage.dart';

class BagService {
  File get _indexFile =>
      File('${InkdFramesStorage.rootDirectory.path}/bag_index_v1.json');

  Future<List<BagItemReference>?> loadItemReferences() async {
    await InkdFramesStorage.ensureDirectories();

    if (!await _indexFile.exists()) return null;

    try {
      final decoded = jsonDecode(await _indexFile.readAsString());
      if (decoded is! List) return null;

      final references = decoded
          .whereType<Map>()
          .map(
            (entry) =>
                BagItemReference.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList();

      references.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return references;
    } catch (_) {
      return null;
    }
  }

  Future<void> rebuildItemReferenceIndex() async {
    await InkdFramesStorage.ensureDirectories();

    final references = <BagItemReference>[];
    var fileCount = 0;
    final seenIds = <String>{};

    await for (final entity in InkdFramesStorage.bagItemsDirectory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }

      fileCount++;

      final decoded = jsonDecode(await entity.readAsString());

      if (decoded is! Map) {
        throw FormatException('Invalid Bag asset: ${entity.path}');
      }

      final reference = BagItemReference.fromJson(
        Map<String, dynamic>.from(decoded),
      );

      if (reference.id.isEmpty) {
        throw FormatException('Bag asset missing ID: ${entity.path}');
      }

      if (!seenIds.add(reference.id)) {
        throw FormatException('Duplicate Bag asset ID: ${reference.id}');
      }

      references.add(reference);
    }

    if (references.length != fileCount) {
      throw StateError('Bag index validation failed.');
    }

    references.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final tempFile = File('${_indexFile.path}.tmp');

    await tempFile.writeAsString(
      jsonEncode(references.map((item) => item.toJson()).toList()),
      flush: true,
    );

    await tempFile.rename(_indexFile.path);
  }

  Future<BagItem?> loadItemById(String itemId) async {
    final file = await _fileFor(itemId);
    if (!await file.exists()) return null;

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return null;

    return BagItem.fromJson(Map<String, dynamic>.from(decoded));
  }

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

    // Invalidate before any asset changes, including partial failures.
    await _invalidateReferenceIndex();

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

  Future<void> _invalidateReferenceIndex() async {
    if (await _indexFile.exists()) {
      await _indexFile.delete();
    }
  }

  Future<List<BagItemReference>> _referencesForUpdate() async {
    final existing = await loadItemReferences();
    if (existing != null) return existing;

    await rebuildItemReferenceIndex();
    final rebuilt = await loadItemReferences();
    if (rebuilt == null) {
      throw StateError('Unable to build Bag reference index.');
    }
    return rebuilt;
  }

  Future<void> _writeReferences(List<BagItemReference> references) async {
    final temp = File('${_indexFile.path}.tmp');
    final data = references.map((r) => r.toJson()).toList();

    await temp.writeAsString(jsonEncode(data), flush: true);
    await temp.rename(_indexFile.path);
  }

  BagItemReference _referenceFor(BagItem item) {
    return BagItemReference(
      id: item.id,
      name: item.name,
      assetType: item.assetType,
      createdAt: item.createdAt,
      imagePath: item.imagePath,
    );
  }

  Future<void> addItem(BagItem item) async {
    try {
      final references = await _referencesForUpdate();
      final normalizedName = item.name.trim().toLowerCase();

      final replaced = references
          .where(
            (r) =>
                r.id != item.id &&
                r.name.trim().toLowerCase() == normalizedName,
          )
          .toList();

      // Persist the replacement before removing older same-name assets.
      await _writeItem(item);

      for (final old in replaced) {
        final oldFile = await _fileFor(old.id);
        if (await oldFile.exists()) {
          await oldFile.delete();
        }
      }

      references.removeWhere(
        (r) => r.id == item.id || r.name.trim().toLowerCase() == normalizedName,
      );

      references.add(_referenceFor(item));
      references.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      try {
        await _writeReferences(references);
      } catch (_) {
        // Asset files remain authoritative. Invalidate the index.
        if (await _indexFile.exists()) {
          await _indexFile.delete();
        }
        rethrow;
      }
    } catch (_) {
      await _invalidateReferenceIndex();
      rethrow;
    }
  }

  Future<void> deleteItem(String itemId) async {
    try {
      final file = await _fileFor(itemId);

      if (await file.exists()) {
        await file.delete();
      }

      final tempFile = File('${file.path}.tmp');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      final references = await loadItemReferences();
      if (references == null) return;

      references.removeWhere((r) => r.id == itemId);

      try {
        await _writeReferences(references);
      } catch (_) {
        if (await _indexFile.exists()) {
          await _indexFile.delete();
        }
        rethrow;
      }
    } catch (_) {
      await _invalidateReferenceIndex();
      rethrow;
    }
  }
}
