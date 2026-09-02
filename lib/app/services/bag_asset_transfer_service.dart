import 'dart:convert';
import 'dart:io';

import 'package:media_store_plus/media_store_plus.dart';

import '../models/bag_item.dart';

class BagAssetTransferService {
  const BagAssetTransferService();

  static const String formatName = 'inkdframes_asset';
  static const int formatVersion = 1;

  Future<String> exportAsset(BagItem item) async {
    final payload = <String, dynamic>{
      'format': formatName,
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'asset': item.toJson(),
    };

    final safeName = _safeFileName(item.name);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final tempDirectory = Directory(
      '${Directory.systemTemp.path}/inkdframes_asset_exports',
    );

    await tempDirectory.create(recursive: true);

    final tempFile = File(
      '${tempDirectory.path}/${safeName}_$timestamp.inkdasset',
    );

    await tempFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );

    if (Platform.isAndroid) {
      await MediaStore.ensureInitialized();
      MediaStore.appFolder = 'InkdFrames';

      final saveInfo = await MediaStore().saveFile(
        tempFilePath: tempFile.path,
        dirType: DirType.download,
        dirName: DirName.download,
      );

      if (saveInfo == null) {
        throw StateError(
          'Asset was created but could not be saved to Downloads/InkdFrames.',
        );
      }

      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      return 'Downloads/InkdFrames';
    }

    final exportDirectory = Directory(
      '${Directory.current.path}/exports/InkdFrames',
    );

    await exportDirectory.create(recursive: true);

    final outputFile = File(
      '${exportDirectory.path}/${safeName}_$timestamp.inkdasset',
    );

    await tempFile.copy(outputFile.path);

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    return outputFile.path;
  }

  Future<BagItem> importAsset(String path) async {
    final file = File(path);

    if (!await file.exists()) {
      throw StateError('The selected asset file could not be found.');
    }

    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);

    if (decoded is! Map) {
      throw const FormatException('Invalid InkdFrames asset file.');
    }

    final root = Map<String, dynamic>.from(decoded);

    if (root['format'] != formatName) {
      throw const FormatException('This file is not an InkdFrames asset.');
    }

    final version = (root['version'] as num?)?.toInt();

    if (version != formatVersion) {
      throw FormatException(
        'Unsupported InkdFrames asset version: ${version ?? 'unknown'}.',
      );
    }

    final rawAsset = root['asset'];

    if (rawAsset is! Map) {
      throw const FormatException(
        'The InkdFrames asset contains no usable object data.',
      );
    }

    return BagItem.fromJson(Map<String, dynamic>.from(rawAsset));
  }

  String _safeFileName(String value) {
    final trimmed = value.trim();

    final normalized = trimmed
        .replaceAll(RegExp(r'[^\w\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    return normalized.isEmpty ? 'InkdFrames_Asset' : normalized;
  }
}
