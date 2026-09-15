// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/llm/model/chat_message.dart';

void main() {
  late Directory tempDirectory;
  late ConversationStore store;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('foxllm-chats-');
    store = ConversationStore(
      applicationSupportDirectory: () async => tempDirectory,
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  ChatConversation conversation({
    int id = 1,
    String title = 'Première question',
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) {
    return ChatConversation(
      id: id,
      title: title,
      updatedAt: updatedAt ?? DateTime(2026, 9, 13, 10),
      messages:
          messages ??
          <ChatMessage>[
            const ChatMessage.user('Bonjour'),
            const ChatMessage.assistant('Salut !'),
          ],
    );
  }

  test('un historique vide se lit sans fichier', () async {
    expect(await store.load(), isEmpty);
  });

  test('les conversations survivent à un cycle écriture/lecture', () async {
    await store.save(<ChatConversation>[conversation()]);

    final restored = await store.load();
    expect(restored, hasLength(1));
    expect(restored.single.id, 1);
    expect(restored.single.title, 'Première question');
    expect(restored.single.updatedAt, DateTime(2026, 9, 13, 10));
    expect(restored.single.messages.map((m) => m.content), <String>[
      'Bonjour',
      'Salut !',
    ]);
    expect(restored.single.messages.map((m) => m.role), <ChatRole>[
      ChatRole.user,
      ChatRole.assistant,
    ]);
  });

  test('la plus récente arrive en tête', () async {
    await store.save(<ChatConversation>[
      conversation(id: 1, title: 'Ancienne', updatedAt: DateTime(2026, 9, 1)),
      conversation(id: 2, title: 'Récente', updatedAt: DateTime(2026, 9, 12)),
    ]);

    final restored = await store.load();
    expect(restored.map((c) => c.title), <String>['Récente', 'Ancienne']);
  });

  test('l’historique est borné aux plus récentes', () async {
    await store.save(<ChatConversation>[
      for (var i = 0; i < ConversationStore.maxConversations + 25; i++)
        conversation(id: i, title: 'Conversation $i'),
    ]);

    expect(await store.load(), hasLength(ConversationStore.maxConversations));
  });

  test('un fichier corrompu est signalé, pas confondu avec un vide', () async {
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}conversations.json',
    );
    await file.writeAsString('{ ceci n’est pas du JSON');

    // Rendre une liste vide laisserait l'appelant écrire cette liste vide
    // par-dessus le fichier : l'échec doit se distinguer d'un historique
    // réellement vide. L'écran, lui, s'ouvre quand même.
    await expectLater(
      store.load(),
      throwsA(
        isA<ConversationLoadException>()
            .having(
              (e) => e.failure,
              'failure',
              ConversationLoadFailure.unreadable,
            )
            // Le message ne reprend pas la cause technique : celle de
            // `jsonDecode` cite un extrait du fichier, donc du contenu privé.
            .having((e) => e.message, 'message', isNot(contains('ceci'))),
      ),
    );
    expect(await file.exists(), isTrue, reason: 'le fichier n’est pas touché');
  });

  test('un fichier absent est un historique vide, pas un échec', () async {
    expect(await store.load(), isEmpty);
  });

  test(
    'une entrée illisible est signalée, les autres sont récupérées',
    () async {
      final file = File(
        '${tempDirectory.path}${Platform.pathSeparator}conversations.json',
      );
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'conversations': <Object?>[
            'pas un objet',
            <String, Object?>{'id': 'identifiant invalide'},
            <String, Object?>{
              'id': 7,
              'title': 'Valide',
              'updatedAt': DateTime(2026, 9, 13).toIso8601String(),
              'messages': <Object?>[
                <String, Object?>{'role': 'user', 'content': 'Bonjour'},
                <String, Object?>{'role': 'inconnu', 'content': 'ignoré'},
              ],
            },
          ],
        }),
      );

      // Les entrées écartées ne disparaissent pas en silence : la lecture lève,
      // ce qui empêche l'appelant de réécrire le fichier par-dessus. Les
      // conversations exploitables voyagent tout de même avec l'exception.
      await expectLater(
        store.load(),
        throwsA(
          isA<ConversationLoadException>()
              .having(
                (e) => e.failure,
                'failure',
                ConversationLoadFailure.partial,
              )
              .having((e) => e.recovered, 'recovered', hasLength(1)),
        ),
      );
      expect(
        await file.exists(),
        isTrue,
        reason: 'le fichier n’est pas touché',
      );

      try {
        await store.load();
        fail('la lecture aurait dû lever');
      } on ConversationLoadException catch (error) {
        expect(error.recovered.single.title, 'Valide');
        expect(error.recovered.single.messages.map((m) => m.content), <String>[
          'Bonjour',
        ]);
        // Le message destiné à l'utilisateur ne cite rien du fichier.
        expect(error.message, isNot(contains('Valide')));
        expect(error.message, isNot(contains('Bonjour')));
      }
    },
  );

  test('une racine qui n’est pas un objet est une erreur', () async {
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}conversations.json',
    );
    await file.writeAsString(jsonEncode(<Object?>['pas un objet']));

    await expectLater(
      store.load(),
      throwsA(
        isA<ConversationLoadException>().having(
          (e) => e.failure,
          'failure',
          ConversationLoadFailure.malformed,
        ),
      ),
    );
    expect(await file.exists(), isTrue);
  });

  test('un champ conversations absent ou mal typé est une erreur', () async {
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}conversations.json',
    );

    for (final body in <Map<String, Object?>>[
      <String, Object?>{},
      <String, Object?>{'conversations': 'pas une liste'},
      <String, Object?>{'conversations': 42},
    ]) {
      await file.writeAsString(jsonEncode(body));
      await expectLater(
        store.load(),
        throwsA(
          isA<ConversationLoadException>().having(
            (e) => e.failure,
            'failure',
            ConversationLoadFailure.malformed,
          ),
        ),
        reason: '$body doit être refusé',
      );
    }
  });

  test(
    'un message invalide dans une conversation valide est signalé',
    () async {
      final file = File(
        '${tempDirectory.path}${Platform.pathSeparator}conversations.json',
      );
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'conversations': <Object?>[
            <String, Object?>{
              'id': 7,
              'title': 'Valide',
              'updatedAt': DateTime(2026, 9, 13).toIso8601String(),
              'messages': <Object?>[
                <String, Object?>{'role': 'user', 'content': 'Bonjour'},
                // Trois façons de perdre un message à l'intérieur d'une
                // conversation par ailleurs lisible.
                'pas un objet',
                <String, Object?>{'role': 'assistant', 'content': 42},
                <String, Object?>{'role': 'inconnu', 'content': 'ignoré'},
              ],
            },
          ],
        }),
      );
      final original = await file.readAsString();

      // Le défaut d'origine : la conversation était acceptée telle quelle, et
      // le premier enregistrement suivant réécrivait le fichier sans ces trois
      // messages.
      try {
        await store.load();
        fail('la lecture aurait dû signaler la perte');
      } on ConversationLoadException catch (error) {
        expect(error.failure, ConversationLoadFailure.partial);
        expect(error.recovered, hasLength(1));
        expect(error.recovered.single.messages.map((m) => m.content), <String>[
          'Bonjour',
        ]);
        expect(error.message, isNot(contains('Bonjour')));
        expect(error.message, isNot(contains('Valide')));
      }
      expect(await file.readAsString(), original);
    },
  );

  test('une donnée imbriquée illisible est signalée', () async {
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}conversations.json',
    );
    // Une pièce jointe inexploitable, puis une liste de sources mal typée :
    // dans les deux cas, le message reste mais amputé.
    for (final broken in <Map<String, Object?>>[
      <String, Object?>{
        'role': 'user',
        'content': 'Avec pièce jointe',
        'attachments': <Object?>['pas un objet'],
      },
      <String, Object?>{
        'role': 'user',
        'content': 'Avec pièce jointe',
        'attachments': 'pas une liste',
      },
      <String, Object?>{
        'role': 'assistant',
        'content': 'Avec sources',
        'citations': <Object?>[42],
      },
    ]) {
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'conversations': <Object?>[
            <String, Object?>{
              'id': 1,
              'title': 'Valide',
              'updatedAt': DateTime(2026, 9, 13).toIso8601String(),
              'messages': <Object?>[broken],
            },
          ],
        }),
      );

      await expectLater(
        store.load(),
        throwsA(
          isA<ConversationLoadException>().having(
            (e) => e.failure,
            'failure',
            ConversationLoadFailure.partial,
          ),
        ),
        reason: 'perte silencieuse pour $broken',
      );
    }
  });

  test(
    'un ancien historique sans champs optionnels se lit sans erreur',
    () async {
      final file = File(
        '${tempDirectory.path}${Platform.pathSeparator}conversations.json',
      );
      // Le format d'avant les pièces jointes, les sources, les évaluations et
      // l'issue de génération : un champ absent n'est pas une perte.
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'conversations': <Object?>[
            <String, Object?>{
              'id': 1,
              'title': 'Ancien',
              'updatedAt': DateTime(2026, 9, 13).toIso8601String(),
              'messages': <Object?>[
                <String, Object?>{'role': 'user', 'content': 'Bonjour'},
                <String, Object?>{'role': 'assistant', 'content': 'Salut !'},
              ],
            },
          ],
        }),
      );

      final restored = await store.load();
      expect(restored, hasLength(1));
      expect(restored.single.messages, hasLength(2));
      expect(restored.single.messages.first.attachments, isEmpty);
      expect(restored.single.messages.last.outcome, GenerationOutcome.complete);
    },
  );

  test('une valeur d’énumération inconnue n’est pas une perte', () async {
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}conversations.json',
    );
    // Écrit par une version plus récente : la solution de repli remplace la
    // valeur sans rien effacer du contenu.
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'conversations': <Object?>[
          <String, Object?>{
            'id': 1,
            'title': 'Futur',
            'updatedAt': DateTime(2026, 9, 13).toIso8601String(),
            'messages': <Object?>[
              <String, Object?>{
                'role': 'assistant',
                'content': 'Réponse',
                'rating': 'enthousiaste',
                'outcome': 'interrompue_par_le_chat',
              },
            ],
          },
        ],
      }),
    );

    final restored = await store.load();
    expect(restored.single.messages.single.content, 'Réponse');
    expect(restored.single.messages.single.rating, MessageRating.none);
    expect(restored.single.messages.single.outcome, GenerationOutcome.complete);
  });

  test('un historique vide et conforme se lit sans erreur', () async {
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}conversations.json',
    );
    await file.writeAsString(
      jsonEncode(<String, Object?>{'conversations': <Object?>[]}),
    );

    // Le seul cas, avec le fichier absent, où une liste vide est la vérité.
    expect(await store.load(), isEmpty);
  });

  test('des enregistrements concurrents ne se corrompent pas', () async {
    await Future.wait<void>(<Future<void>>[
      for (var i = 0; i < 12; i++)
        store.save(<ChatConversation>[
          conversation(id: i, title: 'Écriture $i'),
        ]),
    ]);

    final restored = await store.load();
    expect(restored, hasLength(1));
    expect(restored.single.title, startsWith('Écriture '));
    // Aucun fichier temporaire ne doit subsister.
    final leftovers = await tempDirectory
        .list()
        .where((entity) => entity.path.endsWith('.part'))
        .length;
    expect(leftovers, 0);
  });

  test('clear efface l’historique', () async {
    await store.save(<ChatConversation>[conversation()]);
    await store.clear();
    expect(await store.load(), isEmpty);
  });
}
