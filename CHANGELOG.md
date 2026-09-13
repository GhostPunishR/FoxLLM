# Changelog

Toutes les évolutions importantes de FoxGPT sont documentées dans ce fichier.

## [Non publié]

### Modifications

- le gras et l'italique du Markdown sont rendus : `**réponse**` s'affichait
  avec ses astérisques et sans le gras demandé. Seuls les délimiteurs à
  astérisques sont reconnus — un astérisque pour l'italique, deux pour le
  gras, trois pour les deux —, jamais ceux à tirets bas : `__init__` et
  `nom_de_variable` y perdraient leurs tirets au profit d'un gras jamais
  demandé. Une multiplication, une rangée d'astérisques ou un délimiteur non
  refermé restent du texte, et le code en ligne n'est pas réinterprété ;
- les blocs de code du chat sont colorés : commentaires, chaînes, nombres,
  mots-clés et appels se distinguent, au lieu d'un bloc entier d'une seule
  teinte. La coloration reconnaît une vingtaine de langages d'après celui
  annoncé après les triples accents graves, et retombe sur un jeu commun quand
  il est absent ou inconnu — colorer large ferait passer des identifiants
  ordinaires pour des mots-clés. Les cinq couleurs viennent de la palette et
  gardent un contraste d'au moins 4,5:1 sur le fond des blocs, dans les deux
  déclinaisons ;
- Paramètres → Modèles locaux affiche le modèle en place plutôt que
  « llama.cpp », qui nommait le moteur — information que l'écran des modèles
  donne déjà. Le nom est lu depuis le chemin mémorisé : interroger le moteur
  l'aurait construit, isolate et bibliothèque native compris, pour un
  sous-titre ;
- À propos donne accès au texte intégral de la licence GNU Affero General
  Public License v3, sous laquelle FoxGPT est distribué, et à la page des
  licences tierces que les dépendances imposent de faire figurer dans
  l'application. Le fichier `LICENSE` de la racine est embarqué tel quel :
  deux exemplaires d'une licence finissent toujours par diverger.

### Tests

- tests du découpage syntaxique : rôles reconnus, code reconstitué à
  l'identique, commentaires propres à chaque langage, chaîne non refermée,
  échappements, langage inconnu ;
- contraste WCAG des cinq couleurs de code sur le fond des blocs, et
  vérification qu'aucune ne se confond avec une autre ;
- vérification que le fichier `LICENSE` porte bien le texte officiel de l'AGPL
  v3, clause 13 comprise, et qu'il est déclaré comme ressource ;
- tests du sous-titre des modèles locaux : modèle nommé, absence de modèle,
  stockage illisible.

## [0.1.1] - 2026-09-13

Première mise à jour après la v0.1.0 : démarrage raccourci, conversations et
modèle conservés entre deux lancements, deux déclinaisons de thème, lecture
confortable du code, et une passe de qualité sur le code existant. La suite de
tests passe de 29 à 120 cas.

### Démarrage

- suppression du splash Flutter : l'application ouvre directement l'écran de
  chat. Cet écran n'effectuait aucun préchargement et ajoutait 700 ms d'attente
  purement décorative ;
- le moteur local n'est plus chargé au lancement : l'isolate worker et
  `libfoxgpt_native.so`, qui embarque `llama.cpp`, étaient créés avant le
  premier frame et retardaient d'autant l'apparition de l'interface. Ils sont
  désormais construits à la première utilisation réelle (envoi d'un message,
  ouverture des modèles locaux) ;
- la fenêtre de lancement Android porte le logo FoxGPT sur le fond de la
  déclinaison choisie, au lieu d'une couleur figée. Android la dessine avant
  que le processus démarre et ne peut donc pas lire une préférence Flutter :
  l'application déclare son mode au système via
  `UiModeManager.setApplicationNightMode`, qui teinte le splash dès le
  lancement suivant. Avant Android 12 cette API n'existe pas, la fenêtre de
  lancement suit alors le mode sombre du système ;
- le dernier modèle GGUF utilisé est rouvert automatiquement au premier
  message, au lieu de devoir le recharger à la main à chaque démarrage. Il
  n'est pas ouvert au lancement, ce qui retarderait l'affichage du chat de
  plusieurs secondes.

### Interface du chat

- nouveau logo FoxGPT, partagé par l'écran de lancement, le chat et l'icône
  Android. Le tracé précédent du chat était polygonal ; le nouveau est fourni
  en 1x, 2x et 3x pour rester net aux petites tailles ;
- les boutons du haut forment une barre opaque : le fil de messages s'arrête
  dessous au lieu de défiler derrière eux, où le texte devenait illisible ;
- les réponses sont affichées en Markdown plutôt qu'en texte brut. Chaque bloc
  de code annonce son langage, se copie d'un bouton et défile à l'horizontale
  sans repli au milieu d'une ligne ; le code en ligne est mis en valeur sans
  ses accents graves. Un bloc encore ouvert s'affiche déjà comme tel pendant le
  streaming ;
