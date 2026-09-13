// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/fox_palette.dart';
import 'external_link.dart';
import 'code_highlighter.dart';

/// Morceau d'un message de chat.
///
/// Les modèles répondent en Markdown : sans découpage, le texte brut affiche
/// les délimiteurs ``` et le code se retrouve mélangé à la prose, illisible et
/// impossible à copier proprement.
sealed class MessageSegment {
  const MessageSegment();
}

/// Prose : tout ce qui n'est pas un bloc de code.
final class MessageText extends MessageSegment {
  const MessageText(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is MessageText && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'MessageText($text)';
}

/// Bloc de code délimité par des triples accents graves.
final class MessageCode extends MessageSegment {
  const MessageCode({
    required this.code,
    this.language,
    this.isComplete = true,
  });

  final String code;

  /// Langage annoncé après la clôture ouvrante (```dart), sinon `null`.
  final String? language;

  /// `false` tant que la clôture n'est pas arrivée : la réponse est encore en
  /// cours de streaming, le bloc se remplit au fil des jetons.
  final bool isComplete;

  @override
  bool operator ==(Object other) =>
      other is MessageCode &&
      other.code == code &&
      other.language == language &&
      other.isComplete == isComplete;

  @override
  int get hashCode => Object.hash(code, language, isComplete);

  @override
  String toString() => 'MessageCode($language, complete: $isComplete)';
}

/// Ligne d'ouverture ou de fermeture d'un bloc, avec son langage éventuel.
///
/// Ancrée en début de ligne pour qu'un ``` cité au fil d'une phrase ne coupe
/// pas le message en deux.
final _fencePattern = RegExp(r'^\s*`{3,}\s*([^\s`]*)');

/// Découpe le contenu d'un message en prose et blocs de code.
List<MessageSegment> parseMessageSegments(String content) {
  // Cas courant : aucun bloc. Le contenu est renvoyé tel quel, sans passer par
  // le découpage ligne à ligne qui normaliserait les fins de ligne.
  if (!content.contains('```')) {
    return content.isEmpty
        ? const <MessageSegment>[]
        : <MessageSegment>[MessageText(content)];
  }

  final segments = <MessageSegment>[];
  final pending = <String>[];
  var inCode = false;
  String? language;

  void flushText() {
    final text = _joinTrimmed(pending);
    pending.clear();
    if (text.isNotEmpty) {
      segments.add(MessageText(text));
    }
  }

  void flushCode({required bool isComplete}) {
    final code = _joinTrimmed(pending);
    pending.clear();
    final declaredLanguage = language;
    language = null;
    // Une clôture ouvrante qui vient d'arriver n'a encore aucune ligne : on
    // n'affiche pas de cadre vide avant les premiers jetons.
    if (code.isEmpty && !isComplete && declaredLanguage == null) {
      return;
    }
    segments.add(
      MessageCode(
        code: code,
        language: declaredLanguage,
        isComplete: isComplete,
      ),
    );
  }

  for (final line in content.split('\n')) {
    final fence = _fencePattern.firstMatch(line);
    if (fence != null) {
      if (inCode) {
        flushCode(isComplete: true);
        inCode = false;
      } else {
        flushText();
        final declared = fence.group(1) ?? '';
        language = declared.isEmpty ? null : declared.toLowerCase();
        inCode = true;
      }
      continue;
    }
    pending.add(line);
  }

  if (inCode) {
    flushCode(isComplete: false);
  } else {
    flushText();
  }

  return segments;
}

/// Joint les lignes en retirant les lignes vides de début et de fin.
String _joinTrimmed(List<String> lines) {
  var start = 0;
  var end = lines.length;
  while (start < end && lines[start].trim().isEmpty) {
    start += 1;
  }
  while (end > start && lines[end - 1].trim().isEmpty) {
    end -= 1;
  }
  return lines.sublist(start, end).join('\n');
}

/// Bloc d'un passage de prose.
///
/// Un titre, une puce ou un trait de séparation ne sont pas du texte courant :
/// affichés tels quels, leurs marques Markdown restaient visibles et la
/// hiérarchie de la réponse disparaissait.
sealed class MessageBlock {
  const MessageBlock();
}

final class ParagraphBlock extends MessageBlock {
  const ParagraphBlock(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      other is ParagraphBlock && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'ParagraphBlock($text)';
}

final class HeadingBlock extends MessageBlock {
  const HeadingBlock({required this.text, required this.level});

