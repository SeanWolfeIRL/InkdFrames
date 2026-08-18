import 'dart:io';
import 'dart:ui' as ui;

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
  }) async {
    if (frames.isEmpty) {
      throw StateError('Cannot export an animation with no frames.');
    }

    if (frames.length != frameDurations.length) {
      throw StateError('Frame and duration counts do not match.');
    }

    final home = Platform.environment['HOME'] ?? Directory.current.path;
    final exportDirectory = Directory('$home/InkdFrames_exports');
    await exportDirectory.create(recursive: true);

    final tempDirectory = await Directory.systemTemp.createTemp(
      'inkdframes_export_',
    );

    try {
      var outputFrameIndex = 0;

      for (var frameIndex = 0; frameIndex < frames.length; frameIndex++) {
        final pngBytes = await _renderFrame(
          strokes: frames[frameIndex],
          width: canvasWidth.round(),
          height: canvasHeight.round(),
        );

        final repeats = frameDurations[frameIndex].clamp(1, 1000);

        for (var repeat = 0; repeat < repeats; repeat++) {
          final fileName =
              'frame_${outputFrameIndex.toString().padLeft(6, '0')}.png';

          await File(
            '${tempDirectory.path}/$fileName',
          ).writeAsBytes(pngBytes, flush: false);

          outputFrameIndex++;
        }
      }

      final safeName = _safeFileName(projectName);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${exportDirectory.path}/${safeName}_$timestamp.mp4';

      final result = await Process.run('ffmpeg', [
        '-y',
        '-framerate',
        fps.toString(),
        '-i',
        '${tempDirectory.path}/frame_%06d.png',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-vf',
        'scale=trunc(iw/2)*2:trunc(ih/2)*2',
        '-movflags',
        '+faststart',
        outputPath,
      ]);

      if (result.exitCode != 0) {
        throw StateError('FFmpeg export failed:\n${result.stderr}');
      }

      return outputPath;
    } finally {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  }

  Future<List<int>> _renderFrame({
    required List<VectorStroke> strokes,
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final backgroundPaint = ui.Paint()
      ..color = const ui.Color(0xFF1F1B24)
      ..style = ui.PaintingStyle.fill;

    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      backgroundPaint,
    );

    for (final stroke in strokes) {
      _paintStroke(canvas, stroke);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);

    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw StateError('Could not encode exported frame as PNG.');
      }

      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  void _paintStroke(ui.Canvas canvas, VectorStroke stroke) {
    final points = stroke.points;

    if (points.isEmpty) {
      return;
    }

    final paint = ui.Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..style = ui.PaintingStyle.stroke
      ..isAntiAlias = true;

    if (points.length == 1) {
      canvas.drawPoints(ui.PointMode.points, [
        ui.Offset(points.first.dx, points.first.dy),
      ], paint);
      return;
    }

    if (points.length == 2) {
      final path = ui.Path()
        ..moveTo(points[0].dx, points[0].dy)
        ..lineTo(points[1].dx, points[1].dy);

      canvas.drawPath(path, paint);
      return;
    }

    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);

    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i == 0 ? points[i] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;

      final control1 = ui.Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );

      final control2 = ui.Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );

      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        p2.dx,
        p2.dy,
      );
    }

    canvas.drawPath(path, paint);
  }

  String _safeFileName(String name) {
    final cleaned = name
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    return cleaned.isEmpty ? 'InkdFrames_Animation' : cleaned;
  }
}
