import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/bag_item.dart';
import '../models/vector_stroke.dart';
import '../painters/bag_item_preview_painter.dart';
import 'bag_thumbnail_cache.dart';

/// Renders lightweight PNG previews without modifying original Bag assets.
class BagThumbnailRenderer {
  BagThumbnailRenderer({BagThumbnailCache? cache})
    : _cache = cache ?? BagThumbnailCache();

  final BagThumbnailCache _cache;

  static const int thumbnailSize = 192;

  Future<bool> generateVectorThumbnail(BagItem item) async {
    if (item.assetType != 'vector') {
      return false;
    }

    final strokes = <VectorStroke>[];

    // Bag layers are top-to-bottom. Render bottom layers first.
    for (final layer in item.layers.reversed) {
      if (!layer.visible) continue;

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
            alphaLocked: stroke.alphaLocked,
          ),
        );
      }
    }

    if (strokes.every((stroke) => stroke.points.isEmpty)) {
      return false;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    BagItemPreviewPainter(
      strokes: strokes,
    ).paint(canvas, Size(thumbnailSize.toDouble(), thumbnailSize.toDouble()));

    final picture = recorder.endRecording();

    try {
      final image = await picture.toImage(thumbnailSize, thumbnailSize);

      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

        if (bytes == null) return false;

        await _cache.save(
          item.id,
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );

        return true;
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }
}
