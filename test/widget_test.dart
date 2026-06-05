import 'package:flutter_test/flutter_test.dart';
import 'package:imblinlin/main.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(const BlinlinApp());
    expect(find.text('Blinlin'), findsNothing);
  });
}
