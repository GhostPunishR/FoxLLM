// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/features/chat/speech.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm_native/foxllm_native.dart';

/// La fin d'un énoncé passe maintenant par la réponse de `speak`, donc par un
/// tour de boucle : rien ne s'éteint plus de façon synchrone.
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  group('service de lecture', () {
    test('la fin du texte éteint l’état, sans qu’on ait rien arrêté', () async {
      final tts = _FakeTts();
      final speech = Speech(tts: tts);

      expect(await speech.toggle('Bonjour'), isTrue);
      expect(speech.speaking.value, 'Bonjour');

      // Android signale la fin de l'énoncé : personne n'appelle `stop()`.
      tts.finish();
      await _tick();

      expect(speech.speaking.value, isNull);
    });

    test('l’observable prévient à chaque changement', () async {
      final tts = _FakeTts();
      final speech = Speech(tts: tts);
      final seen = <String?>[];
      speech.speaking.addListener(() => seen.add(speech.speaking.value));

      await speech.toggle('Bonjour');
      tts.finish();
      await _tick();
      await speech.toggle('Autre chose');
      await speech.toggle('Autre chose');

      expect(seen, <String?>['Bonjour', null, 'Autre chose', null]);
    });

    test('une annulation et une erreur éteignent aussi l’état', () async {
      final tts = _FakeTts();
      final speech = Speech(tts: tts);

      await speech.toggle('Bonjour');
      tts.cancel();
      await _tick();
      expect(speech.speaking.value, isNull);

      await speech.toggle('Bonjour');
      tts.fail('voix absente');
      await _tick();
      expect(speech.speaking.value, isNull);
    });

    test('relire le même texte l’arrête', () async {
      final tts = _FakeTts();
      final speech = Speech(tts: tts);

      await speech.toggle('Bonjour');
      expect(await speech.toggle('Bonjour'), isFalse);
      expect(speech.speaking.value, isNull);
      expect(tts.stopCalls, 1);
    });

    test('passer à un autre texte arrête le premier', () async {
      final tts = _FakeTts();
      final speech = Speech(tts: tts);

      await speech.toggle('Premier');
      expect(await speech.toggle('Second'), isTrue);
      expect(speech.speaking.value, 'Second');
      expect(tts.stopCalls, 1);
      expect(tts.spoken, <String>['Premier', 'Second']);
    });

    test('un texte vide ne lance rien', () async {
      final tts = _FakeTts();
      final speech = Speech(tts: tts);

      expect(await speech.toggle('   '), isFalse);
      expect(tts.spoken, isEmpty);
      expect(speech.speaking.value, isNull);
    });
  });

  group('bouton de lecture', () {
    testWidgets('revient au repos quand la lecture se termine', (tester) async {
      final tts = _FakeTts();
      await _pumpAnswer(tester, tts);

      await tester.tap(find.byTooltip('Lire à voix haute'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Arrêter la lecture'), findsOneWidget);
      expect(find.byTooltip('Lire à voix haute'), findsNothing);

      // Le défaut d'origine : le bouton restait allumé après la dernière
      // syllabe, parce que l'écran gardait une copie que rien ne rafraîchit.
      tts.finish();
      await tester.pumpAndSettle();

      expect(find.byTooltip('Lire à voix haute'), findsOneWidget);
      expect(find.byTooltip('Arrêter la lecture'), findsNothing);
    });

    testWidgets('rappuyer après la fin relit, sans rester bloqué', (
      tester,
    ) async {
      final tts = _FakeTts();
      await _pumpAnswer(tester, tts);

      await tester.tap(find.byTooltip('Lire à voix haute'));
      await tester.pumpAndSettle();
      tts.finish();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Lire à voix haute'));
      await tester.pumpAndSettle();

      expect(tts.spoken, <String>['Réponse à lire', 'Réponse à lire']);
      expect(find.byTooltip('Arrêter la lecture'), findsOneWidget);
    });

    testWidgets('le bouton arrête vraiment la lecture en cours', (
      tester,
    ) async {
      final tts = _FakeTts();
      await _pumpAnswer(tester, tts);

      await tester.tap(find.byTooltip('Lire à voix haute'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Arrêter la lecture'));
      await tester.pumpAndSettle();

      expect(tts.stopCalls, 1);
      expect(find.byTooltip('Lire à voix haute'), findsOneWidget);
    });

    testWidgets('quitter l’écran pendant la lecture ne lève rien', (
      tester,
    ) async {
      final tts = _FakeTts();
      await _pumpAnswer(tester, tts);

      await tester.tap(find.byTooltip('Lire à voix haute'));
      await tester.pumpAndSettle();

      // L'écran part alors que la voix parle encore : l'écouteur doit être
      // retiré avant l'arrêt, sans quoi le rappel toucherait un écran détruit.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(tts.stopCalls, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('un arrêt annule un démarrage en attente', () {
    test(
      'la voix ne part pas si l’arrêt survient pendant la préparation',
      () async {
        final tts = _FakeTts()..holdSetLanguage = true;
        final speech = Speech(tts: tts);

        final pending = speech.toggle('Bonjour');
        // La préparation n'est pas revenue : rien ne parle encore, et c'est
        // justement le moment où l'arrêt doit compter.
        expect(speech.speaking.value, isNull);
        await speech.stop();

        tts.releaseSetLanguage();
        expect(await pending, isFalse);
        expect(tts.spoken, isEmpty, reason: 'aucune lecture tardive');
        expect(speech.speaking.value, isNull);
      },
    );

    test('un arrêt pendant la lecture la coupe, et sa fin tardive ne '
        'relance rien', () async {
      // Ce contrôle portait sur un `speak` qui aboutissait après l'arrêt, et
      // exigeait un second arrêt. Avec `awaitSpeakCompletion`, la réponse de
      // `speak` n'annonce plus le départ mais la fin de l'énoncé : le seul
      // arrêt envoyé suffit, et c'est sa fin tardive qui ne doit rien réveiller.
      final tts = _FakeTts()..delayCallbacks = true;
      final speech = Speech(tts: tts);

      expect(await speech.toggle('Bonjour'), isTrue);
      await speech.stop();

      expect(speech.speaking.value, isNull);
      expect(tts.stopCalls, 1, reason: 'la voix a bien été coupée');

      tts.deliverHeldCallbacks();
      await _tick();
      expect(speech.speaking.value, isNull);
    });

    test('le rappel d’annulation d’une bascule n’éteint pas la nouvelle '
        'lecture', () async {
      final tts = _FakeTts();
      final speech = Speech(tts: tts);

      expect(await speech.toggle('Première'), isTrue);
      // Passer à une autre phrase arrête la première : Android annonce alors
      // son annulation, sans préciser laquelle.
      expect(await speech.toggle('Seconde'), isTrue);
      expect(speech.speaking.value, 'Seconde');
      expect(tts.spoken, <String>['Première', 'Seconde']);
    });

    test('la destruction pendant un démarrage n’ouvre plus rien', () async {
      final tts = _FakeTts()..holdSetLanguage = true;
      final speech = Speech(tts: tts);

      final pending = speech.toggle('Première');
      await _tick();
      await speech.dispose();
      tts.releaseSetLanguage();

      expect(await pending, isFalse);
      expect(speech.speaking.value, isNull);
      expect(tts.spoken, isEmpty, reason: 'rien n’est parti après la fin');
      // Et plus rien ne repart après la destruction.
      expect(await speech.toggle('Seconde'), isFalse);
      expect(tts.spoken, isEmpty);
    });

    test('un rappel d’annulation arrivé après le démarrage de la suivante '
        'ne l’éteint pas', () async {
      // Le scénario que `_switching` ne couvrait pas : le rappel de A ne
      // traverse le `Handler` d'Android qu'après que B a fini de démarrer.
      final tts = _FakeTts()..delayCallbacks = true;
      final speech = Speech(tts: tts);

      expect(await speech.toggle('Première'), isTrue);
      expect(await speech.toggle('Seconde'), isTrue);
      expect(speech.speaking.value, 'Seconde');

      tts.deliverHeldCallbacks();
      await _tick();

      expect(
        speech.speaking.value,
        'Seconde',
        reason: 'un rappel de la lecture précédente a éteint la suivante',
      );

      // Et la vraie fin de la seconde remet bien au repos.
      tts.finish();
      await _tick();
      expect(speech.speaking.value, isNull);
    });

    test('un rappel de fin arrivé après le démarrage de la suivante ne '
        'l’éteint pas', () async {
      final tts = _FakeTts()..delayCallbacks = true;
      final speech = Speech(tts: tts);

      expect(await speech.toggle('Première'), isTrue);
      // Fin naturelle de la première : c'est la réponse de `speak` qui
      // l'annonce, le rappel anonyme suivra plus tard.
      tts.finish();
      await _tick();
      expect(speech.speaking.value, isNull);

      expect(await speech.toggle('Seconde'), isTrue);
      tts.deliverHeldCallbacks();
      await _tick();

      expect(speech.speaking.value, 'Seconde');
    });

    test('un rappel d’erreur arrivé après le démarrage de la suivante ne '
        'l’éteint pas', () async {
      final tts = _FakeTts()..delayCallbacks = true;
      final speech = Speech(tts: tts);

      expect(await speech.toggle('Première'), isTrue);
      tts.fail('voix absente');
      await _tick();
      expect(speech.speaking.value, isNull);

      expect(await speech.toggle('Seconde'), isTrue);
      tts.deliverHeldCallbacks();
      await _tick();

      expect(speech.speaking.value, 'Seconde');

      tts.finish();
      await _tick();
      expect(speech.speaking.value, isNull);
    });

    test('deux demandes rapprochées ne laissent que la dernière', () async {
      final tts = _FakeTts()..holdSetLanguage = true;
      final speech = Speech(tts: tts);

      final first = speech.toggle('Premier');
      final second = speech.toggle('Second');
      tts.releaseSetLanguage();

      expect(await first, isFalse);
      expect(await second, isTrue);
      expect(tts.spoken, <String>['Second']);
      expect(speech.speaking.value, 'Second');
    });
  });

  group('la voix s’arrête quand le message quitte l’écran', () {
    testWidgets('changer de conversation coupe la lecture', (tester) async {
      final tts = _FakeTts();
      await _pumpTwoThreads(tester, tts);

      await tester.tap(find.byTooltip('Lire à voix haute'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Arrêter la lecture'), findsOneWidget);

      await _openThread(tester, 'Autre fil');

      // Le fil quitté continuait de se faire lire, et plus aucun bouton ne
      // permettait de l'interrompre : il était parti avec le message.
      expect(tts.stopCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un nouveau chat coupe la lecture', (tester) async {
      final tts = _FakeTts();
      await _pumpAnswer(tester, tts);

      await tester.tap(find.byTooltip('Lire à voix haute'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Nouveau chat'));
      await tester.pumpAndSettle();

      expect(tts.stopCalls, 1);
    });

    testWidgets('supprimer le fil affiché coupe la lecture', (tester) async {
      final tts = _FakeTts();
      await _pumpTwoThreads(tester, tts);

      await tester.tap(find.byTooltip('Lire à voix haute'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Actions de la conversation').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();

      expect(tts.stopCalls, 1);
    });

    testWidgets('régénérer la réponse lue coupe la lecture', (tester) async {
      final tts = _FakeTts();
      await _pumpAnswer(tester, tts);

      await tester.tap(find.byTooltip('Lire à voix haute'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Plus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Régénérer la réponse'));
      await tester.pumpAndSettle();

      expect(tts.stopCalls, 1);
      expect(find.byTooltip('Lire à voix haute'), findsOneWidget);
    });

    testWidgets('régénérer laisse parler une autre réponse', (tester) async {
      final tts = _FakeTts();
      await _pumpAnswer(tester, tts);
      // Un second échange : la première réponse reste en place au-dessus.
      await tester.enterText(find.byType(TextField).first, 'Seconde question');
      await tester.pump();
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pumpAndSettle();

      // On écoute la première réponse, puis on régénère la seconde.
      await tester.tap(find.byTooltip('Lire à voix haute').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Plus').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Régénérer la réponse'));
      await tester.pumpAndSettle();

      // Celle qu'on écoute n'a pas bougé : rien ne justifie de la couper.
      expect(tts.stopCalls, 0);
      expect(find.byTooltip('Arrêter la lecture'), findsOneWidget);
    });
  });
}

/// Affiche deux fils enregistrés, le premier ouvert et lisible.
Future<void> _pumpTwoThreads(WidgetTester tester, _FakeTts tts) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(_ScriptedBackend()),
        conversationStoreProvider.overrideWithValue(
          _SeededStore(<ChatConversation>[
            ChatConversation(
              id: 1,
              title: 'Fil écouté',
              updatedAt: DateTime.now(),
              messages: <ChatMessage>[
                const ChatMessage.user('Ma question'),
                const ChatMessage.assistant('Réponse à lire'),
              ],
            ),
            ChatConversation(
              id: 2,
              title: 'Autre fil',
              updatedAt: DateTime.now(),
              messages: <ChatMessage>[const ChatMessage.user('Ailleurs')],
            ),
          ]),
        ),
        speechProvider.overrideWithValue(Speech(tts: tts)),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();

  await _openThread(tester, 'Fil écouté');
}

/// Ouvre un fil depuis le menu latéral.
Future<void> _openThread(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(title).last);
  await tester.pumpAndSettle();
}

class _SeededStore implements ConversationStore {
  _SeededStore(this.seed);

  final List<ChatConversation> seed;

  @override
  Future<List<ChatConversation>> load() async => seed;

  @override
  Future<void> save(List<ChatConversation> conversations) async {}

  @override
  Future<void> clear() async {}
}

/// Affiche un chat portant une réponse terminée, prête à être lue.
Future<void> _pumpAnswer(WidgetTester tester, _FakeTts tts) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(_ScriptedBackend()),
        conversationStoreProvider.overrideWithValue(_EmptyStore()),
        speechProvider.overrideWithValue(Speech(tts: tts)),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).first, 'Ma question');
  await tester.pump();
  await tester.tap(find.byTooltip('Envoyer'));
  await tester.pumpAndSettle();
}

/// Synthèse simulée : le test décide quand la voix se tait.
///
/// `FlutterTts` n'appelle la plateforme qu'à l'usage, jamais dans son
/// constructeur : en hériter suffit donc à l'écarter du banc de test.
/// Moteur simulé, calqué sur le plugin réel.
///
/// Avec `awaitSpeakCompletion(true)`, le plugin Android garde la réponse de
/// `speak` jusqu'à la fin de l'énoncé qu'il a lancé : il la rend à 1 sur une
/// fin naturelle, à 0 sur un arrêt ou une panne. Il appelle ensuite le rappel
/// correspondant, qui lui ne porte aucun identifiant et arrive depuis le fil
/// de la synthèse, donc pas forcément à l'heure.
class _FakeTts extends FlutterTts {
  final List<String> spoken = <String>[];
  int stopCalls = 0;
  bool awaitsCompletion = false;

  /// Vanne : le test décide quand la préparation revient.
  bool holdSetLanguage = false;
  final _languageGate = Completer<void>();

  void releaseSetLanguage() => _languageGate.complete();

  /// Énoncé en cours, tant qu'Android n'en a pas annoncé la fin.
  Completer<dynamic>? _utterance;

  /// Retient les rappels au lieu de les délivrer avec la fin de l'énoncé.
  ///
  /// C'est ainsi qu'ils arrivent en retard sur l'appareil : `onStop` et
  /// `onDone` traversent un `Handler` avant d'atteindre Dart.
  bool delayCallbacks = false;
  final List<void Function()> _held = <void Function()>[];

  /// Délivre enfin les rappels retenus.
  void deliverHeldCallbacks() {
    final held = List<void Function()>.of(_held);
    _held.clear();
    for (final callback in held) {
      callback();
    }
  }

  VoidCallback? _onCompletion;
  VoidCallback? _onCancel;
  ErrorHandler? _onError;

  /// Fin normale de l'énoncé, telle qu'Android la signale.
  void finish() => _end(1, () => _onCompletion?.call());

  void cancel() => _end(0, () => _onCancel?.call());

  void fail(String message) => _end(0, () => _onError?.call(message));

  void _end(int result, void Function() callback) {
    final utterance = _utterance;
    _utterance = null;
    utterance?.complete(result);
    if (delayCallbacks) {
      _held.add(callback);
    } else {
      callback();
    }
  }

  @override
  void setCompletionHandler(VoidCallback callback) => _onCompletion = callback;

  @override
  void setCancelHandler(VoidCallback callback) => _onCancel = callback;

  @override
  void setErrorHandler(ErrorHandler handler) => _onError = handler;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    awaitsCompletion = awaitCompletion;
    return 1;
  }

  @override
  Future<dynamic> setLanguage(String language) async {
    if (holdSetLanguage) {
      await _languageGate.future;
    }
    return 1;
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) {
    spoken.add(text);
    if (!awaitsCompletion) {
      return Future<dynamic>.value(1);
    }
    final utterance = Completer<dynamic>();
    _utterance = utterance;
    return utterance.future;
  }

  @override
  Future<dynamic> stop() async {
    stopCalls += 1;
    // Le plugin rend la réponse de `speak` à 0 dès l'arrêt, puis annonce
    // l'annulation par un rappel qui, lui, peut traîner.
    _end(0, () => _onCancel?.call());
    return 1;
  }
}

class _EmptyStore implements ConversationStore {
  @override
  Future<List<ChatConversation>> load() async => <ChatConversation>[];

  @override
  Future<void> save(List<ChatConversation> conversations) async {}

  @override
  Future<void> clear() async {}
}

class _ScriptedBackend implements LocalLlmBackend {
  @override
  String get id => 'scripted';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'scripted/0.0.0';

  @override
  Future<bool> get isModelLoaded async => true;

  @override
  Future<FoxLlmModelInfo?> get modelInfo async => null;

  @override
  Future<FoxLlmGenerationStats?> get lastGenerationStats async => null;

  @override
  Future<void> loadModel(String path) async {}

  @override
  Future<void> unloadModel() async {}

  int _answers = 0;

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) {
    // Des réponses distinctes : la lecture en cours est repérée par son
    // texte, donc deux réponses identiques seraient indiscernables et le
    // test ne prouverait rien.
    _answers += 1;
    return Stream<String>.value(
      _answers == 1 ? 'Réponse à lire' : 'Réponse numéro $_answers',
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
