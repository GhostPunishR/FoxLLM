// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';

import 'package:foxllm/core/theme/fox_palette.dart';

class LegalSection {
  const LegalSection({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.updatedAt,
    required this.sections,
  });

  final String title;
  final String updatedAt;
  final List<LegalSection> sections;
}

const termsOfUseDocument = LegalDocument(
  title: 'Conditions d’utilisation',
  updatedAt: 'Septembre 2026',
  sections: <LegalSection>[
    LegalSection(
      title: 'Objet',
      paragraphs: <String>[
        'FoxLLM est un client de discussion qui exécute des modèles de langage '
            'directement sur ton téléphone, ou qui contacte un fournisseur '
            'distant avec une clé API que tu fournis toi-même.',
        'Utiliser l’application vaut acceptation des présentes conditions.',
      ],
    ),
    LegalSection(
      title: 'Clés API et fournisseurs tiers',
      paragraphs: <String>[
        'Le mode « API personnelle » utilise une clé que tu obtiens auprès du '
            'fournisseur de ton choix. FoxLLM ne revend aucun accès et '
            'n’intervient pas dans la relation entre toi et ce fournisseur.',
        'Tu restes seul responsable de cette clé, des coûts facturés par le '
            'fournisseur, et du respect des conditions de ce dernier.',
      ],
    ),
    LegalSection(
      title: 'Ce que tu envoies',
      paragraphs: <String>[
        'En mode « API personnelle », tes messages et les pièces jointes qui '
            'les accompagnent partent vers le fournisseur choisi. Tu restes '
            'responsable de ce que tu envoies, notamment du droit d’en '
            'disposer, et leur traitement relève des conditions de ce '
            'fournisseur.',
        'Le mode « Recherche web » va plus loin : le fournisseur se sert de ta '
            'question pour interroger le web. Ne l’active pas pour un échange '
            'que tu veux garder pour toi.',
        'Avec un modèle local, aucun message n’est envoyé à un fournisseur.',
      ],
    ),
    LegalSection(
      title: 'Modèles locaux',
      paragraphs: <String>[
        'Les fichiers GGUF que tu importes proviennent de sources que tu '
            'choisis. Il t’appartient de vérifier que leur licence autorise '
            'l’usage que tu en fais.',
        'Les performances et la qualité des réponses dépendent du modèle '
            'importé et des capacités de ton appareil.',
      ],
    ),
    LegalSection(
      title: 'Contenus générés',
      paragraphs: <String>[
        'Les réponses sont produites automatiquement : elles peuvent être '
            'inexactes, incomplètes ou inadaptées. Elles ne constituent pas un '
            'conseil professionnel, notamment médical, juridique ou financier.',
        'Il te revient de vérifier toute information avant de l’utiliser.',
      ],
    ),
    LegalSection(
      title: 'Garantie et responsabilité',
      paragraphs: <String>[
        'L’application est fournie en l’état, sans garantie de disponibilité '
            'ni d’absence d’erreur.',
        'Dans les limites permises par la loi applicable, les auteurs ne '
            'peuvent être tenus responsables des dommages résultant de '
            'l’utilisation de l’application.',
      ],
    ),
  ],
);

