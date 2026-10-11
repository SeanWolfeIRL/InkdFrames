import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/bag_item.dart';
import 'package:inkdframes/app/models/bag_motion_asset.dart';
import 'package:inkdframes/app/models/composite_asset.dart';
import 'package:inkdframes/app/models/group_animation_track.dart';
import 'package:inkdframes/app/models/transform_keyframe.dart';

void main() {
  test('animated Bag item survives JSON round-trip', () {
    final original = BagItem(
      id: 'spider_test',
      name: 'John D',
      sourceGroupName: 'John D',
      assetType: 'composite',
      layers: const <BagLayer>[],
      createdAt: DateTime.utc(2026, 10, 8),
      composite: const CompositeAsset(
        version: 1,
        canvasWidth: 1920,
        canvasHeight: 1080,
        root: CompositeNode(
          type: 'group',
          id: 'spider_root',
          name: 'John D',
          children: <CompositeNode>[
            CompositeNode(type: 'group', id: 'spider_eyes', name: 'Eyes'),
          ],
        ),
      ),
      motion: const BagMotionAsset(
        fps: 12,
        frameIds: <String>['frame_a', 'frame_b'],
        frameDurations: <int>[2, 3],
        transformKeyframes: <TransformKeyframe>[
          TransformKeyframe(
            id: 'key_1',
            frameId: 'frame_b',
            targetGroupId: 'spider_root',
            translateX: 24,
          ),
        ],
        groupAnimationTracks: <GroupAnimationTrack>[
          GroupAnimationTrack(
            targetGroupId: 'spider_eyes',
            clips: <GroupAnimationClip>[
              GroupAnimationClip(sourceFrameId: 'frame_a', duration: 2),
              GroupAnimationClip(sourceFrameId: 'frame_b', duration: 3),
            ],
          ),
        ],
      ),
    );

    final restored = BagItem.fromJson(original.toJson());

    expect(restored.isComposite, isTrue);
    expect(restored.motion, isNotNull);
    expect(restored.motion!.fps, 12);
    expect(restored.motion!.frameIds, ['frame_a', 'frame_b']);
    expect(restored.motion!.frameDurations, [2, 3]);

    final keyframe = restored.motion!.transformKeyframes.single;
    expect(keyframe.frameId, 'frame_b');
    expect(keyframe.targetGroupId, 'spider_root');
    expect(keyframe.translateX, 24);

    final track = restored.motion!.groupAnimationTracks.single;
    expect(track.targetGroupId, 'spider_eyes');
    expect(track.clips.length, 2);
    expect(track.clips.last.sourceFrameId, 'frame_b');
    expect(track.clips.last.duration, 3);

    expect(restored.toJson(), original.toJson());
  });

  test('legacy single animation appears as idle clip', () {
    final legacy = BagMotionAsset.fromJson({
      'version': 1,
      'fps': 7,
      'frameIds': ['a', 'b'],
      'frameDurations': [2, 4],
      'transformKeyframes': [],
      'groupAnimationTracks': [],
    });

    expect(legacy.availableClips.length, 1);
    expect(legacy.availableClips.single.name, 'idle');
    expect(legacy.availableClips.single.fps, 7);
    expect(legacy.availableClips.single.frameDurations, [2, 4]);
    expect(legacy.toJson().containsKey('clips'), isFalse);
  });

  test('multiple named clips survive JSON round-trip', () {
    const motion = BagMotionAsset(
      fps: 7,
      frameIds: ['a', 'b'],
      frameDurations: [1, 2],
      clips: [
        BagMotionClip(
          name: 'idle',
          fps: 7,
          frameIds: ['a', 'b'],
          frameDurations: [1, 2],
        ),
        BagMotionClip(
          name: 'walking',
          fps: 12,
          frameIds: ['b', 'a'],
          frameDurations: [3, 4],
          transformKeyframes: [
            TransformKeyframe(
              id: 'walk_key',
              frameId: 'b',
              targetGroupId: 'spider_root',
              translateX: 15,
            ),
          ],
        ),
      ],
    );

    final restored = BagMotionAsset.fromJson(motion.toJson());

    expect(restored.version, 2);
    expect(restored.availableClips.map((clip) => clip.name), [
      'idle',
      'walking',
    ]);
    expect(restored.availableClips.last.fps, 12);
    expect(restored.availableClips.last.frameDurations, [3, 4]);
    expect(
      restored.availableClips.last.transformKeyframes.single.translateX,
      15,
    );
    expect(restored.toJson(), motion.toJson());
  });

  test('legacy Bag item without motion remains compatible', () {
    final original = BagItem(
      id: 'legacy_test',
      name: 'Static Asset',
      sourceGroupName: 'Static Asset',
      layers: const <BagLayer>[],
      createdAt: DateTime.utc(2026, 10, 8),
    );

    final restored = BagItem.fromJson(original.toJson());

    expect(restored.motion, isNull);
    expect(restored.toJson(), original.toJson());
  });
}
