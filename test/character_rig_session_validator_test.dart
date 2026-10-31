import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/models/character_rig.dart';
import 'package:inkdframes/app/models/character_rig_editing_session.dart';
import 'package:inkdframes/app/models/character_rig_session_validator.dart';
import 'package:inkdframes/app/models/drawing_layer.dart';
import 'package:inkdframes/app/models/rig_deformer.dart';
import 'package:inkdframes/app/models/stroke_rig.dart';
import 'package:inkdframes/app/models/vector_stroke.dart';

StrokeRig makeRig({double x = 45, String strokeId = 'leg-stroke'}) {
  return StrokeRig(
    id: 'leg-rig',
    strokeId: strokeId,
    controls: [
      RigControlPoint(
        id: 'leg-tip',
        restX: 20,
        restY: 30,
        x: x,
        y: 55,
        radius: 12,
        locked: false,
      ),
    ],
  );
}

CharacterRig makeCharacter({
  String id = 'jd-mini',
  String targetId = 'leg-stroke',
}) {
  return CharacterRig(
    id: id,
    targets: [
      CharacterRigTarget(
        id: 'leg-target',
        type: RigTargetType.stroke,
        targetId: targetId,
        rig: makeRig(x: 20),
      ),
    ],
  );
}

CharacterRigEditingSession makeSession({
  String characterId = 'jd-mini',
  String frameId = 'frame-2',
  List<StrokeRig>? rigs,
}) {
  return CharacterRigEditingSession(
    characterRigId: characterId,
    frameId: frameId,
    strokeRigs: rigs ?? [makeRig()],
  );
}

DrawingLayer makeLayer({
  bool visible = true,
  bool filled = false,
  bool alphaLocked = false,
  bool includeStroke = true,
}) {
  return DrawingLayer(
    id: 'leg-layer',
    name: 'Leg',
    visible: visible,
    frames: [
      [],
      [
        if (includeStroke)
          VectorStroke(
            id: 'leg-stroke',
            points: [],
            filled: filled,
            alphaLocked: alphaLocked,
          ),
      ],
    ],
  );
}

void main() {
  final frames = ['frame-1', 'frame-2'];

  Map<String, StrokeRig>? validate({
    CharacterRigEditingSession? session,
    CharacterRig? character,
    List<String>? frameIds,
    List<DrawingLayer>? layers,
  }) {
    return validateCharacterRigSession(
      session ?? makeSession(),
      character ?? makeCharacter(),
      frameIds ?? frames,
      layers ?? [makeLayer()],
    );
  }

  test('valid unfinished deformation restores', () {
    final result = validate();
    expect(result, isNotNull);
    expect(result!['leg-stroke']!.controls.single.x, 45);
  });

  test('missing artwork stroke rejects session', () {
    expect(validate(layers: [makeLayer(includeStroke: false)]), isNull);
  });

  test('hidden artwork layer rejects session', () {
    expect(validate(layers: [makeLayer(visible: false)]), isNull);
  });

  test('filled stroke rejects session', () {
    expect(validate(layers: [makeLayer(filled: true)]), isNull);
  });

  test('alpha-locked stroke rejects session', () {
    expect(validate(layers: [makeLayer(alphaLocked: true)]), isNull);
  });

  test('incorrect character ID rejects session', () {
    expect(validate(session: makeSession(characterId: 'other')), isNull);
  });

  test('missing frame rejects session', () {
    expect(validate(session: makeSession(frameId: 'missing')), isNull);
  });

  test('duplicate frame IDs reject session', () {
    expect(validate(frameIds: ['frame-2', 'frame-2']), isNull);
  });

  test('modified rest control rejects session', () {
    final altered = StrokeRig(
      id: 'leg-rig',
      strokeId: 'leg-stroke',
      controls: [
        RigControlPoint(
          id: 'leg-tip',
          restX: 999,
          restY: 30,
          x: 45,
          y: 55,
          radius: 12,
          locked: false,
        ),
      ],
    );

    expect(validate(session: makeSession(rigs: [altered])), isNull);
  });

  test('duplicate saved stroke rejects session', () {
    expect(
      validate(session: makeSession(rigs: [makeRig(), makeRig()])),
      isNull,
    );
  });

  test('inconsistent registered target rejects session', () {
    expect(validate(character: makeCharacter(targetId: 'wrong')), isNull);
  });
}
