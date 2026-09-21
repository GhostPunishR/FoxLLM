// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:foxllm/core/app_info.dart';
import 'package:foxllm/core/theme/fox_palette.dart';
import 'package:foxllm/features/chat/attachments/attachment_store.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/features/chat/conversations/history_archive.dart';
import 'package:foxllm/features/chat/conversations/history_archive_service.dart';
import 'package:foxllm/l10n/app_localizations.dart';

/// Exporter l'historique, et le réimporter ailleurs.
///
/// Ce n'est pas un écran de confort : FoxLLM refuse la sauvegarde d'Android
/// vers Google Drive, et l'assume dans sa politique de confidentialité. La
/// contrepartie est qu'un changement de téléphone emporte tout, et cet écran
/// est la seule réponse à cela.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  bool _busy = false;

  HistoryArchiveService get _service => HistoryArchiveService(
    attachments: ref.read(attachmentStoreProvider),
    appVersion: foxLlmVersion,
  );

  void _say(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final conversations = await ref.read(conversationStoreProvider).load();
      if (conversations.isEmpty) {
        _say(l10n.historyEmpty);
        return;
      }

      final contents = await _service.export(conversations);
      // Le fichier passe par le dossier temporaire : le partage d'Android
      // veut un chemin, et rien ne justifie d'écrire ailleurs une copie que
      // le système effacera.
      final directory = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = File('${directory.path}/foxllm-historique-$stamp.json');
      await file.writeAsString(contents, flush: true);

      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(file.path)], title: l10n.historyTitle),
      );
    } catch (error) {
      _say(l10n.historyExportFailed('$error'));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    final picked = await FilePicker.pickFile(
      dialogTitle: l10n.historyImport,
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    final path = picked?.path;
    if (path == null) {
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await _service.import(await File(path).readAsString());
      final store = ref.read(conversationStoreProvider);

      // Les conversations importées s'ajoutent : écraser l'historique en
      // place perdrait ce qui a été écrit depuis l'export, sans prévenir.
      //
      // Leurs identifiants viennent d'un autre appareil et peuvent déjà être
      // pris ici. Un doublon ferait disparaître une conversation existante
      // à la première écriture, donc chacune reçoit au besoin un numéro
      // libre.
      final existing = await store.load();
      final taken = existing.map((conversation) => conversation.id).toSet();
      var next = taken.isEmpty ? 1 : taken.reduce(math.max) + 1;
      final added = <ChatConversation>[];
      for (final conversation in result.conversations) {
        added.add(
          ChatConversation(
            id: taken.contains(conversation.id) ? next++ : conversation.id,
            title: conversation.title,
            updatedAt: conversation.updatedAt,
            messages: conversation.messages,
            previousMessages: conversation.previousMessages,
          ),
        );
      }
      await store.save(<ChatConversation>[...added, ...existing]);

      _say(
        l10n.historyImported(
          result.conversations.length,
          result.restoredAttachments,
        ),
      );
      if (result.skippedConversations > 0 || result.missingAttachments > 0) {
        _say(
          l10n.historyImportPartial(
            result.skippedConversations,
            result.missingAttachments,
          ),
        );
      }
    } on HistoryArchiveException catch (rejection) {
      _say(l10n.historyImportFailed(_describe(rejection, l10n)));
    } catch (error) {
      _say(l10n.historyImportFailed('$error'));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _describe(HistoryArchiveException rejection, AppLocalizations l10n) =>
      switch (rejection.defect) {
        HistoryArchiveDefect.unreadable => l10n.historyArchiveUnreadable,
        HistoryArchiveDefect.notAnArchive => l10n.historyArchiveNotAnArchive,
        HistoryArchiveDefect.tooRecent => l10n.historyArchiveTooRecent(
          rejection.detail ?? '?',
        ),
        HistoryArchiveDefect.empty => l10n.historyArchiveEmpty,
      };

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.historyTitle,
          style: TextStyle(color: fox.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        children: <Widget>[
          Text(
            l10n.historyIntro,
            style: TextStyle(
              color: fox.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          _Action(
            icon: Icons.ios_share_rounded,
            label: l10n.historyExport,
            hint: l10n.historyExportHint,
            onPressed: _busy ? null : _export,
          ),
          const SizedBox(height: 14),
          _Action(
            icon: Icons.download_rounded,
            label: l10n.historyImport,
            hint: l10n.historyImportHint,
            onPressed: _busy ? null : _import,
          ),
          if (_busy) ...<Widget>[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;

    return Material(
      color: fox.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: fox.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Icon(icon, color: fox.accent),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: TextStyle(
                        color: fox.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hint,
                      style: TextStyle(color: fox.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
