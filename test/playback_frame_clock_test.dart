import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/playback_frame_clock.dart';

void main() {
  test('held frames advance one unit at a time', () {
    final first = PlaybackFrameClock.advance(
      frameIndex: 0,
      frameUnit: 0,
      frameDurations: [3, 1],
    );
    expect(first.frameIndex, 0);
    expect(first.frameUnit, 1);

    final second = PlaybackFrameClock.advance(
      frameIndex: 0,
      frameUnit: first.frameUnit,
      frameDurations: [3, 1],
    );
    expect(second.frameIndex, 0);
    expect(second.frameUnit, 2);
  });

  test('advances to next frame after hold', () {
    final next = PlaybackFrameClock.advance(
      frameIndex: 0,
      frameUnit: 2,
      frameDurations: [3, 1],
    );
    expect(next.frameIndex, 1);
    expect(next.frameUnit, 0);
  });

  test('loops back to first frame', () {
    final next = PlaybackFrameClock.advance(
      frameIndex: 1,
      frameUnit: 0,
      frameDurations: [3, 1],
    );
    expect(next.frameIndex, 0);
    expect(next.frameUnit, 0);
  });

  test('zero duration is treated as one unit', () {
    final next = PlaybackFrameClock.advance(
      frameIndex: 0,
      frameUnit: 0,
      frameDurations: [0, 2],
    );
    expect(next.frameIndex, 1);
    expect(next.frameUnit, 0);
  });

  test('single-frame timeline loops to its own first unit', () {
    final next = PlaybackFrameClock.advance(
      frameIndex: 0,
      frameUnit: 0,
      frameDurations: [1],
    );

    expect(next.frameIndex, 0);
    expect(next.frameUnit, 0);
  });

  test('empty timeline returns initial position', () {
    final next = PlaybackFrameClock.advance(
      frameIndex: 0,
      frameUnit: 0,
      frameDurations: [],
    );
    expect(next.frameIndex, 0);
    expect(next.frameUnit, 0);
  });
}
