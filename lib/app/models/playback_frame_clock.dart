class PlaybackFramePosition {
  const PlaybackFramePosition({
    required this.frameIndex,
    required this.frameUnit,
  });

  final int frameIndex;
  final int frameUnit;
}

/// Advances the main timeline by one base-FPS unit.
///
/// Independent Scene Motion uses a separate elapsed-time clock.
class PlaybackFrameClock {
  const PlaybackFrameClock._();

  static PlaybackFramePosition advance({
    required int frameIndex,
    required int frameUnit,
    required List<int> frameDurations,
  }) {
    if (frameDurations.isEmpty) {
      return const PlaybackFramePosition(frameIndex: 0, frameUnit: 0);
    }

    final duration = frameDurations[frameIndex].clamp(1, 1000000);

    if (frameUnit + 1 < duration) {
      return PlaybackFramePosition(
        frameIndex: frameIndex,
        frameUnit: frameUnit + 1,
      );
    }

    return PlaybackFramePosition(
      frameIndex: frameIndex < frameDurations.length - 1 ? frameIndex + 1 : 0,
      frameUnit: 0,
    );
  }
}
