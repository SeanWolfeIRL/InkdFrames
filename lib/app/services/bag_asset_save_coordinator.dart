import 'package:flutter/foundation.dart';

import '../models/bag_item.dart';
import 'bag_service.dart';
import 'bag_thumbnail_cache.dart';
import 'bag_thumbnail_renderer.dart';

/// Coordinates Bag persistence and disposable preview generation.
class BagAssetSaveCoordinator {
  BagAssetSaveCoordinator({
    BagService? bagService,
    BagThumbnailCache? thumbnailCache,
    BagThumbnailRenderer? thumbnailRenderer,
  }) : _bagService = bagService ?? BagService(),
       _thumbnailCache = thumbnailCache ?? BagThumbnailCache(),
       _thumbnailRenderer = thumbnailRenderer ?? BagThumbnailRenderer();

  final BagService _bagService;
  final BagThumbnailCache _thumbnailCache;
  final BagThumbnailRenderer _thumbnailRenderer;

  Future<void> addItem(BagItem item) async {
    // Identify same-name assets that BagService will replace.
    // Never load their full artwork just to clean up previews.
    final references = await _bagService.loadItemReferences();
    final normalizedName = item.name.trim().toLowerCase();
    final replacedIds = references == null
        ? <String>[]
        : references
              .where(
                (reference) =>
                    reference.id != item.id &&
                    reference.name.trim().toLowerCase() == normalizedName,
              )
              .map((reference) => reference.id)
              .toList();

    // A preview must never be considered valid during asset replacement.
    try {
      await _thumbnailCache.invalidate(item.id);
    } catch (error) {
      debugPrint('BAG_THUMBNAIL: invalidation failed: $error');
    }

    // Asset persistence remains authoritative. Save failures propagate.
    await _bagService.addItem(item);

    // Remove previews belonging to assets replaced by this save.
    for (final oldId in replacedIds) {
      try {
        await _thumbnailCache.invalidate(oldId);
      } catch (error) {
        debugPrint('BAG_THUMBNAIL: replacement cleanup failed: $error');
      }
    }

    if (item.assetType != 'vector') return;

    try {
      await _thumbnailRenderer.generateVectorThumbnail(item);
    } catch (error) {
      debugPrint('BAG_THUMBNAIL: generation failed: $error');
    }
  }
}
