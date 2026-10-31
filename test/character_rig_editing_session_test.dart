import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/character_rig_editing_session.dart';
import 'package:inkdframes/app/models/inkdframes_project.dart';
import 'package:inkdframes/app/models/rig_deformer.dart';
import 'package:inkdframes/app/models/stroke_rig.dart';

void main() {
  test('unfinished deformation survives project JSON round-trip', () {
    final session = CharacterRigEditingSession(
      characterRigId: 'jd-mini',
      frameId: 'frame-2',
      strokeRigs: [
        StrokeRig(
          id: 'leg-rig',
          strokeId: 'leg-stroke',
          controls: [
            RigControlPoint(
              id: 'leg-tip',
              restX: 20,
              restY: 30,
              x: 45,
              y: 55,
              radius: 12,
              locked: false,
            ),
          ],
        ),
      ],
    );

    final project = InkdFramesProject(
      id: 'test-project',
      name: 'JD Mini',
      fps: 12,
      frames: const [],
      frameDurations: [1, 1],
      frameIds: ['frame-1', 'frame-2'],
      activeRigSession: session,
    );

    final restored = InkdFramesProject.fromJson(project.toJson());
    final active = restored.activeRigSession;

    expect(active, isNotNull);
    expect(active!.characterRigId, 'jd-mini');
    expect(active.frameId, 'frame-2');
    expect(active.strokeRigs.single.strokeId, 'leg-stroke');
    expect(active.strokeRigs.single.controls.single.restX, 20);
    expect(active.strokeRigs.single.controls.single.x, 45);
    expect(active.strokeRigs.single.controls.single.y, 55);
  });

  test('projects without editing sessions remain compatible', () {
    final project = InkdFramesProject(
      id: 'legacy',
      name: 'Legacy',
      fps: 12,
      frames: const [],
      frameDurations: [1],
    );

    final json = project.toJson();
    expect(json.containsKey('activeRigSession'), isFalse);

    final restored = InkdFramesProject.fromJson(json);
    expect(restored.activeRigSession, isNull);
  });
  test('malformed stroke list does not block project loading', () {
    final project = InkdFramesProject(
      id: 'recovery-test',
      name: 'JD Mini Recovery',
      fps: 12,
      frames: const [],
      frameDurations: [1],
    );

    final json = project.toJson();
    json['activeRigSession'] = {
      'characterRigId': 'jd-mini',
      'frameId': 'frame-1',
      'strokeRigs': 'invalid-data',
    };

    final restored = InkdFramesProject.fromJson(json);

    expect(restored.id, 'recovery-test');
    expect(restored.name, 'JD Mini Recovery');
    expect(restored.activeRigSession, isNull);
  });

  test('invalid control coordinate does not block project loading', () {
    final project = InkdFramesProject(
      id: 'coordinate-test',
      name: 'Coordinate Recovery',
      fps: 12,
      frames: const [],
      frameDurations: [1],
    );

    final json = project.toJson();
    json['activeRigSession'] = {
      'characterRigId': 'jd-mini',
      'frameId': 'frame-1',
      'strokeRigs': [
        {
          'id': 'leg-rig',
          'strokeId': 'leg-stroke',
          'controls': [
            {
              'id': 'leg-tip',
              'restX': 20,
              'restY': 30,
              'x': 'corrupted',
              'y': 55,
              'radius': 12,
              'locked': false,
            },
          ],
        },
      ],
    };

    final restored = InkdFramesProject.fromJson(json);

    expect(restored.id, 'coordinate-test');
    expect(restored.activeRigSession, isNull);
  });

  test('non-map editing session does not block project loading', () {
    final project = InkdFramesProject(
      id: 'type-test',
      name: 'Type Recovery',
      fps: 12,
      frames: const [],
      frameDurations: [1],
    );

    final json = project.toJson();
    json['activeRigSession'] = ['invalid-session'];

    final restored = InkdFramesProject.fromJson(json);

    expect(restored.id, 'type-test');
    expect(restored.activeRigSession, isNull);
  });
}
