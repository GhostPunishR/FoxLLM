# Changelog

Toutes les évolutions importantes de FoxGPT sont documentées dans ce fichier.

## [Non publié]

Passe de qualité sur le code existant, plus la suppression du splash Flutter
demandée séparément. En dehors des points listés ci-dessous, aucun comportement
n'est volontairement modifié.

### Modifications

- suppression du splash Flutter : l'application ouvre directement l'écran de
  chat. Cet écran n'effectuait aucun préchargement et ajoutait 700 ms d'attente
  purement décorative ;
- nouveau logo FoxGPT, partagé par l'écran de lancement, le chat et l'icône
  Android. Le tracé précédent du chat était polygonal ; le nouveau est fourni
  en 1x, 2x et 3x pour rester net aux petites tailles ;
- la fenêtre de lancement Android affiche ce logo sur le fond du chat
  (`#0B0B0B`) au lieu du renard sur blanc, donc sans rupture visuelle avec
  l'interface qui suit. Le démarrage du moteur Flutter reste visible — il ne
  peut pas être supprimé — mais il n'affiche plus un écran d'une autre couleur.

- le moteur local n'est plus chargé au lancement : l'isolate worker et
  `libfoxgpt_native.so`, qui embarque `llama.cpp`, n'étaient créés qu'à
  l'affichage du chat mais avant le premier frame, retardant d'autant
  l'apparition de l'interface. Ils sont désormais construits à la première
  utilisation réelle (envoi d'un message, ouverture des modèles locaux).

- Paramètres → Apparence propose deux déclinaisons aux couleurs du renard,
  « Sombre renard » et « Clair renard », avec aperçu et choix conservé entre
  deux lancements. Les écrans lisent désormais une palette centralisée
  (`FoxPalette`) au lieu de couleurs codées en dur, et les puces d'outils du
  chat passent du bleu Material à l'orange FoxGPT ;
- l'entrée « À propos » des Paramètres ouvre désormais un écran donnant accès
  aux conditions d'utilisation et à la politique de confidentialité ;
- suppression du pied de page des Paramètres (le libellé « FoxGPT » et son
  trait orange).

- une conversation peut être renommée ou supprimée depuis le menu latéral,
  via le bouton « … » ou un appui long ; la suppression demande confirmation,
  puisque l'historique est désormais conservé sur l'appareil ;
- l'historique des conversations est enregistré dans le stockage privé de
  l'application et rechargé au lancement suivant ; l'écriture passe par un
  fichier temporaire renommé, pour qu'une fermeture brutale ne laisse pas un
  historique tronqué ;
- le dernier modèle GGUF utilisé est mémorisé et rouvert automatiquement au
  premier message, au lieu de devoir le recharger à la main à chaque
  démarrage. Il n'est pas ouvert au lancement, ce qui retarderait l'affichage
  du chat de plusieurs secondes.

### Corrections

- deux imports GGUF du même nom lancés en parallèle ne s'écrasent plus : la
  destination est réservée avant l'écriture, alors que la vérification
  d'existence laissait les deux imports viser le même fichier ;
- quitter l'écran « API personnelle » pendant un test de connexion ne déclenche
  plus `setState()` après `dispose()` ;
- l'enregistrement d'une API personnelle ne touche plus les contrôleurs de
  texte après le démontage de l'écran, ce qui levait une exception aussitôt
  avalée et masquait un enregistrement pourtant réussi ;
- une Base URL comportant plusieurs barres obliques finales ne produit plus
  d'URL à double séparateur.

### Qualité interne

- backends OpenAI-compatible et Gemini construits sur un socle commun
  `HttpStreamingBackend` : annulation, fermeture du client HTTP, lecture SSE et
  cycle de vie `stop()`/`dispose()` ne sont plus dupliqués entre fournisseurs ;
- une seule exception HTTP distante, `PersonalApiHttpException` ; le doublon
  `HttpException`, qui masquait en plus la classe homonyme de `dart:io`, est
  supprimé ;
- normalisation de Base URL factorisée en un seul point ;
- l'écran de chat ne se reconstruit plus entièrement à chaque frappe : seul le
  bouton d'envoi observe désormais le brouillon ;
- le défilement automatique n'empile plus un post-frame callback et une
  animation par token pendant le streaming.

### Tests

- couverture de l'envoi d'un message : rendu du message, streaming de la
  réponse, historique transmis au backend, bouton Arrêter, erreur de génération
  et réponse vide ;
- tests du socle HTTP partagé : lecture SSE, erreurs HTTP, absence de clé API ;
- tests de l'écran « API personnelle », dont la régression `setState()` après
  `dispose()` ;
- tests d'import GGUF concurrent et de libération d'un nom réservé ;
- tests de normalisation des Base URL ;
- le dossier `test/` est désormais vérifié par le workflow Dart Format.

## [0.1.0] - 2026-09-12

Première version fonctionnelle de FoxGPT pour Android, avec exécution locale de modèles GGUF et prise en charge d'API personnelles BYOK.

### Interface et expérience utilisateur

- écran de chat FoxGPT utilisé comme écran d'accueil principal ;
- interface plein écran immersive sur Android ;
- composer responsive avec actions Réflexion, Rechercher, ajout, voix/envoi et Stop ;
- streaming des réponses directement dans le chat ;
- bouton Stop fonctionnel pour interrompre une génération locale ou distante ;
- création d'une nouvelle conversation depuis l'interface ;
- menu latéral inspiré de l'interface de chat de référence ;
- recherche dans les conversations de la session ;
- regroupement des conversations par période : Aujourd'hui, 7 jours et Plus tôt ;
- titre d'une conversation généré à partir du premier message utilisateur ;
- possibilité de revenir sur une conversation précédente pendant la session ;
- bouton Paramètres placé en bas du menu latéral ;
- écran Paramètres dédié avec accès aux modèles locaux et à l'API personnelle.

### Identité visuelle FoxGPT

- nouveau logo renard orange dérivé directement de l'image de référence FoxGPT ;
- logo vectoriel commun utilisé dans le chat, le splash et les ressources Android ;
- icône APK sur fond blanc ;
- icône adaptive et icône ronde Android ;
- splash natif Android blanc avec le renard FoxGPT ;
- splash Flutter avec le même branding et une barre de chargement orange ;
- transition du splash vers le chat sans flash blanc parasite.

### Moteur local GGUF

- intégration réelle de `llama.cpp` pour Android arm64 ;
- version `llama.cpp` b10903 épinglée au commit `481c65f091f74c5e7089dd0a3a1cc6b50cced31e` ;
- cible Android arm64 / API 28+ ;
- package FFI `foxgpt_native` avec ABI C stable ;
- contrat Dart commun `LlmBackend` pour les backends locaux et distants ;
- backend local `LocalLlmBackend` ;
- exécution des appels natifs bloquants dans un isolate worker longue durée ;
- chargement et déchargement réels de modèles GGUF ;
- sélection d'un fichier `.gguf` avec le picker système Android ;
- import des modèles dans le stockage privé de FoxGPT avec progression ;
- import sécurisé via fichier temporaire `.part` ;
- bibliothèque persistante des modèles importés ;
- gestion des doublons et suppression des modèles ;
- écran de gestion des modèles locaux ;
- affichage de l'état chargé/déchargé ;
- affichage des métadonnées du modèle, dont description, taille et contexte entraîné ;
- streaming token par token C++ → Dart → Flutter ;
- décodage UTF-8 incrémental des morceaux natifs ;
- arrêt coopératif immédiat avec flag atomique ;
- prise en charge des paramètres température, top-p et max tokens ;
- métriques de génération : nombre de tokens, durée et tokens/s ;
- diagnostic du moteur local exécuté via le worker isolate ;
- stubs natifs sur les architectures non prises en charge afin de conserver le mode API et les tests FFI.

### API personnelle / BYOK

- ajout d'une configuration API personnelle directement dans Paramètres ;
- parcours simplifié : Fournisseur → Clé API → Modèles disponibles → Choix du modèle → Test → Utiliser dans le chat ;
- aucune obligation de saisir manuellement une Base URL pour les fournisseurs intégrés ;
- récupération automatique des modèles disponibles avec la clé API quand le fournisseur le permet ;
- choix du modèle laissé à l'utilisateur, sans modèle imposé ou hardcodé par FoxGPT ;
- saisie manuelle de l'identifiant du modèle disponible en secours ;
- mode Personnalisé pour les API compatibles OpenAI avec Base URL manuelle ;
- activation ou désactivation de l'API personnelle pour le chat ;
- bascule automatique vers le backend distant lorsque l'API personnelle est activée ;
- retour au moteur local llama.cpp lorsque l'API personnelle n'est pas utilisée ;
- test de connexion depuis l'application ;
- streaming des réponses distantes ;
- arrêt des requêtes distantes via le même comportement Stop que le moteur local ;
- messages d'erreur API rendus plus lisibles, notamment pour les problèmes de crédits.

### Fournisseurs API intégrés

- OpenAI ;
- Google Gemini ;
- Groq ;
- Mistral AI ;
- OpenRouter ;
- xAI ;
- fournisseur Personnalisé compatible OpenAI.

### Backends distants

- backend OpenAI-compatible avec streaming SSE ;
- prise en charge d'OpenAI, Groq, Mistral AI, OpenRouter et xAI via leurs interfaces compatibles ;
- adaptateur Google Gemini dédié avec `streamGenerateContent` et streaming SSE ;
- récupération des catalogues de modèles des fournisseurs ;
- filtrage des modèles non destinés au chat lorsque les métadonnées du fournisseur le permettent.

### Sécurité des clés API

- aucune clé API hardcodée dans FoxGPT ;
- aucune clé envoyée vers un serveur FoxGPT ;
- communication directe téléphone → fournisseur ;
- stockage sécurisé des clés sur l'appareil via `flutter_secure_storage` ;
- option session uniquement pour ne pas persister la clé ;
- suppression explicite d'une clé enregistrée ;
- effacement du champ de clé lors d'un changement de fournisseur afin d'éviter son envoi accidentel au mauvais service ;
- HTTPS obligatoire pour les fournisseurs Internet ;
- HTTP autorisé uniquement pour localhost et les réseaux privés en mode personnalisé.

### Tests et intégration continue

- workflow Dart Format ;
- workflow Flutter Analyze ;
- workflow Flutter Tests ;
- workflow Native Dart Analyze ;
- workflow C++ Compile ;
- workflow FFI Smoke ;
- workflow Android Build ;
- smoke tests du cycle de vie du worker natif ;
- tests du streaming et de l'annulation ;
- tests de configuration BYOK ;
- tests de résolution des fournisseurs et de leurs URLs ;
- tests de découverte des modèles ;
- tests du streaming Gemini ;
- tests de l'interface de splash, du menu latéral et de l'ouverture des Paramètres ;
- construction d'un APK Android arm64 en CI ;
- vérification automatique que le moteur llama.cpp et les symboles de streaming sont bien embarqués dans l'APK.

### Limitations connues de la v0.1.0

- l'historique des conversations est conservé pendant la session mais n'est pas encore persistant après redémarrage de l'application ;
- le moteur local réel est actuellement ciblé sur Android arm64 / API 28+.
