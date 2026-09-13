import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/fox_palette.dart';
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

/// Repère les portions `code` en ligne, hors bloc.
final _inlineCodePattern = RegExp(r'`([^`\n]+)`');

/// Construit les fragments d'un paragraphe, code en ligne mis en valeur.
List<InlineSpan> buildInlineSpans(String text, {required TextStyle codeStyle}) {
  final spans = <InlineSpan>[];
  var index = 0;
  for (final match in _inlineCodePattern.allMatches(text)) {
    if (match.start > index) {
      spans.add(TextSpan(text: text.substring(index, match.start)));
    }
    spans.add(TextSpan(text: match.group(1), style: codeStyle));
    index = match.end;
  }
  if (index < text.length) {
    spans.add(TextSpan(text: text.substring(index)));
  }
  return spans;
}

/// Affiche le contenu d'un message : prose et blocs de code copiables.
class MessageMarkdown extends StatelessWidget {
  const MessageMarkdown({
    super.key,
    required this.content,
    required this.textStyle,
  });

  final String content;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    final codeStyle = textStyle.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const <String>['Roboto Mono', 'Courier New'],
      fontSize: (textStyle.fontSize ?? 16) - 2,
      color: fox.accentText,
    );

    final widgets = <Widget>[];
    for (final segment in parseMessageSegments(content)) {
      switch (segment) {
        case MessageText(:final text):
          widgets.add(
            Text.rich(
              TextSpan(children: buildInlineSpans(text, codeStyle: codeStyle)),
              style: textStyle,
            ),
          );
        case MessageCode(:final code, :final language, :final isComplete):
          widgets.add(
            CodeBlock(code: code, language: language, isComplete: isComplete),
          );
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
      children: <Widget>[
        for (var i = 0; i < widgets.length; i += 1) ...<Widget>[
          if (i > 0) const SizedBox(height: 12),
          widgets[i],
        ],
      ],
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