  final String text;

  /// Nombre de dièses, de 1 à 6.
  final int level;

  @override
  bool operator ==(Object other) =>
      other is HeadingBlock && other.text == text && other.level == level;

  @override
  int get hashCode => Object.hash(text, level);

  @override
  String toString() => 'HeadingBlock($level, $text)';
}

final class ListItemBlock extends MessageBlock {
  const ListItemBlock({
    required this.text,
    required this.bullet,
    this.depth = 0,
  });

  final String text;

  /// Puce affichée : « • » pour une liste à puces, « 1. » pour une numérotée.
  final String bullet;

  /// Niveau d'imbrication, déduit de l'indentation.
  final int depth;

  @override
  bool operator ==(Object other) =>
      other is ListItemBlock &&
      other.text == text &&
      other.bullet == bullet &&
      other.depth == depth;

  @override
  int get hashCode => Object.hash(text, bullet, depth);

  @override
  String toString() => 'ListItemBlock($bullet, $depth, $text)';
}

final class DividerBlock extends MessageBlock {
  const DividerBlock();

  @override
  bool operator ==(Object other) => other is DividerBlock;

  @override
  int get hashCode => (DividerBlock).hashCode;

  @override
  String toString() => 'DividerBlock()';
}

final _headingPattern = RegExp(r'^ {0,3}(#{1,6})\s+(.*)$');
final _bulletPattern = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final _orderedPattern = RegExp(r'^(\s*)(\d{1,9})[.)]\s+(.*)$');

/// Trait de séparation : une ligne faite d'un seul caractère répété.
final _rulePattern = RegExp(r'^ {0,3}([-*_])[ \t]*(?:\1[ \t]*){2,}$');

/// Découpe un passage de prose en titres, puces, traits et paragraphes.
List<MessageBlock> parseTextBlocks(String text) {
  final blocks = <MessageBlock>[];
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) {
      return;
    }
    blocks.add(ParagraphBlock(paragraph.join('\n')));
    paragraph.clear();
  }

  for (final line in text.split('\n')) {
    if (line.trim().isEmpty) {
      flushParagraph();
      continue;
    }

    if (_rulePattern.hasMatch(line)) {
      flushParagraph();
      blocks.add(const DividerBlock());
      continue;
    }

    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      blocks.add(
        HeadingBlock(
          level: heading.group(1)!.length,
          text: heading.group(2)!.trim(),
        ),
      );
      continue;
    }

    final ordered = _orderedPattern.firstMatch(line);
    if (ordered != null) {
      flushParagraph();
      blocks.add(
        ListItemBlock(
          text: ordered.group(3)!.trim(),
          bullet: '${ordered.group(2)}.',
          depth: _indentDepth(ordered.group(1)!),
        ),
      );
      continue;
    }

    final bullet = _bulletPattern.firstMatch(line);
    if (bullet != null) {
      flushParagraph();
      blocks.add(
        ListItemBlock(
          text: bullet.group(2)!.trim(),
          bullet: '•',
          depth: _indentDepth(bullet.group(1)!),
        ),
      );
      continue;
    }

    paragraph.add(line);
  }

  flushParagraph();
  return blocks;
}

int _indentDepth(String indent) => (indent.length ~/ 2).clamp(0, 4);

/// Construit les fragments d'un paragraphe : gras, italique et code en ligne.
///
/// Les modèles écrivent en Markdown. Rendu tel quel, `**réponse**` s'affichait
/// avec ses astérisques et sans le gras demandé.
///
/// Seuls les délimiteurs à astérisques sont reconnus. Ceux à tirets bas ne le
/// sont pas volontairement : `__init__` ou `nom_de_variable` y perdraient leurs
/// tirets au profit d'un gras jamais demandé.
List<InlineSpan> buildInlineSpans(
  String text, {
  required TextStyle codeStyle,
  TextStyle? linkStyle,
  void Function(Uri url)? onLinkTap,
  List<GestureRecognizer>? recognizers,
}) => _inlineSpans(
  text,
  codeStyle: codeStyle,
  linkStyle: linkStyle,
  onLinkTap: onLinkTap,
  recognizers: recognizers,
  bold: false,
  italic: false,
);