const privacyPolicyDocument = LegalDocument(
  title: 'Politique de confidentialité',
  updatedAt: 'Septembre 2026',
  sections: <LegalSection>[
    LegalSection(
      title: 'Principe',
      paragraphs: <String>[
        'FoxLLM ne dispose d’aucun serveur. L’application ne collecte, ne '
            'transmet et ne stocke aucune donnée personnelle pour son propre '
            'compte.',
      ],
    ),
    LegalSection(
      title: 'Conversations',
      paragraphs: <String>[
        'Avec un modèle local, les messages ne quittent jamais l’appareil : '
            'la génération est effectuée sur place.',
        'Avec une API personnelle, les messages sont envoyés directement au '
            'fournisseur que tu as configuré, depuis ton téléphone. Leur '
            'traitement relève alors de la politique de confidentialité de ce '
            'fournisseur.',
        'L’historique est enregistré sur l’appareil, dans l’espace de '
            'stockage privé de l’application, afin de retrouver tes '
            'conversations au lancement suivant. Il n’est jamais envoyé '
            'ailleurs.',
      ],
    ),
    LegalSection(
      title: 'Pièces jointes',
      paragraphs: <String>[
        'Une photo, une image de la galerie ou un fichier texte joint à un '
            'message est recopié dans l’espace de stockage privé de '
            'l’application. C’est ce qui permet de rouvrir la conversation des '
            'semaines plus tard et d’y retrouver la pièce jointe, même si '
            'l’original a disparu. Supprimer la conversation efface aussi ces '
            'copies.',
        'FoxLLM n’ouvre de lui-même ni l’appareil photo ni tes dossiers : il '
            'appelle le sélecteur du système, qui ne lui remet que le fichier '
            'choisi.',
        'Avec une API personnelle, l’image part dans la requête et le contenu '
            'du fichier texte rejoint le message : ils suivent le chemin de la '
            'conversation. Un modèle local ne reçoit pas d’image, et le texte '
            'joint ne quitte pas l’appareil.',
      ],
    ),
    LegalSection(
      title: 'Recherche web',
      paragraphs: <String>[
        'Le mode « Recherche web » n’existe qu’avec une API personnelle OpenAI '
            'ou Google : c’est le fournisseur qui consulte le web, jamais '
            'l’application. Ta question lui sert alors à chercher, et les '
            'sources citées reviennent avec la réponse.',
        'Le mode éteint, ou face à un modèle local, aucune recherche n’est '
            'lancée et rien n’est transmis à un moteur de recherche.',
      ],
    ),
    LegalSection(
      title: 'Copie et partage',
      paragraphs: <String>[
        'Copier une réponse la dépose dans le presse-papiers du système ; la '
            'partager la remet à l’application que tu désignes. Dans les deux '
            'cas le texte sort de FoxLLM parce que tu l’as demandé, et ce '
            'qu’il en advient ensuite relève de l’application qui le reçoit.',
      ],
    ),
    LegalSection(
      title: 'Sauvegardes Android',
      paragraphs: <String>[
        'Android sauvegarde par défaut les données des applications vers le '
            'Google Drive de leur utilisateur, et les transfère vers son '
            'téléphone suivant. FoxLLM refuse les deux : ni l’historique, ni '
            'les pièces jointes, ni les réglages, ni les clés API ne sont '
            'copiés hors de l’appareil par ce mécanisme.',
        'La contrepartie est assumée : en changeant de téléphone, ou après '
            'une désinstallation, tes conversations ne reviennent pas. C’est '
            'le prix de la promesse faite plus haut.',
      ],
    ),
    LegalSection(
      title: 'Lecture à voix haute',
      paragraphs: <String>[
        'La lecture d’une réponse utilise le service de synthèse vocale '
            'd’Android. FoxLLM ne produit ni ne conserve aucun son : il '
            'confie le texte de la réponse au service du système, qui le dit.',
        'Selon l’appareil et les voix installées, cette synthèse peut avoir '
            'lieu sur le téléphone ou passer par les serveurs du fournisseur '
            'de la voix, le plus souvent Google. Le texte de la réponse lue '
            'peut donc lui être transmis, y compris lorsque la réponse vient '
            'd’un modèle local.',
      ],
    ),
    LegalSection(
      title: 'Dictée vocale',
      paragraphs: <String>[
        'La dictée utilise le service de reconnaissance vocale d’Android. '
            'FoxLLM ne transporte aucun son lui-même et n’en conserve aucun : '
            'seul le texte reconnu arrive dans le champ de saisie, où tu peux '
            'le corriger avant d’envoyer.',
        'Selon l’appareil et les paquets de langue installés, ce service peut '
            'traiter l’audio sur le téléphone ou l’envoyer à ses propres '
            'serveurs. Ce traitement relève alors de la politique de '
            'confidentialité de Google.',
        'L’accès au micro est demandé à la première dictée, jamais au '
            'lancement, et l’application reste utilisable sans l’accorder.',
      ],
    ),
    LegalSection(
      title: 'Personnalisation',
      paragraphs: <String>[
        'Les instructions écrites dans « Paramètres → Personnalisation » sont '
            'conservées sur l’appareil, dans le stockage sécurisé du système.',
        'Elles accompagnent chaque message envoyé au modèle choisi, local ou '
            'distant, afin qu’il adopte le ton demandé. Les effacer depuis cet '
            'écran les retire immédiatement.',
      ],
    ),
    LegalSection(
      title: 'Clés API',
      paragraphs: <String>[
        'En mode « Mémoriser sur cet appareil », la clé est confiée au '
            'stockage sécurisé du système, qui la chiffre.',
        'Sinon, elle n’est gardée qu’en mémoire et disparaît à la fermeture de '
            'l’application.',
        'La clé n’est transmise qu’au fournisseur auquel elle est destinée, et '
            'n’apparaît ni dans les journaux ni dans les exports.',
      ],
    ),
    LegalSection(
      title: 'Modèles importés',
      paragraphs: <String>[
        'Les fichiers GGUF sont copiés dans l’espace de stockage privé de '
            'l’application, inaccessible aux autres applications.',
        'Les supprimer depuis l’écran « Modèles locaux » les efface de '
            'l’appareil.',
      ],
    ),
    LegalSection(
      title: 'Mesure d’audience',
      paragraphs: <String>[
        'L’application n’embarque aucun outil de statistiques, de suivi '
            'publicitaire ou de rapport d’incident. Aucun compte n’est '
            'demandé, et rien n’identifie ton appareil.',
      ],
    ),
    LegalSection(
      title: 'Permissions',
      paragraphs: <String>[
        'Deux permissions seulement sont déclarées. L’accès à Internet ne sert '
            'qu’à joindre le fournisseur d’API que tu configures, pour la '
            'réponse comme pour la liste de ses modèles : sans API '
            'personnelle, l’application ne contacte personne.',
        'Le micro sert à la dictée. Il est demandé à la première utilisation, '
            'jamais au lancement, et l’application reste utilisable sans '
            'l’accorder.',
        'Rien d’autre n’est réclamé : ni appareil photo, ni accès au stockage '
            'partagé, ni position, ni contacts. Les photos et les fichiers '
            'passent par les sélecteurs du système, qui n’exigent aucune '
            'permission de la part de l’application.',
      ],
    ),
  ],
);

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          document.title,
          style: TextStyle(color: fox.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
        children: <Widget>[
          Text(
            'Dernière mise à jour : ${document.updatedAt}',
            style: TextStyle(color: fox.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          for (final section in document.sections) ...<Widget>[
            Text(
              section.title,
              style: TextStyle(
                color: fox.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final paragraph in section.paragraphs) ...<Widget>[
              Text(
                paragraph,
                style: TextStyle(
                  color: fox.textPrimary.withValues(alpha: 0.86),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
