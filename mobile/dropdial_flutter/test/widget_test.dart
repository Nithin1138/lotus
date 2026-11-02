import 'package:flutter_test/flutter_test.dart';
import 'package:dropdial_flutter/main.dart';

void main() {
  testWidgets('DropDial App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DropDialMobileApp());
    expect(find.text('DropDial'), findsOneWidget);
    expect(find.text('Formats'), findsOneWidget);
  });
}
