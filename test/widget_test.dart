import 'package:flutter_test/flutter_test.dart';
import 'package:inkdframes/main.dart';

void main() {
  testWidgets('InkdFrames home screen shows actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const InkdFramesApp());

    expect(find.text('InkdFrames'), findsOneWidget);
    expect(
      find.text('Turn your Galaxy Ultra into a portable animation studio.'),
      findsOneWidget,
    );
    expect(find.text('Import a Memory'), findsOneWidget);
    expect(find.text('Blank Animation'), findsOneWidget);
  });
}
