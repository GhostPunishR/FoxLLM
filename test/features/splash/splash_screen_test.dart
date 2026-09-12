import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/features/chat/fox_mark.dart';
import 'package:foxgpt/features/splash/splash_screen.dart';

void main() {
  testWidgets('shows branded splash with progress bar', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FoxGptSplashScreen(duration: Duration(hours: 1)),
      ),
    );

    expect(find.byType(FoxMark), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
