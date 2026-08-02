import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/app/inkdframes_app.dart';

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

    await tester.tap(find.text('Blank Animation'));
    await tester.pumpAndSettle();

    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Add Frame'), findsOneWidget);
  });

  testWidgets('Workspace can add a second frame', (tester) async {
    await tester.pumpWidget(const InkdFramesApp());

    await tester.tap(find.text('Blank Animation'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('frame-0')), findsOneWidget);

    await tester.tap(find.text('Add Frame'));
    await tester.pump();

    expect(find.byKey(const Key('frame-1')), findsOneWidget);
  });
}
