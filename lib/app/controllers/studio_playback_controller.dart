import 'dart:async';

/// Owns Studio's one-shot playback timer and elapsed-time baseline.
///
/// Frame advancement, scene rendering, and video synchronisation remain
/// responsibilities of the Workspace.
class StudioPlaybackController {
  StudioPlaybackController({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  Timer? _timer;
  DateTime? _lastTick;
  bool _disposed = false;

  /// Schedules one tick, replacing any previously scheduled tick.
  ///
  /// Rescheduling preserves the elapsed-time baseline.
  void schedule({
    required double fps,
    required void Function(int elapsedMicroseconds) onTick,
  }) {
    if (_disposed) return;

    _timer?.cancel();

    final frameMilliseconds = (1000 / fps).round().clamp(40, 1000);
    _lastTick ??= _now();

    _timer = Timer(Duration(milliseconds: frameMilliseconds), () {
      if (_disposed) return;

      final now = _now();
      final lastTick = _lastTick;
      final elapsedMicroseconds = lastTick == null
          ? frameMilliseconds * 1000
          : now.difference(lastTick).inMicroseconds.clamp(0, 1000000);

      _lastTick = now;
      _timer = null;
      onTick(elapsedMicroseconds);
    });
  }

  /// Stops pending playback without resetting elapsed-time accounting.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Stops playback and resets the elapsed-time baseline.
  void pause() {
    cancel();
    _lastTick = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    pause();
  }
}
