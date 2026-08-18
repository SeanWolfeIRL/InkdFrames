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
  }) {
    throw UnsupportedError('MP4 export is not available in the web preview.');
  }
}
