import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/scene_motion_clock.dart';

void main() {
  test('seven FPS animation advances independently', () {
    const durations = <int>[1, 1, 1];

    expect(
      SceneMotionClock.frameIndex(
        elapsedMicroseconds: 0,
        fps: 7,
        frameDurations: durations,
      ),
      0,
    );

    expect(
      SceneMotionClock.frameIndex(
        elapsedMicroseconds: 150000,
        fps: 7,
        frameDurations: durations,
      ),
      1,
    );

    expect(
      SceneMotionClock.frameIndex(
        elapsedMicroseconds: 300000,
        fps: 7,
        frameDurations: durations,
      ),
      2,
    );

    expect(
      SceneMotionClock.frameIndex(
        elapsedMicroseconds: 450000,
        fps: 7,
        frameDurations: durations,
      ),
      0,
    );
  });

  test('held frames respect their durations', () {
    expect(
      SceneMotionClock.frameIndex(
        elapsedMicroseconds: 250000,
        fps: 10,
        frameDurations: const [3, 1],
      ),
      0,
    );

    expect(
      SceneMotionClock.frameIndex(
        elapsedMicroseconds: 350000,
        fps: 10,
        frameDurations: const [3, 1],
      ),
      1,
    );
  });

  test('non-looping animation stops on its final frame', () {
    expect(
      SceneMotionClock.frameIndex(
        elapsedMicroseconds: 5000000,
        fps: 7,
        frameDurations: const [1, 1, 1],
        loop: false,
      ),
      2,
    );
  });
}