List<InlineSpan> _inlineSpans(
  String text, {
  required TextStyle codeStyle,
  required TextStyle? linkStyle,
  required void Function(Uri url)? onLinkTap,
  required List<GestureRecognizer>? recognizers,
  required bool bold,
  required bool italic,
}) {
  TextStyle? emphasis() {
    if (!bold && !italic) {
      return null;
    }
    return TextStyle(
      fontWeight: bold ? FontWeight.w700 : null,
      fontStyle: italic ? FontStyle.italic : null,
    );
  }

  final spans = <InlineSpan>[];
  final pending = StringBuffer();

  void flush() {
    if (pending.isNotEmpty) {
      spans.add(TextSpan(text: pending.toString(), style: emphasis()));
      pending.clear();
    }
  }

  var index = 0;
  while (index < text.length) {
    final char = text[index];

    if (char == '`') {
      // Le code en ligne n'est pas réinterprété : des astérisques y restent
      // des astérisques.
      final closing = text.indexOf('`', index + 1);
      final newline = text.indexOf('\n', index + 1);
      final onSameLine = newline == -1 || closing < newline;
      if (closing > index + 1 && onSameLine) {
        flush();
        spans.add(
          TextSpan(
            text: text.substring(index + 1, closing),
            style: codeStyle.merge(emphasis()),
          ),
        );
        index = closing + 1;
        continue;
      }
    }

    if (char == '[') {
      final link = _matchLink(text, index);
      if (link != null) {
        flush();
        final recognizer = onLinkTap == null
            ? null
            : (TapGestureRecognizer()..onTap = () => onLinkTap(link.url));
        if (recognizer != null) {
          recognizers?.add(recognizer);
        }
        spans.add(
          TextSpan(
            text: link.label,
            style: (linkStyle ?? const TextStyle()).merge(emphasis()),
            recognizer: recognizer,
          ),
        );
        index = link.end;
        continue;
      }
    }

    if (char == '*') {
      // Un astérisque met en italique, deux en gras, trois les deux à la fois.
      var run = 0;
      while (run < 3 && index + run < text.length && text[index + run] == '*') {
        run += 1;
      }
      final marker = '*' * run;
      final contentStart = index + run;
      final closing = _closingEmphasis(text, contentStart, marker);
      if (closing != -1) {
        flush();
        spans.addAll(
          _inlineSpans(
            text.substring(contentStart, closing),
            codeStyle: codeStyle,
            linkStyle: linkStyle,
            onLinkTap: onLinkTap,
            recognizers: recognizers,
            bold: bold || run >= 2,
            italic: italic || run.isOdd,
          ),
        );
        index = closing + marker.length;
        continue;
      }
    }

    pending.write(char);
    index += 1;
  }

  flush();
  return spans;
}

/// Position du délimiteur fermant, ou `-1` s'il n'y en a pas d'utilisable.
///
/// Les règles écartent ce qui n'est pas une mise en valeur : un produit
/// « 2 * 3 * 4 », une liste à puces, ou des astérisques séparés par un
/// paragraphe entier.
int _closingEmphasis(String text, int contentStart, String marker) {
  if (contentStart >= text.length || _isSpace(text[contentStart])) {
    return -1;
  }

  var index = contentStart;
  while (index < text.length) {
    final closing = text.indexOf(marker, index);
    if (closing == -1) {
      return -1;
    }
    // Un « ** » ne ferme pas une mise en italique ouverte par un seul astérisque.
    if (marker == '*' && text.startsWith('**', closing)) {
      index = closing + 2;
      continue;
    }
    if (closing == contentStart || _isSpace(text[closing - 1])) {
      index = closing + marker.length;
      continue;
    }
    final content = text.substring(contentStart, closing);
    if (content.contains('\n\n')) {
      return -1;
    }
    return closing;
  }
  return -1;
}

