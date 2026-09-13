// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';

import '../../core/theme/fox_palette.dart';

/// Version de l'application, tenue en phase avec `pubspec.yaml` par un test.
const foxGptVersion = '0.1.1';

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
        'FoxGPT est un client de discussion qui exécute des modèles de langage '
            'directement sur ton téléphone, ou qui contacte un fournisseur '
            'distant avec une clé API que tu fournis toi-même.',
        'Utiliser l’application vaut acceptation des présentes conditions.',
      ],
    ),
    LegalSection(
      title: 'Clés API et fournisseurs tiers',
      paragraphs: <String>[
        'Le mode « API personnelle » utilise une clé que tu obtiens auprès du '
            'fournisseur de ton choix. FoxGPT ne revend aucun accès et '
            'n’intervient pas dans la relation entre toi et ce fournisseur.',
        'Tu restes seul responsable de cette clé, des coûts facturés par le '
            'fournisseur, et du respect des conditions de ce dernier.',
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
        'FoxGPT ne dispose d’aucun serveur. L’application ne collecte, ne '
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
            'publicitaire ou de rapport d’incident.',
        'La seule permission demandée est l’accès à Internet, utilisé '
            'uniquement pour joindre le fournisseur d’API que tu configures.',
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
