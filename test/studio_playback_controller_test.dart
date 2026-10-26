import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/controllers/studio_playback_controller.dart';

void main() {
  test('scheduled tick fires after one frame interval', () {
    fakeAsync((async) {
      final controller = StudioPlaybackController(
        now: () => async.getClock(DateTime(2026)).now(),
      );

      int? elapsed;
      controller.schedule(fps: 25, onTick: (value) => elapsed = value);

      async.elapse(const Duration(milliseconds: 39));
      expect(elapsed, isNull);

      async.elapse(const Duration(milliseconds: 1));
      expect(elapsed, 40000);

      controller.dispose();
    });
  });

  test('cancel prevents a pending tick', () {
    fakeAsync((async) {
      final controller = StudioPlaybackController();
      var ticks = 0;

      controller.schedule(fps: 25, onTick: (_) => ticks++);
      controller.cancel();

      async.elapse(const Duration(seconds: 1));
      expect(ticks, 0);
      controller.dispose();
    });
  });

  test('rescheduling replaces the pending callback', () {
    fakeAsync((async) {
      final controller = StudioPlaybackController();
      var first = 0;
      var second = 0;

      controller.schedule(fps: 25, onTick: (_) => first++);
      controller.schedule(fps: 25, onTick: (_) => second++);

      async.elapse(const Duration(milliseconds: 40));

      expect(first, 0);
      expect(second, 1);
      controller.dispose();
    });
  });

  test('FPS change reschedules using the latest interval', () {
    fakeAsync((async) {
      final controller = StudioPlaybackController();
      var ticks = 0;

      controller.schedule(fps: 10, onTick: (_) => ticks++);
      async.elapse(const Duration(milliseconds: 30));

      controller.schedule(fps: 25, onTick: (_) => ticks++);

      async.elapse(const Duration(milliseconds: 39));
      expect(ticks, 0);

      async.elapse(const Duration(milliseconds: 1));
      expect(ticks, 1);
      controller.dispose();
    });
  });

  test('rescheduling preserves elapsed-time continuity', () {
    fakeAsync((async) {
      final controller = StudioPlaybackController(
        now: () => async.getClock(DateTime(2026)).now(),
      );
      int? elapsed;

      controller.schedule(fps: 10, onTick: (value) => elapsed = value);
      async.elapse(const Duration(milliseconds: 30));

      controller.schedule(fps: 25, onTick: (value) => elapsed = value);
      async.elapse(const Duration(milliseconds: 40));

      expect(elapsed, 70000);
      controller.dispose();
    });
  });

  test('pause resets elapsed-time baseline', () {
    fakeAsync((async) {
      final controller = StudioPlaybackController(
        now: () => async.getClock(DateTime(2026)).now(),
      );
      int? elapsed;

      controller.schedule(fps: 25, onTick: (_) {});
      async.elapse(const Duration(milliseconds: 20));
      controller.pause();

      async.elapse(const Duration(seconds: 2));

      controller.schedule(fps: 25, onTick: (value) => elapsed = value);
      async.elapse(const Duration(milliseconds: 40));

      expect(elapsed, 40000);
      controller.dispose();
    });
  });

  test('dispose prevents callbacks and future scheduling', () {
    fakeAsync((async) {
      final controller = StudioPlaybackController();
      var ticks = 0;

      controller.schedule(fps: 25, onTick: (_) => ticks++);
      controller.dispose();
      controller.schedule(fps: 25, onTick: (_) => ticks++);

      async.elapse(const Duration(seconds: 1));
      expect(ticks, 0);
    });
  });
}
