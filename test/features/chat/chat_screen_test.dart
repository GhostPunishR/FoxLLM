import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/features/chat/chat_screen.dart';
import 'package:foxgpt/features/chat/fox_mark.dart';

void main() {
  testWidgets('shows the FoxGPT chat home on launch', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ChatScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FoxMark), findsOneWidget);
    expect(
      find.text("Salut ! Qu'aimeriez-vous\ndiscuter aujourd'hui ?"),
      findsOneWidget,
    );
    expect(find.text('Réflexion'), findsOneWidget);
    expect(find.text('Rechercher'), findsOneWidget);
    expect(find.text('Message ou maintenir pour parler'), findsOneWidget);
    expect(find.byTooltip('Menu'), findsOneWidget);
    expect(find.byTooltip('Nouveau chat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens navigation from the top-left menu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ChatScreen()),
      ),
    );

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    expect(find.text('FoxGPT'), findsOneWidget);
    expect(find.text('Nouveau chat'), findsOneWidget);
    expect(find.text('Modèles locaux'), findsOneWidget);
    expect(find.text('API personnelle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
