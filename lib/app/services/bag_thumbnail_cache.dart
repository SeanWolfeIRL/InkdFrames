import 'dart:io';
import 'dart:typed_data';

import 'inkdframes_storage.dart';

/// Disposable PNG cache. Original Bag assets remain authoritative.
class BagThumbnailCache {
  Future<File> fileFor(String itemId) async {
    await InkdFramesStorage.ensureDirectories();
    final safeId = InkdFramesStorage.safeFileName(itemId);
    return File('${InkdFramesStorage.bagThumbnailsDirectory.path}/$safeId.png');
  }

  Future<File?> existingFile(String itemId) async {
    final file = await fileFor(itemId);
    return await file.exists() ? file : null;
  }

  Future<void> save(String itemId, Uint8List pngBytes) async {
    final file = await fileFor(itemId);
    final temp = File('${file.path}.tmp');

    await temp.writeAsBytes(pngBytes, flush: true);

    try {
      await temp.rename(file.path);
    } on FileSystemException {
      // Some filesystems require removing the destination first.
      if (await file.exists()) {
        await file.delete();
      }
      await temp.rename(file.path);
    }
  }

  Future<void> invalidate(String itemId) async {
    final file = await fileFor(itemId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
