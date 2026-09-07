import 'dart:ui' as ui;
import 'dart:typed_data';

import '../models/vector_stroke.dart';

class AnimationExportService {
  const AnimationExportService();

  Future<String> exportMp4({
    required String projectName,
    required List<List<VectorStroke>> frames,
    required List<int> frameDurations,
    required double fps,
    required double canvasWidth,
    required double canvasHeight,
    required ui.Color backgroundColor,
  }) {
    throw UnsupportedError('MP4 export is not available in the web preview.');
  }

  Future<String> exportRawRgbaPngAsset({
    required String assetName,
    required int width,
    required int height,
    required Uint8List rgbaBytes,
  }) {
    throw UnsupportedError(
      'RGBA PNG export is not available in the web preview.',
    );
  }

  Future<String> exportRenderedPngAsset({
    required String assetName,
    required List<int> pngBytes,
  }) {
    throw UnsupportedError(
      'Rendered PNG export is not available in the web preview.',
    );
  }

  Future<String> exportPngAsset({
    required String assetName,
    required List<VectorStroke> strokes,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    throw UnsupportedError(
      'PNG asset export is not available in the web preview.',
    );
  }
}
