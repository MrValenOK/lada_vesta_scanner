import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lada_vesta_scanner/main.dart'; // Если проект называется иначе, поменяй здесь

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: VestaScanApp()));
    expect(find.text('VestaScan Pro'), findsOneWidget);
  });
}