import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cowlog_flutter/screens/startup_screen.dart';

void main() {
  testWidgets('Startup shows the approved image then releases the app once', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: StartupScreen(child: Text('app-ready'))),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      const AssetImage('assets/models/cow_holstein.png'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.byType(Image), findsNothing);
    expect(find.text('app-ready'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(Image), findsNothing);
  });
  testWidgets('Reduced motion bypasses the long startup transition', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: StartupScreen(child: Text('app-ready')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.byType(Image), findsNothing);
    expect(find.text('app-ready'), findsOneWidget);
  });
}
