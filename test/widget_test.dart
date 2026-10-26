import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/inkdframes_app.dart';
import 'package:inkdframes/app/screens/workspace_screen.dart';
import 'package:inkdframes/app/painters/animation_canvas_painter.dart';

Future<void> openWorkspace(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: WorkspaceScreen(projectName: 'Test Animation')),
  );
  await tester.pumpAndSettle();
}

Future<void> ensureTimelineOpen(WidgetTester tester) async {
  final showTimeline = find.byTooltip('Show Timeline');

  if (showTimeline.evaluate().isNotEmpty) {
    await tester.tap(showTimeline);
    await tester.pumpAndSettle();
  }
}

Future<void> ensureFrameToolsOpen(WidgetTester tester) async {
  final showFrameTools = find.byTooltip('Show Frame Tools');

  if (showFrameTools.evaluate().isNotEmpty) {
    await tester.tap(showFrameTools);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('InkdFrames home screen shows actions', (tester) async {
    await tester.pumpWidget(const InkdFramesApp());

    expect(find.text('InkdFrames'), findsOneWidget);
    expect(find.text('Enter Studio'), findsOneWidget);
    expect(find.text('Enter Home'), findsOneWidget);
  });

  testWidgets('Blank Animation opens the workspace screen', (tester) async {
    await openWorkspace(tester);

    expect(find.text('Test Animation'), findsOneWidget);
    expect(find.byTooltip('Save Project'), findsOneWidget);
    await ensureTimelineOpen(tester);
    await ensureFrameToolsOpen(tester);
    expect(find.byTooltip('Add Frame'), findsOneWidget);
  });

  testWidgets('Workspace can add a second frame', (tester) async {
    await openWorkspace(tester);

    await ensureTimelineOpen(tester);
    expect(find.byKey(const Key('frame-0')), findsOneWidget);

    await ensureFrameToolsOpen(tester);

    await tester.tap(find.byTooltip('Add Frame'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('frame-1')), findsOneWidget);
  });

  testWidgets('ECHO preserves three independent historical strokes', (
    tester,
  ) async {
    await openWorkspace(tester);

    final canvasPaints = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is AnimationCanvasPainter,
    );

    expect(canvasPaints, findsWidgets);

    final canvasCenter = tester.getCenter(canvasPaints.first);

    for (final offset in <Offset>[
      const Offset(-80, -60),
      const Offset(-20, 0),
      const Offset(40, 60),
    ]) {
      final gesture = await tester.startGesture(canvasCenter + offset);
      await gesture.moveTo(canvasCenter + offset + const Offset(20, 20));
      await gesture.up();
      await tester.pump();
    }

    await ensureTimelineOpen(tester);
    await ensureFrameToolsOpen(tester);

    await tester.tap(find.byTooltip('Add Frame'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('frame-1')), findsOneWidget);

    final echoPaints = find.descendant(
      of: find.byType(ColorFiltered),
      matching: canvasPaints,
    );

    final historicalPainters = tester
        .widgetList<CustomPaint>(echoPaints)
        .map((widget) => widget.painter)
        .whereType<AnimationCanvasPainter>()
        .where((painter) => painter.strokes.isNotEmpty)
        .toList();

    expect(historicalPainters, isNotEmpty);

    final historicalStrokes = historicalPainters
        .expand((painter) => painter.strokes)
        .toList();

    expect(historicalStrokes, hasLength(3));
    expect(
      historicalStrokes.map((stroke) => stroke.points.length),
      everyElement(2),
    );
  });
}
