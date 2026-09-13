// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

/// Rôle d'un fragment de code, pour lui donner sa couleur.
enum CodeTokenType { plain, comment, string, number, keyword, call }

/// Fragment de code homogène.
class CodeToken {
  const CodeToken(this.text, this.type);

  final String text;
  final CodeTokenType type;

  @override
  bool operator ==(Object other) =>
      other is CodeToken && other.text == text && other.type == type;

  @override
  int get hashCode => Object.hash(text, type);

  @override
  String toString() => 'CodeToken(${type.name}, $text)';
}

/// Syntaxe des commentaires et jeu de mots-clés d'une famille de langages.
class _Grammar {
  const _Grammar({
    required this.keywords,
    this.lineComments = const <String>['//'],
    this.blockComment,
  });

  final Set<String> keywords;
  final List<String> lineComments;

  /// Délimiteurs d'un commentaire multiligne, ouvrant puis fermant.
  final (String, String)? blockComment;
}

const _cKeywords = <String>{
  'abstract',
  'as',
  'async',
  'await',
  'base',
  'bool',
  'break',
  'case',
  'catch',
  'char',
  'class',
  'const',
  'constexpr',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'double',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'float',
  'for',
  'fun',
  'function',
  'get',
  'if',
  'implements',
  'import',
  'in',
  'inline',
  'instanceof',
  'int',
  'interface',
  'is',
  'late',
  'let',
  'library',
  'long',
  'mixin',
  'namespace',
  'new',
  'null',
  'operator',
  'override',
  'package',
  'part',
  'private',
  'protected',
  'public',
  'required',
  'return',
  'sealed',
  'set',
  'short',
  'static',
  'struct',
  'super',
  'switch',
  'sync',
  'template',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'typeof',
  'union',
  'unsigned',
  'val',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

const _pythonKeywords = <String>{
  'and',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'class',
  'continue',
  'def',
  'del',
  'elif',
  'else',
  'except',
  'False',
  'finally',
  'for',
  'from',
  'global',
  'if',
  'import',
  'in',
  'is',
  'lambda',
  'None',
  'nonlocal',
  'not',
  'or',
  'pass',
  'raise',
  'return',
  'True',
  'try',
  'while',
  'with',
  'yield',
};

const _shellKeywords = <String>{
  'case',
  'do',
  'done',
  'elif',
  'else',
  'esac',
  'export',
  'fi',
  'for',
  'function',
  'if',
  'in',
  'local',
  'read',
  'return',
  'then',
  'until',
  'while',
};

const _sqlKeywords = <String>{
  'alter',
  'and',
  'as',
  'asc',
  'by',
  'create',
  'delete',
  'desc',
  'distinct',
  'drop',
  'from',
  'group',
  'having',
  'index',
  'inner',
  'insert',
  'into',
  'join',
  'left',
  'limit',
  'not',
  'null',
  'on',
  'or',
  'order',
  'outer',
  'primary',
  'select',
  'set',
  'table',
  'union',
  'update',
  'values',
  'where',
};

const _dataKeywords = <String>{'true', 'false', 'null'};

const _cFamily = _Grammar(keywords: _cKeywords, blockComment: ('/*', '*/'));

/// Grammaires par langage annoncé après la clôture ouvrante.
const Map<String, _Grammar> _grammars = <String, _Grammar>{
  'bash': _Grammar(keywords: _shellKeywords, lineComments: <String>['#']),
  'c': _cFamily,
  'cpp': _cFamily,
  'csharp': _cFamily,
  'css': _Grammar(
    keywords: <String>{},
    lineComments: <String>[],
    blockComment: ('/*', '*/'),
  ),
  'dart': _cFamily,
  'go': _cFamily,
  'html': _Grammar(
    keywords: <String>{},
    lineComments: <String>[],
    blockComment: ('<!--', '-->'),
  ),
  'java': _cFamily,
  'javascript': _cFamily,
  'json': _Grammar(keywords: _dataKeywords, lineComments: <String>[]),
  'kotlin': _cFamily,
  'php': _Grammar(
    keywords: _cKeywords,
    lineComments: <String>['//', '#'],
    blockComment: ('/*', '*/'),
  ),
  'python': _Grammar(keywords: _pythonKeywords, lineComments: <String>['#']),
  'ruby': _Grammar(keywords: _pythonKeywords, lineComments: <String>['#']),
  'rust': _cFamily,
  'sql': _Grammar(
    keywords: _sqlKeywords,
    lineComments: <String>['--'],
    blockComment: ('/*', '*/'),
  ),
  'swift': _cFamily,
  'typescript': _cFamily,
  'xml': _Grammar(
    keywords: <String>{},
    lineComments: <String>[],
    blockComment: ('<!--', '-->'),
  ),
  'yaml': _Grammar(keywords: _dataKeywords, lineComments: <String>['#']),
};

/// Noms réellement écrits après les triples accents graves.
const Map<String, String> _languageAliases = <String, String>{
  'bash': 'bash',
  'c': 'c',
  'c++': 'cpp',
  'cc': 'cpp',
  'cs': 'csharp',
  'csharp': 'csharp',
  'cpp': 'cpp',
  'css': 'css',
  'dart': 'dart',
  'go': 'go',
  'golang': 'go',
  'h': 'c',
  'hpp': 'cpp',
  'htm': 'html',
  'html': 'html',
  'java': 'java',
  'javascript': 'javascript',
  'js': 'javascript',
  'json': 'json',
  'jsx': 'javascript',
  'kotlin': 'kotlin',
  'kt': 'kotlin',
  'php': 'php',
  'py': 'python',
  'python': 'python',
  'rb': 'ruby',
  'ruby': 'ruby',
  'rs': 'rust',
  'rust': 'rust',
  'sh': 'bash',
  'shell': 'bash',
  'sql': 'sql',
  'swift': 'swift',
  'ts': 'typescript',
  'tsx': 'typescript',
  'typescript': 'typescript',
  'xml': 'xml',
  'yaml': 'yaml',
  'yml': 'yaml',
  'zsh': 'bash',
};

/// Repli quand aucun langage n'est annoncé, ou qu'il est inconnu.
///
/// Seuls les mots-clés communs à la plupart des langages y figurent : colorer
/// large ferait passer pour mot-clé des identifiants ordinaires.
const _fallback = _Grammar(
  keywords: <String>{
    'class',
    'const',
    'def',
    'else',
    'export',
    'false',
    'for',
    'function',
    'if',
    'import',
    'let',
    'new',
    'null',
    'return',
    'true',
    'var',
    'while',
  },
  lineComments: <String>['//', '#'],
  blockComment: ('/*', '*/'),
);

_Grammar _grammarFor(String? language) {
  if (language == null) {
    return _fallback;
  }
  final canonical = _languageAliases[language.toLowerCase()];
  return canonical == null ? _fallback : _grammars[canonical] ?? _fallback;
}

bool _isDigit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;

bool _isIdentifierStart(String c) =>
    (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
    (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
    c == '_' ||
    c == r'$';

bool _isIdentifierPart(String c) => _isIdentifierStart(c) || _isDigit(c);

/// Découpe le code en fragments colorables.
///
/// Un analyseur complet par langage serait hors de proportion ici : le but est
/// de distinguer commentaires, chaînes, nombres, mots-clés et appels, ce qui
/// suffit à rendre un extrait lisible. Tout ce qui n'est pas reconnu reste du
/// texte courant, jamais coloré à tort.
List<CodeToken> highlightCode(String code, {String? language}) {
  if (code.isEmpty) {
    return const <CodeToken>[];
  }

  final grammar = _grammarFor(language);
  final tokens = <CodeToken>[];
  final plain = StringBuffer();
  var index = 0;

  void flushPlain() {
    if (plain.isNotEmpty) {
      tokens.add(CodeToken(plain.toString(), CodeTokenType.plain));
      plain.clear();
    }
  }

  void add(String text, CodeTokenType type) {
    flushPlain();
    tokens.add(CodeToken(text, type));
  }

  while (index < code.length) {
    final rest = code.substring(index);

    final blockComment = grammar.blockComment;
    if (blockComment != null && rest.startsWith(blockComment.$1)) {
      final closing = code.indexOf(
        blockComment.$2,
        index + blockComment.$1.length,
      );
      final end = closing == -1
          ? code.length
          : closing + blockComment.$2.length;
      add(code.substring(index, end), CodeTokenType.comment);
      index = end;
      continue;
    }

    final lineComment = grammar.lineComments
        .where(rest.startsWith)
        .fold<String?>(null, (longest, marker) {
          return longest == null || marker.length > longest.length
              ? marker
              : longest;
        });
    if (lineComment != null) {
      final newline = code.indexOf('\n', index);
      final end = newline == -1 ? code.length : newline;
      add(code.substring(index, end), CodeTokenType.comment);
      index = end;
      continue;
    }

    final char = code[index];
    if (char == '"' || char == "'" || char == '`') {
      final end = _endOfString(code, index, char);
      add(code.substring(index, end), CodeTokenType.string);
      index = end;
      continue;
    }

    if (_isDigit(char)) {
      final end = _endOfNumber(code, index);
      add(code.substring(index, end), CodeTokenType.number);
      index = end;
      continue;
    }

    if (_isIdentifierStart(char)) {
      var end = index + 1;
      while (end < code.length && _isIdentifierPart(code[end])) {
        end += 1;
      }
      final word = code.substring(index, end);
      if (grammar.keywords.contains(word)) {
        add(word, CodeTokenType.keyword);
      } else if (_opensCall(code, end)) {
        add(word, CodeTokenType.call);
      } else {
        plain.write(word);
      }
      index = end;
      continue;
    }

    plain.write(char);
    index += 1;
  }

  flushPlain();
  return tokens;
}

/// Fin d'une chaîne ouverte en [start], délimiteur compris.
///
/// Une chaîne non refermée court jusqu'à la fin de sa ligne — sauf entre
/// accents graves, seul délimiteur couramment multiligne — pour qu'une
/// apostrophe isolée dans un commentaire ou du texte ne colore pas la suite.
int _endOfString(String code, int start, String quote) {
  final allowNewline = quote == '`';
  var index = start + 1;
  while (index < code.length) {
    final char = code[index];
    if (char == r'\') {
      index += 2;
      continue;
    }
    if (char == quote) {
      return index + 1;
    }
    if (char == '\n' && !allowNewline) {
      return index;
    }
    index += 1;
  }
  return code.length;
}

int _endOfNumber(String code, int start) {
  var index = start;
  while (index < code.length) {
    final char = code[index];
    final isExponentSign =
        (char == '-' || char == '+') &&
        index > start &&
        (code[index - 1] == 'e' || code[index - 1] == 'E');
    if (_isDigit(char) ||
        char == '.' ||
        char == '_' ||
        isExponentSign ||
        _isHexOrExponentLetter(char)) {
      index += 1;
      continue;
    }
    break;
  }
  return index;
}

bool _isHexOrExponentLetter(String c) =>
    (c.compareTo('a') >= 0 && c.compareTo('f') <= 0) ||
    (c.compareTo('A') >= 0 && c.compareTo('F') <= 0) ||
    c == 'x' ||
    c == 'X';

/// Vrai si une parenthèse ouvrante suit l'identifiant : c'est un appel.
bool _opensCall(String code, int end) {
  var index = end;
  while (index < code.length && (code[index] == ' ' || code[index] == '\t')) {
    index += 1;
  }
  return index < code.length && code[index] == '(';
}
