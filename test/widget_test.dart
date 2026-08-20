import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/inkdframes_app.dart';
import 'package:inkdframes/app/painters/animation_canvas_painter.dart';

Future<void> openWorkspace(WidgetTester tester) async {
  await tester.tap(find.text('Blank Animation'));
  await tester.pumpAndSettle();

  expect(find.text('Name your animation'), findsOneWidget);

  await tester.enterText(find.byType(TextField), 'Test Animation');
  await tester.tap(find.text('Create'));
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
    expect(
      find.text('Turn your Galaxy Ultra into a portable animation studio.'),
      findsOneWidget,
    );
    expect(find.text('Import a Memory'), findsOneWidget);
    expect(find.text('Blank Animation'), findsOneWidget);
  });

  testWidgets('Blank Animation opens the workspace screen', (tester) async {
    await tester.pumpWidget(const InkdFramesApp());

    await openWorkspace(tester);

    expect(find.text('Test Animation'), findsOneWidget);
    expect(find.byTooltip('Save Project'), findsOneWidget);
    expect(find.byTooltip('Add Frame'), findsOneWidget);
  });

  testWidgets('Workspace can add a second frame', (tester) async {
    await tester.pumpWidget(const InkdFramesApp());

    await openWorkspace(tester);

    await ensureTimelineOpen(tester);
    expect(find.byKey(const Key('frame-0')), findsOneWidget);

    await ensureFrameToolsOpen(tester);

    await tester.tap(find.byTooltip('Add Frame'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('frame-1')), findsOneWidget);
  });

  testWidgets('Three separate strokes remain independent onion-skin strokes', (
    tester,
  ) async {
    await tester.pumpWidget(const InkdFramesApp());

    await openWorkspace(tester);

    final customPaintFinder = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is AnimationCanvasPainter,
    );

    expect(customPaintFinder, findsOneWidget);

    final canvasCenter = tester.getCenter(customPaintFinder);

    final firstStroke = await tester.startGesture(
      canvasCenter + const Offset(20, 20),
    );
    await firstStroke.moveTo(canvasCenter + const Offset(60, 60));
    await firstStroke.up();
    await tester.pump();

    final secondStroke = await tester.startGesture(
      canvasCenter + const Offset(80, 80),
    );
    await secondStroke.moveTo(canvasCenter + const Offset(120, 120));
    await secondStroke.up();
    await tester.pump();

    final thirdStroke = await tester.startGesture(
      canvasCenter + const Offset(140, 140),
    );
    await thirdStroke.moveTo(canvasCenter + const Offset(180, 180));
    await thirdStroke.up();
    await tester.pump();

    await ensureFrameToolsOpen(tester);

    await tester.tap(find.byTooltip('Add Frame'));
    await tester.pumpAndSettle();

    final customPaint = tester
        .widgetList<CustomPaint>(customPaintFinder)
        .firstWhere((widget) => widget.painter is AnimationCanvasPainter);

    final painter = customPaint.painter as AnimationCanvasPainter;

    expect(painter.previousOnionSkinStrokes, hasLength(3));
    expect(
      painter.previousOnionSkinStrokes.map((stroke) => stroke.points.length),
      [2, 2, 2],
    );
    expect(painter.nextOnionSkinStrokes, isEmpty);
  });
}
