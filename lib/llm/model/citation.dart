// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

/// Source citée par un modèle qui a consulté le web.
///
/// Seuls les fournisseurs dotés d'un outil de recherche en produisent : le
/// moteur local n'a rien à citer, puisqu'il ne sort pas de l'appareil.
class Citation {
  const Citation({required this.url, this.title = ''});

  final String url;

  /// Titre de la page, quand le fournisseur le donne. Vide sinon : l'adresse
  /// sert alors d'intitulé, plutôt qu'un libellé inventé.
  final String title;

  /// Nom d'hôte, pour situer la source d'un coup d'œil.
  String get host {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return url;
    }
    final host = uri.host.toLowerCase();
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// Ce qui s'affiche : le titre s'il existe, l'hôte sinon.
  String get label => title.trim().isEmpty ? host : title.trim();

  Map<String, Object?> toJson() => <String, Object?>{
    'url': url,
    if (title.isNotEmpty) 'title': title,
  };

  /// Rend `null` si l'entrée est inexploitable, pour qu'une citation abîmée
  /// n'emporte pas la conversation qui la porte.
  static Citation? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    final url = value['url'];
    if (url is! String || url.trim().isEmpty) {
      return null;
    }
    final title = value['title'];
    return Citation(url: url, title: title is String ? title : '');
  }

  @override
  bool operator ==(Object other) => other is Citation && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Ajoute [citation] à [into] si son adresse n'y figure pas déjà.
///
/// Un même lien revient souvent plusieurs fois dans un flux : une fois par
/// passage du texte qui s'y réfère. La liste affichée, elle, ne doit le
/// montrer qu'une fois, dans l'ordre d'apparition.
void addCitation(List<Citation> into, Citation citation) {
  final url = citation.url.trim();
  if (url.isEmpty) {
    return;
  }
  final existing = into.indexWhere((other) => other.url == url);
  if (existing < 0) {
    into.add(Citation(url: url, title: citation.title));
    return;
  }
  // Un titre arrivé plus tard complète une entrée qui n'en avait pas.
  if (into[existing].title.isEmpty && citation.title.isNotEmpty) {
    into[existing] = Citation(url: url, title: citation.title);
  }
}
