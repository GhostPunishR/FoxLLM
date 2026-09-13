// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/llm/chat_attachment.dart';
import 'package:foxllm/core/llm/chat_message.dart';
import 'package:foxllm/core/llm/local_backend_provider.dart';
import 'package:foxllm/core/llm/generation_settings.dart';
import 'package:foxllm/core/llm/local_llm_backend.dart';
import 'package:foxllm/features/chat/attachment_picker.dart';
import 'package:foxllm/features/chat/attachment_resolver.dart';
import 'package:foxllm/features/chat/attachment_store.dart';
import 'package:foxllm/features/chat/chat_conversation.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversation_store.dart';
import 'package:foxllm_native/foxllm_native.dart';

void main() {
  group('ChatAttachment', () {
    test('distingue une image d’un fichier texte', () {
      expect(_attachment(mimeType: 'image/png').isImage, isTrue);
      expect(_attachment(mimeType: 'text/plain').isImage, isFalse);
      expect(_attachment(mimeType: 'text/plain').isText, isTrue);
    });

    test('survit à un aller-retour JSON', () {
      final attachment = _attachment();
      expect(ChatAttachment.fromJson(attachment.toJson()), attachment);
    });

    test('une entrée abîmée est écartée sans lever', () {
      expect(
        ChatAttachment.fromJson(<String, Object?>{'name': 'seul'}),
        isNull,
      );
      expect(ChatAttachment.fromJson('pas un objet'), isNull);
    });

    test('déduit le type des extensions courantes', () {
      expect(mimeTypeForFileName('photo.JPG'), 'image/jpeg');
      expect(mimeTypeForFileName('notes.md'), 'text/markdown');
      expect(mimeTypeForFileName('main.dart'), 'text/plain');
      expect(mimeTypeForFileName('archive.zip'), 'application/octet-stream');
    });

    test('affiche une taille lisible', () {
      expect(formatAttachmentSize(512), '512 o');
      expect(formatAttachmentSize(2048), '2 Ko');
      expect(formatAttachmentSize(3 * 1024 * 1024), '3.0 Mo');
    });
  });

  group('AttachmentStore', () {
    test('garde une copie, la relit, puis l’efface', () async {
      final store = AttachmentStore(root: _tempRoot());

      final saved = await store.save(
        name: 'note.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList(utf8.encode('bonjour')),
      );

      expect(saved.sizeBytes, 7);
      expect(File(saved.path).existsSync(), isTrue);
      expect(utf8.decode((await store.read(saved))!), 'bonjour');

      await store.delete(<ChatAttachment>[saved]);
      expect(File(saved.path).existsSync(), isFalse);
      expect(await store.read(saved), isNull);
    });

    test('deux fichiers du même nom ne s’écrasent pas', () async {
      final store = AttachmentStore(root: _tempRoot());
      final first = await store.save(
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList(<int>[1]),
      );
      final second = await store.save(
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList(<int>[2, 2]),
      );

      expect(first.path, isNot(second.path));
      expect((await store.read(first))!.length, 1);
      expect((await store.read(second))!.length, 2);
    });

    test('effacer une copie absente ne lève pas', () async {
      final store = AttachmentStore(root: _tempRoot());
      await store.delete(<ChatAttachment>[_attachment(path: '/absent/x.png')]);
    });
  });

  group('resolveAttachments', () {
    test(
      'le texte d’un fichier rejoint le message, annoncé par son nom',
      () async {
        final store = AttachmentStore(root: _tempRoot());
        final attachment = await store.save(
          name: 'main.dart',
          mimeType: 'text/plain',
          bytes: Uint8List.fromList(utf8.encode('void main() {}')),
        );

        final resolved = await resolveAttachments(
          <ChatMessage>[
            ChatMessage(
              role: ChatRole.user,
              content: 'Explique',
              attachments: <ChatAttachment>[attachment],
            ),
          ],
          store: store,
          supportsImages: false,
        );

        expect(resolved.single.content, contains('Explique'));
        expect(resolved.single.content, contains('Fichier joint : main.dart'));
        expect(resolved.single.content, contains('void main() {}'));
        // La requête porte le contenu : les références n'y servent plus.
        expect(resolved.single.attachments, isEmpty);
        expect(resolved.single.images, isEmpty);
      },
    );

    test('une image devient un morceau d’image pour l’API', () async {
      final store = AttachmentStore(root: _tempRoot());
      final attachment = await store.save(
        name: 'photo.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );

      final resolved = await resolveAttachments(
        <ChatMessage>[
          ChatMessage(
            role: ChatRole.user,
            content: 'Décris',
            attachments: <ChatAttachment>[attachment],
          ),
        ],
        store: store,
        supportsImages: true,
      );

      final image = resolved.single.images.single;
      expect(image.mimeType, 'image/png');
      expect(image.dataUrl, startsWith('data:image/png;base64,'));
      expect(resolved.single.content, 'Décris');
    });

    test('un moteur sans vision refuse l’image en le disant', () async {
      final store = AttachmentStore(root: _tempRoot());
      final attachment = await store.save(
        name: 'photo.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(<int>[1]),
      );

      expect(
        () => resolveAttachments(
          <ChatMessage>[
            ChatMessage(
              role: ChatRole.user,
              content: '',
              attachments: <ChatAttachment>[attachment],
            ),
          ],
          store: store,
          supportsImages: false,
        ),
        throwsA(
          isA<UnsupportedAttachmentException>().having(
            (e) => e.message,
            'message',
            allOf(contains('ne lit pas les images'), contains('photo.png')),
          ),
        ),
      );
    });

    test('un binaire non image est refusé clairement', () async {
      final store = AttachmentStore(root: _tempRoot());
      final attachment = await store.save(
        name: 'archive.zip',
        mimeType: 'application/octet-stream',
        bytes: Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0xFF, 0xFE]),
      );

      expect(
        () => resolveAttachments(
          <ChatMessage>[
            ChatMessage(
              role: ChatRole.user,
              content: 'Tiens',
              attachments: <ChatAttachment>[attachment],
            ),
          ],
          store: store,
          supportsImages: true,
        ),
        throwsA(isA<UnsupportedAttachmentException>()),
      );
    });

    test('une copie disparue n’empêche pas l’envoi', () async {
      final store = AttachmentStore(root: _tempRoot());
      final resolved = await resolveAttachments(
        <ChatMessage>[
          ChatMessage(
            role: ChatRole.user,
            content: 'Bonjour',
            attachments: <ChatAttachment>[_attachment(path: '/absent/x.txt')],
          ),
        ],
        store: store,
        supportsImages: false,
      );

      expect(resolved.single.content, 'Bonjour');
    });
  });

  group('message multimodal', () {
    test('le format OpenAI porte texte et image en morceaux', () {
      final json = ChatMessage(
        role: ChatRole.user,
        content: 'Décris',
        images: <InlineImage>[
          InlineImage(
            mimeType: 'image/png',
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ],
      ).toApiJson();

      final parts = json['content'] as List<Object?>;
      expect(parts, hasLength(2));
      expect((parts.first as Map)['text'], 'Décris');
      expect((parts.last as Map)['type'], 'image_url');
    });

    test('sans image, le format reste une simple chaîne', () {
      final json = const ChatMessage.user('Bonjour').toApiJson();
      expect(json['content'], 'Bonjour');
    });
  });

  group('conversation enregistrée', () {
    test('garde les références des pièces jointes', () {
      final conversation = ChatConversation(
        id: 1,
        title: 'Avec image',
        updatedAt: DateTime(2026, 9, 13),
        messages: <ChatMessage>[
          ChatMessage(
            role: ChatRole.user,
            content: 'Regarde',
            attachments: <ChatAttachment>[_attachment()],
          ),
        ],
      );

      final restored = ChatConversation.fromJson(conversation.toJson());
      expect(restored!.messages.single.attachments.single, _attachment());
    });
  });

  group('menu « + » du composer', () {
    testWidgets('propose les trois sources, toutes actives', (tester) async {
      await _pumpChat(tester, _FakePicker());
      await tester.tap(find.byTooltip('Ajouter'));
      await tester.pumpAndSettle();

      for (final label in <String>['Joindre un fichier', 'Photos', 'Caméra']) {
        final tile = tester.widget<ListTile>(
          find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
        );
        expect(tile.onTap, isNotNull, reason: '$label doit être utilisable');
      }
    });

    testWidgets('la pièce jointe choisie apparaît dans le composer', (
      tester,
    ) async {
      final picker = _FakePicker(result: _picked('rapport.txt'));
      await _pumpChat(tester, picker);

      await tester.tap(find.byTooltip('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Joindre un fichier'));
      await tester.pumpAndSettle();

      expect(find.text('rapport.txt'), findsOneWidget);
      expect(find.byTooltip('Retirer rapport.txt'), findsOneWidget);
      // Le contenu du fichier ne s'écrit pas dans le champ de saisie.
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('retirer une pièce jointe la fait disparaître', (tester) async {
      final picker = _FakePicker(result: _picked('rapport.txt'));
      await _pumpChat(tester, picker);

      await tester.tap(find.byTooltip('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Joindre un fichier'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Retirer rapport.txt'));
      await tester.pumpAndSettle();

      expect(find.text('rapport.txt'), findsNothing);
    });

    testWidgets('la pièce jointe envoyée reste une pièce jointe dans le fil', (
      tester,
    ) async {
      final backend = _RecordingBackend();
      await _pumpChat(
        tester,
        _FakePicker(result: _picked('rapport.txt')),
        backend: backend,
      );

      await tester.tap(find.byTooltip('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Joindre un fichier'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Résume ceci');
      await tester.pump();
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pumpAndSettle();

      // Le fil montre le fichier, pas son contenu.
      expect(find.text('rapport.txt'), findsOneWidget);
      expect(find.text('Résume ceci'), findsOneWidget);
      expect(find.textContaining('contenu du fichier'), findsNothing);

      // Le modèle, lui, reçoit bien le contenu.
      final sent = backend.calls.single.last.content;
      expect(sent, contains('Résume ceci'));
      expect(sent, contains('Fichier joint : rapport.txt'));
      expect(sent, contains('contenu du fichier'));
    });

    testWidgets('une pièce jointe seule suffit à envoyer', (tester) async {
      final backend = _RecordingBackend();
      await _pumpChat(
        tester,
        _FakePicker(result: _picked('notes.txt')),
        backend: backend,
      );

      await tester.tap(find.byTooltip('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Joindre un fichier'));
      await tester.pumpAndSettle();

      // Sans texte saisi, le bouton d'envoi doit quand même être proposé.
      expect(find.byTooltip('Envoyer'), findsOneWidget);
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pumpAndSettle();

      expect(backend.calls, hasLength(1));
      expect(find.text('notes.txt'), findsOneWidget);
    });

    testWidgets('un refus du sélecteur est expliqué', (tester) async {
      await _pumpChat(
        tester,
        _FakePicker(
          error: const AttachmentException('Pièce jointe trop volumineuse.'),
        ),
      );

      await tester.tap(find.byTooltip('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();

      expect(find.text('Pièce jointe trop volumineuse.'), findsOneWidget);
    });
  });
}

PickedAttachment _picked(String name) => PickedAttachment(
  name: name,
  mimeType: mimeTypeForFileName(name),
  bytes: Uint8List.fromList(utf8.encode('contenu du fichier')),
);

ChatAttachment _attachment({
  String name = 'photo.png',
  String path = '/tmp/foxllm/photo.png',
  String mimeType = 'image/png',
  int sizeBytes = 42,
}) => ChatAttachment(
  name: name,
  path: path,
  mimeType: mimeType,
  sizeBytes: sizeBytes,
);

Directory _tempRoot() {
  final directory = Directory.systemTemp.createTempSync('foxllm_attachments');
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

Future<void> _pumpChat(
  WidgetTester tester,
  AttachmentPicker picker, {
  LocalLlmBackend? backend,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        attachmentPickerProvider.overrideWithValue(picker),
        attachmentStoreProvider.overrideWithValue(_MemoryStore()),
        conversationStoreProvider.overrideWithValue(_EmptyStore()),
        localLlmBackendProvider.overrideWithValue(backend ?? _IdleBackend()),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Range les pièces jointes en mémoire.
///
/// Le banc de test simule l'horloge : une écriture disque n'y aboutit jamais,
/// et l'écran resterait bloqué en attendant la copie.
class _MemoryStore extends AttachmentStore {
  final Map<String, Uint8List> _files = <String, Uint8List>{};

  @override
  Future<ChatAttachment> save({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final path = '/mémoire/${_files.length}_$name';
    _files[path] = bytes;
    return ChatAttachment(
      name: name,
      path: path,
      mimeType: mimeType,
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<Uint8List?> read(ChatAttachment attachment) async =>
      _files[attachment.path];

  @override
  Future<void> delete(Iterable<ChatAttachment> attachments) async {
    for (final attachment in attachments) {
      _files.remove(attachment.path);
    }
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

class _FakePicker implements AttachmentPicker {
  _FakePicker({this.result, this.error});

  /// `null` simule une annulation.
  final PickedAttachment? result;
  final AttachmentException? error;

  @override
  Future<PickedAttachment?> pick(AttachmentSource source) async {
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return result;
  }
}

/// Retient les messages transmis, pour vérifier ce qui part au modèle.
class _RecordingBackend extends _IdleBackend {
  final List<List<ChatMessage>> calls = <List<ChatMessage>>[];

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) {
    calls.add(List<ChatMessage>.of(messages));
    return Stream<String>.value('ok');
  }
}

class _IdleBackend implements LocalLlmBackend {
  @override
  String get id => 'idle';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'idle/0.0.0';

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

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) => Stream<String>.value('ok');

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
