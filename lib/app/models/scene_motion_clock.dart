/// Resolves an independent animation's current source frame.
///
/// Elapsed time is measured in microseconds. Frame durations are expressed
/// in source-FPS ticks, so this clock is independent of the scene timeline.
class SceneMotionClock {
  const SceneMotionClock._();

  static int frameIndex({
    required int elapsedMicroseconds,
    required double fps,
    required List<int> frameDurations,
    bool loop = true,
  }) {
    if (frameDurations.isEmpty || fps <= 0) return 0;

    final totalTicks = frameDurations.fold<int>(
      0,
      (sum, duration) => sum + duration.clamp(1, 1000000),
    );

    if (totalTicks <= 0) return 0;

    final elapsedTicks =
        ((elapsedMicroseconds.clamp(0, 9223372036854775807) * fps) / 1000000)
            .floor();

    var tick = loop
        ? elapsedTicks % totalTicks
        : elapsedTicks.clamp(0, totalTicks - 1);

    for (var i = 0; i < frameDurations.length; i++) {
      final duration = frameDurations[i].clamp(1, 1000000);
      if (tick < duration) return i;
      tick -= duration;
    }

    return frameDurations.length - 1;
  }
}
