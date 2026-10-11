import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/bag_motion_asset.dart';
import 'package:inkdframes/app/models/scene_motion_instance.dart';

void main() {
  test('scene placement survives JSON round-trip', () {
    final instance = SceneMotionInstance(
      id: 'instance-1',
      rootGroupId: 'spider-root',
      bagItemId: 'spider',
      motion: const BagMotionAsset(
        fps: 7,
        frameIds: ['frame-1'],
        frameDurations: [1],
      ),
      placementX: 125,
      placementY: 80,
      placementScaleX: 0.25,
      placementScaleY: 0.25,
      placementRotation: 0.5,
      placementPivotX: 500,
      placementPivotY: 300,
    );

    final restored = SceneMotionInstance.fromJson(instance.toJson());

    expect(restored.placementX, 125);
    expect(restored.placementY, 80);
    expect(restored.placementScaleX, 0.25);
    expect(restored.placementScaleY, 0.25);
    expect(restored.placementRotation, 0.5);
    expect(restored.placementPivotX, 500);
    expect(restored.placementPivotY, 300);
    expect(restored.motion.frameIds, ['frame-1']);
  });

  test('placement updates preserve authored animation', () {
    final original = SceneMotionInstance(
      id: 'instance-1',
      rootGroupId: 'spider-root',
      bagItemId: 'spider',
      motion: const BagMotionAsset(
        fps: 7,
        frameIds: ['f1', 'f2'],
        frameDurations: [1, 1],
      ),
    );

    final placed = original.copyWith(
      placementX: 200,
      placementY: 100,
      placementScaleX: 0.2,
      placementScaleY: 0.2,
      placementRotation: 0.3,
    );

    expect(placed.placementX, 200);
    expect(placed.placementY, 100);
    expect(placed.placementScaleX, 0.2);
    expect(placed.placementScaleY, 0.2);
    expect(placed.placementRotation, 0.3);
    expect(placed.motion, same(original.motion));
    expect(placed.rootGroupId, original.rootGroupId);
    expect(original.placementScaleX, 1);
  });

  test('older scene instances default to identity placement', () {
    final restored = SceneMotionInstance.fromJson({
      'id': 'legacy',
      'rootGroupId': 'root',
      'bagItemId': 'bag',
      'motion': {
        'fps': 7,
        'frameIds': ['frame-1'],
        'frameDurations': [1],
      },
    });

    expect(restored.placementX, 0);
    expect(restored.placementY, 0);
    expect(restored.placementScaleX, 1);
    expect(restored.placementScaleY, 1);
    expect(restored.placementRotation, 0);
  });
}
