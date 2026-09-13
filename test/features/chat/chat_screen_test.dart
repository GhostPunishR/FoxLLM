// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/core/ui/fox_mark.dart';

void main() {
  testWidgets('shows the FoxLLM chat home on launch', (tester) async {
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

  testWidgets('keeps chat content above the composer when input grows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ChatScreen())),
    );
    await tester.pump();

    await tester.enterText(
      find.byType(TextField),
      'Ligne 1\nLigne 2\nLigne 3\nLigne 4\nLigne 5',
    );
    await tester.pumpAndSettle();

    final contentRect = tester.getRect(
      find.byKey(const ValueKey<String>('chat-content')),
    );
    final composerRect = tester.getRect(
      find.byKey(const ValueKey<String>('chat-composer')),
    );

    expect(contentRect.bottom, lessThanOrEqualTo(composerRect.top));
    expect(contentRect.overlaps(composerRect), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the conversation drawer from the top-left menu', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ChatScreen())),
    );

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    expect(find.text('Rechercher dans les chats'), findsOneWidget);
    expect(find.text('Aujourd’hui'), findsOneWidget);
    expect(find.text('Aucune conversation'), findsOneWidget);
    expect(find.text('Paramètres'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens settings from the drawer bottom action', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ChatScreen())),
    );

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();

    expect(find.text('Paramètres'), findsOneWidget);
    expect(find.text('Modèles locaux'), findsOneWidget);
    expect(find.text('API personnelle'), findsOneWidget);
    expect(find.text('Apparence'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