/// Lien Markdown reconnu, et position où reprendre la lecture.
typedef _Link = ({String label, Uri url, int end});

/// Reconnaît `[texte](https://…)` ouvert en [start].
///
/// Rend `null` si la forme est incomplète, ou si l'adresse n'est pas en http
/// ou https : le passage s'affiche alors tel qu'écrit, plutôt que de masquer
/// une destination que l'application refuserait d'ouvrir.
_Link? _matchLink(String text, int start) {
  final labelEnd = text.indexOf(']', start + 1);
  if (labelEnd <= start + 1) {
    return null;
  }
  final label = text.substring(start + 1, labelEnd);
  if (label.contains('\n')) {
    return null;
  }
  if (labelEnd + 1 >= text.length || text[labelEnd + 1] != '(') {
    return null;
  }

  final urlEnd = text.indexOf(')', labelEnd + 2);
  if (urlEnd <= labelEnd + 2) {
    return null;
  }
  final raw = text.substring(labelEnd + 2, urlEnd).trim();
  if (raw.isEmpty || raw.contains(RegExp(r'\s'))) {
    return null;
  }

  final url = Uri.tryParse(raw);
  if (url == null || (url.scheme != 'http' && url.scheme != 'https')) {
    return null;
  }
  return (label: label, url: url, end: urlEnd + 1);
}

bool _isSpace(String character) => character.trim().isEmpty;

/// Affiche le contenu d'un message : titres, listes, liens, prose et blocs de
/// code copiables.
class MessageMarkdown extends StatefulWidget {
  const MessageMarkdown({
    super.key,
    required this.content,
    required this.textStyle,
    this.openLink = openExternalLink,
  });

  final String content;
  final TextStyle textStyle;

  /// Ouverture d'un lien, remplaçable pour ne pas dépendre du navigateur en
  /// test. Rend `false` si le lien n'a pas pu être ouvert.
  final Future<bool> Function(Uri url) openLink;

  @override
  State<MessageMarkdown> createState() => _MessageMarkdownState();
}

class _MessageMarkdownState extends State<MessageMarkdown> {
  /// Détecteurs d'appui des liens du rendu courant.
  ///
  /// Ils vivent aussi longtemps que les fragments qui les portent : le message
  /// étant reconstruit à chaque jeton pendant le streaming, ceux du rendu
  /// précédent sont libérés une fois la frame passée.
  List<GestureRecognizer> _recognizers = <GestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  Future<void> _open(Uri url) async {
    final opened = await widget.openLink(url);
    if (opened || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Lien impossible à ouvrir.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    final base = widget.textStyle;
    final baseSize = base.fontSize ?? 16;
    final codeStyle = base.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const <String>['Roboto Mono', 'Courier New'],
      fontSize: baseSize - 2,
      color: fox.accentText,
    );
    final linkStyle = TextStyle(
      color: fox.accentText,
      decoration: TextDecoration.underline,
      decorationColor: fox.accentText,
    );

    final previous = _recognizers;
    final recognizers = <GestureRecognizer>[];
    _recognizers = recognizers;
    if (previous.isNotEmpty) {
      // Libérés après la frame : les fragments qu'ils portent sont encore à
      // l'écran le temps que celle-ci se termine.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final recognizer in previous) {
          recognizer.dispose();
        }
      });
    }

    List<InlineSpan> spansOf(String text) => buildInlineSpans(
      text,
      codeStyle: codeStyle,
      linkStyle: linkStyle,
      onLinkTap: (url) => unawaited(_open(url)),
      recognizers: recognizers,
    );

    final widgets = <Widget>[];
    var previousWasListItem = false;

    void add(Widget child, {required double gapBefore}) {
      if (widgets.isNotEmpty) {
        widgets.add(SizedBox(height: gapBefore));
      }
      widgets.add(child);
    }

    for (final segment in parseMessageSegments(widget.content)) {
      switch (segment) {
        case MessageText(:final text):
          for (final block in parseTextBlocks(text)) {
            switch (block) {
              case ParagraphBlock(:final text):
                add(
                  Text.rich(TextSpan(children: spansOf(text)), style: base),
                  gapBefore: 10,
                );
                previousWasListItem = false;
              case HeadingBlock(:final text, :final level):
                add(
                  Text.rich(
                    TextSpan(children: spansOf(text)),
                    style: base.copyWith(
                      fontSize:
                          baseSize +
                          switch (level) {
                            1 => 6.0,
                            2 => 4.0,
                            3 => 2.0,
                            _ => 1.0,
                          },
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  gapBefore: 14,
                );
                previousWasListItem = false;
              case ListItemBlock(:final text, :final bullet, :final depth):
                add(
                  Padding(
                    padding: EdgeInsets.only(left: depth * 16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 24,
                          child: Text(
                            bullet,
                            style: base.copyWith(color: fox.textSecondary),
                          ),
                        ),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: spansOf(text)),
                            style: base,
                          ),
                        ),
                      ],
                    ),
                  ),
                  gapBefore: previousWasListItem ? 4 : 10,
                );
                previousWasListItem = true;
              case DividerBlock():
                add(
                  Divider(height: 1, thickness: 1, color: fox.border),
                  gapBefore: 14,
                );
                previousWasListItem = false;
            }
          }
        case MessageCode(:final code, :final language, :final isComplete):
          add(
            CodeBlock(code: code, language: language, isComplete: isComplete),
            gapBefore: 12,
          );
          previousWasListItem = false;
      }
    }

    if (widgets.isEmpty) {
      return const SizedBox.shrink();
    }
    if (widgets.length == 1) {
      return widgets.single;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }
}