- le menu « + » du composer propose de joindre un fichier texte ou du code, lu
  et inséré dans le message en bloc annoté. Photos et caméra y figurent,
  signalées comme dépendantes d'un modèle multimodal, qu'aucun backend ne sait
  lire aujourd'hui. « Modèles locaux » quitte ce menu : sa place est dans les
  Paramètres ;
- une conversation peut être renommée ou supprimée depuis le menu latéral, via
  le bouton « … » ou un appui long ; la suppression demande confirmation,
  puisque l'historique est désormais conservé sur l'appareil ;
- l'historique des conversations est enregistré dans le stockage privé de
  l'application et rechargé au lancement suivant ; l'écriture passe par un
  fichier temporaire renommé, pour qu'une fermeture brutale ne laisse pas un
  historique tronqué.

### Paramètres

- Apparence propose deux déclinaisons aux couleurs du renard, « Clair renard »
  et « Sombre renard », avec aperçu et choix conservé entre deux lancements. La
  déclinaison claire ouvre la liste et s'applique par défaut. Les écrans lisent
  une palette centralisée (`FoxPalette`) au lieu de couleurs codées en dur, et
  les puces d'outils du chat passent du bleu Material à l'orange FoxGPT ;
- nouvelle entrée Personnalisation, à la place de « Confidentialité » qui
  n'était qu'un libellé inerte : l'utilisateur y décrit comment FoxGPT doit
  répondre — ton, longueur, langue, rôle à tenir — avec des modèles prêts à
  l'emploi. Ces consignes ouvrent chaque requête en message système, aussi bien
  vers le moteur local que vers une API personnelle, et ne sont pas figées dans
  les conversations enregistrées ;
- l'entrée « À propos » ouvre un écran donnant accès aux conditions
  d'utilisation et à la politique de confidentialité ;
- suppression du pied de page des Paramètres (le libellé « FoxGPT » et son
  trait orange).

### Corrections

- une API personnelle activée était ignorée : le chat réclamait un modèle GGUF
  alors qu'il aurait dû interroger le fournisseur. L'override du backend était
  posé conditionnellement dans un `ProviderScope` imbriqué, or Riverpod
  n'accepte pas qu'un override apparaisse en cours de route ; les réglages
  étant lus de façon asynchrone, il arrivait toujours trop tard ;
- les écrans « Modèles locaux » et « API personnelle » ignoraient le thème
  choisi : leurs cartes et libellés suivent les rôles Material, qui n'étaient
  pas dérivés de la palette FoxGPT ;
- une lecture lente du stockage revenait par-dessus un choix fait entre-temps :
  un thème sélectionné juste après le lancement pouvait repasser tout seul à
  l'ancien, et les instructions de personnalisation subissaient le même sort ;
- deux appuis rapprochés sur Envoyer lançaient deux générations pendant
  l'ouverture d'un modèle, dont une était perdue : l'indicateur de génération
  n'était levé qu'une fois la requête partie ;
- une erreur de lecture de l'historique empêchait aussi la restauration du
  dernier modèle : les deux sont désormais indépendantes ;
- renommer une conversation touchait le champ de texte après sa libération,
  pendant l'animation de fermeture du dialogue ;
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
- tous les rôles de surface, de contour et de texte du `ColorScheme` dérivent
  de la palette : un écran Material suit le thème sans réglage par widget ;
- l'écran de chat ne se reconstruit plus entièrement à chaque frappe : seul le
  bouton d'envoi observe le brouillon ;
- le défilement automatique n'empile plus un post-frame callback et une
  animation par token pendant le streaming.

### Tests et intégration continue

- couverture de l'envoi d'un message : rendu, streaming, historique transmis au
  backend, bouton Arrêter, erreur de génération, réponse vide et rechargement
  du modèle mémorisé ;
- tests du découpage Markdown, du bouton de copie et du rendu d'un bloc encore
  ouvert ;
- tests de la barre du haut : le fil de messages ne recouvre jamais les boutons,
  encoche comprise ;
- tests des pièces jointes : refus d'un binaire, d'un fichier trop volumineux
  ou vide, insertion dans le brouillon ;
- tests de la personnalisation : relecture, troncature, message système en tête
  de requête et absent des conversations enregistrées ;
- tests du thème : contraste WCAG des deux palettes, ordre d'affichage, défaut
  clair, et déclaration du mode au système pour le splash ;
- tests de persistance des conversations, de renommage et de suppression ;
- tests du socle HTTP partagé : lecture SSE, erreurs HTTP, absence de clé API ;
- tests d'import GGUF concurrent et de libération d'un nom réservé ;
- la CI produit aussi un APK release : le mode debug s'exécute en JIT et ne
  reflète pas les performances réelles de démarrage ;
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
