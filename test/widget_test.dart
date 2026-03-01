import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App bar title test', (WidgetTester tester) async {
    // Provide the necessary dependencies for the test.
    SharedPreferences.setMockInitialValues({}); 
    final prefs = await SharedPreferences.getInstance();

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (context) => InspectionProvider(prefs),
        child: const BarcodeScannerApp(),
      ),
    );

    // Verify that the app bar title is correct.
    expect(find.text('流水线条码质检'), findsOneWidget);
  });
}