/// Fragments colorés d'un bloc de code.
///
/// Sans coloration, tout le bloc s'affichait dans la même teinte : lisible
/// pour une ligne, pénible pour une fonction entière.
List<InlineSpan> codeSpans(
  String code, {
  required String? language,
  required FoxPalette palette,
}) {
  Color colorOf(CodeTokenType type) => switch (type) {
    CodeTokenType.plain => palette.textPrimary,
    CodeTokenType.comment => palette.codeComment,
    CodeTokenType.string => palette.codeString,
    CodeTokenType.number => palette.codeNumber,
    CodeTokenType.keyword => palette.codeKeyword,
    CodeTokenType.call => palette.codeCall,
  };

  return <InlineSpan>[
    for (final token in highlightCode(code, language: language))
      TextSpan(
        text: token.text,
        style: TextStyle(
          color: colorOf(token.type),
          fontStyle: token.type == CodeTokenType.comment
              ? FontStyle.italic
              : null,
          fontWeight: token.type == CodeTokenType.keyword
              ? FontWeight.w600
              : null,
        ),
      ),
  ];
}

/// Bloc de code avec en-tête, langage et bouton de copie.
class CodeBlock extends StatefulWidget {
  const CodeBlock({
    super.key,
    required this.code,
    this.language,
    this.isComplete = true,
  });

  final String code;
  final String? language;
  final bool isComplete;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  /// Retour visuel après une copie, remplacé par le libellé d'origine ensuite.
  Timer? _copiedTimer;
  bool _copied = false;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    return Container(
      decoration: BoxDecoration(
        color: fox.surfaceInput,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fox.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: fox.border)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.language ?? 'code',
                    style: TextStyle(
                      color: fox.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(_copy()),
                  style: TextButton.styleFrom(
                    foregroundColor: _copied ? fox.accent : fox.textSecondary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 16,
                  ),
                  label: Text(
                    _copied ? 'Copié' : 'Copier',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          // Le code garde ses retours à la ligne d'origine : il défile à
          // l'horizontale plutôt que d'être replié n'importe où.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: SelectableText.rich(
              TextSpan(
                children: codeSpans(
                  widget.code,
                  language: widget.language,
                  palette: fox,
                ),
              ),
              style: TextStyle(
                color: fox.textPrimary,
                fontFamily: 'monospace',
                fontFamilyFallback: const <String>[
                  'Roboto Mono',
                  'Courier New',
                ],
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
