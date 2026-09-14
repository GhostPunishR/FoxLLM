# Changelog

Toutes les évolutions importantes de FoxLLM sont documentées dans ce fichier.

## [Non publié]

### Ajouts

- **barre d'actions sous chaque réponse terminée** : copier, noter, lire à voix
  haute, partager, et un menu pour régénérer la réponse ou en sélectionner le
  texte. Elle n'apparaît qu'une fois la réponse complète : pendant la
  génération, il n'y a rien de complet à copier, à lire ni à partager ;
- **sources citées, affichées à droite de cette barre**. Quand le mode
  Recherche est actif, OpenAI et Gemini indiquent les pages consultées :
  l'API Responses au fil du texte, Gemini dans ses métadonnées d'ancrage. Les
  deux formats sont relevés, dédoublonnés dans leur ordre d'apparition, et
  conservés avec la conversation. Un moteur local ou un fournisseur sans outil
  de recherche n'affiche rien, faute d'avoir quoi que ce soit à citer ;
- **modification d'un message envoyé** : un appui long ouvre Copier,
  Sélectionner le texte, Modifier le message et Partager. La modification se
  fait sur place, à la ligne du message ; l'envoi remplace la suite du fil par
  la nouvelle réponse. Le brouillon en cours d'écriture dans le composer reste
  intact ;
- la lecture à voix haute et le partage passent par les services d'Android
  (`flutter_tts`, `share_plus`). Comme pour la dictée, FoxLLM ne transporte
  aucun son et n'en conserve aucun.

### Notes

- le pouce haut et le pouce bas restent **sur l'appareil** : FoxLLM n'a pas de
  serveur à qui transmettre un avis, et n'en aura pas. C'est un repère
  personnel, conservé avec la conversation, pour retrouver une bonne réponse
  dans un long fil.

### Corrections

- **accumulation de sauvegardes sur stockage lent** : le regroupement espaçait
  les écritures mais chaque déclenchement partait sans attendre le précédent.
  Le magasin sérialisait bien les écritures physiques, mais les instantanés
  s'empilaient dans sa file : quatre demandes pendant une écriture lente
  produisaient quatre copies de tout l'historique. Le regroupeur ne tient plus
  qu'une écriture à la fois ; ce qui change pendant celle-ci marque l'état sans
  prendre d'instantané, et repart groupé à son retour, avec l'état d'alors. Une
  demande explicite pendant une écriture n'est pas perdue, et les simples
  fragments gardent leur cadence au lieu d'enchaîner les écritures ;
- **`ref` lu après destruction de l'écran** : quand une copie de pièce jointe
  aboutissait après la fermeture de l'écran, le nettoyage passait encore par
  `ref`, qui lève une exception une fois le widget démonté. Le fichier restait
  alors sur l'appareil sans que rien n'y renvoie. Le magasin et le sélecteur
  sont saisis avant la première attente, tant que `ref` est lisible. Les deux
  branches d'erreur de la sélection et de l'enregistrement étaient exposées de
  la même façon : `_showSnack` abandonne désormais le message quand l'écran a
  disparu, au lieu d'empiler une exception par-dessus l'erreur d'origine.

### Corrections

- **moteur natif** : la boucle de décodage confiait au batch un pointeur vers
  un jeton déclaré dans le corps de la boucle. `llama_batch_get_one` ne copie
  pas : `llama_decode` relisait donc au tour suivant une variable sortie de sa
  portée. Le jeton vit désormais hors de la boucle. Reproduit puis vérifié
  avec AddressSanitizer, llama.cpp b10903 compilé instrumenté et une vraie
  génération de vingt-quatre jetons sur un GGUF de test ;
- **clé API** : une clé enregistrée n'est plus réutilisée quand l'adresse du
  serveur change. Le fournisseur « Personnalisé » garde le même identifiant
  d'une base URL à l'autre, si bien que la clé du serveur précédent pouvait
  partir vers le nouveau, y compris à la récupération des modèles, avant tout
  enregistrement. La réutilisation dépend maintenant du fournisseur **et** du
  destinataire, c'est-à-dire schéma, hôte, port effectif et chemin. Une
  réécriture équivalente de l'URL ne change rien ; changer d'hôte, de port, de
  schéma ou de chemin impose de ressaisir la clé, parce qu'une passerelle peut
  router chaque préfixe vers un fournisseur différent. Les installations
  existantes conservent la leur ;
- **envoi pendant le chargement d'un modèle** : l'identité de l'envoi est prise
  avant la première attente et vérifiée après chacune. Ouvrir un autre fil ou
  en créer un pendant l'ouverture du GGUF faisait repartir l'ancien texte avec
  le nouvel historique ; l'envoi devenu obsolète est abandonné sans toucher au
  brouillon du fil courant ;
- **pièces jointes** : elles suivent le brouillon. Changer de conversation
  effaçait le texte mais gardait les pièces jointes, qui accompagnaient alors
  un message d'un autre fil. Les copies devenues inutiles sont effacées, jamais
  celles d'un message enregistré, et une sélection de fichier qui aboutit après
  le changement de fil ne s'y invite plus ;
- **enregistrement de l'historique** : les échecs d'écriture ne sont plus
  avalés. `save()` remonte l'erreur de son écriture à l'appelant, la file
  continue de servir les suivantes, et l'utilisateur est averti une fois par
  panne plutôt qu'à chaque fragment.

### Performances

- l'historique n'est plus réécrit intégralement à chaque fragment reçu. Les
  enregistrements intermédiaires sont regroupés, au plus un toutes les deux
  secondes, et l'état est relu au moment d'écrire plutôt que figé à la
  planification : une écriture différée ne peut donc pas ressusciter une
  conversation supprimée entre-temps. Fin de génération, arrêt, erreur,
  navigation, renommage, suppression et fermeture de l'écran écrivent tous
  sans attendre.

### Tests

- 235 à 266 cas. Origine des clés API et migration des réglages, regroupement
  des écritures et propagation des échecs, envoi annulé par un changement de
  fil, pièces jointes liées au brouillon. Les tests d'écran ont été vérifiés
  contre le code d'origine : ils échouent bien là où le correctif manque ;
- `packages/foxllm_native/tool/asan/run.sh` rejoue la vérification native :
  llama.cpp et le moteur compilés sous AddressSanitizer, un GGUF de test
  fabriqué sur place, et une génération réelle. Hors intégration continue, la
  compilation instrumentée durant une dizaine de minutes.

### Corrections

- le modèle local ne tient plus les deux rôles de la conversation. Le prompt
  était assemblé à la main dans un format `<|rôle|>` qui n'appartient à aucun
  modèle : faute de reconnaître la fin de son tour, le modèle enchaînait en
  écrivant la réplique de l'utilisateur, puis la suivante, jusqu'à la limite de
  jetons, balises comprises. Le prompt est désormais construit avec le gabarit
  de conversation inscrit dans le GGUF, celui-là même pour lequel le modèle a
  été entraîné : il termine sur son jeton de fin, et `llama.cpp` arrête la
  boucle ;
- un filet de sécurité coupe malgré tout la réponse au premier marqueur de fin
  de tour, pour les GGUF dont le gabarit est inexact ou qui écrivent leurs
  balises en texte ordinaire plutôt qu'en jetons spéciaux. Douze marqueurs des
  familles ChatML, Llama 3, Phi et Mistral sont reconnus, y compris arrivés en
  plusieurs morceaux, sans retarder l'affichage du texte ordinaire ;
- l'ABI native passe en 0.4.0 avec l'export `foxllm_engine_apply_chat_template`,
  dont la CI Android vérifie la présence dans la bibliothèque livrée. Un GGUF
  sans gabarit, ou avec un gabarit que `llama.cpp` ne sait pas appliquer, se
  replie sur ChatML plutôt que d'échouer.

### Ajouts

- site public dans `docs/`, prêt à être publié par GitHub Pages : page
  d'accueil, conditions d'utilisation et politique de confidentialité. Le site
  reprend la palette de l'application et suit lui aussi le thème du visiteur,
  clair ou sombre, avec une bascule manuelle ;
- la page d'accueil montre les deux trajets de données (modèle local, où rien
  ne quitte l'appareil, et API personnelle, où la requête va directement au
  fournisseur), un registre de ce que l'application manipule et de l'endroit
  où cela atterrit, les fournisseurs pris en charge, les étapes d'installation
  et la licence ;
- la politique de confidentialité obtient ainsi une adresse publique, telle que
  la demandent les magasins d'applications ;
- un test vérifie que `conditions.html` et `confidentialite.html` reprennent mot
  pour mot les textes de `legal_documents.dart`, que les liens internes du site
  pointent vers des fichiers existants, et que la version annoncée est celle de
  l'application. La suite passe de 216 à 222 cas.

### Modifications

- `chat_screen.dart` passait deux mille lignes : le widget d'écran, la barre du
  haut, le fil des messages, la zone de saisie et le menu latéral dans un seul
  fichier. Il est découpé en `chat_top_bar.dart`, `chat_messages.dart`,
  `chat_composer.dart` et `chat_drawer.dart`, rattachés par `part` à la même
  bibliothèque : les widgets gardent leur nom, leur portée privée et leur accès
  à l'état de l'écran, seul le rangement change ;
- les imports sont remis en ordre alphabétique, `dart:`, paquets tiers puis
  FoxLLM ;
- l'arborescence du code est refaite. `lib/core/llm/` ramassait dix-huit
  fichiers mêlant le contrat des moteurs, les modèles de données et les
  réglages ; `lib/features/chat/` mêlait écrans et stockage. Désormais `core/`
  ne garde que les briques transverses (`storage/`, `theme/`, `ui/`), `llm/`
  regroupe les moteurs (`model/`, `backend/`, `personal_api/`) sans le moindre
  widget, et chaque écran garde ses dépendances sous `features/`. Le dossier
  `test/` suit la même arborescence, et `test/repository/` rassemble les
  contrôles qui portent sur le dépôt lui-même ;
- la version, le titulaire des droits et l'adresse du dépôt quittent
  `legal_documents.dart` pour `core/app_info.dart` : ces constantes ne sont pas
  des textes juridiques ;
- les imports internes s'écrivent en `package:foxllm/...` au lieu de chemins
  relatifs. Un fichier déplacé ne casse plus les fichiers qui l'utilisent ;
- README repris en page de présentation : logo, badges Dart, Flutter, C++,
  Android et licence, les deux moteurs, les fonctions, l'installation, la
  structure du code, et les vérifications d'intégration continue rassemblées
  dans un tableau. La longue liste d'état, qui recopiait le journal des
  versions, disparaît ;
- le tiret cadratin est proscrit dans le dépôt, ponctuation française
  ordinaire à la place. Un test le vérifie sur les fichiers que FoxLLM écrit
  lui-même, `LICENSE` excepté puisque son texte ne se retouche pas ;
- `docs/ARCHITECTURE.md` est supprimé : le site le remplace pour le lecteur, et
  le README garde le schéma des couches et l'invariant d'accès au moteur natif.
  Les points d'implémentation qui expliquent le comportement visible (isolate
  worker, arrêt par drapeau atomique, décodage UTF-8 incrémental, import GGUF
  par flux, socle HTTP partagé) sont repris dans la section « Sous le capot »
  du site ;
- l'application s'appelle désormais **FoxLLM**. « GPT » n'est pas une marque
  enregistrée, l'office américain ayant refusé le dépôt en jugeant le sigle
  descriptif, mais les règles de marque d'OpenAI demandent de ne pas
  l'employer dans le nom d'un produit tiers, et les magasins d'applications
  ont déjà fait retirer des applications pour ce motif. Le renommage a lieu
  avant toute publication : l'`applicationId` Android est figé dès la première
  mise en ligne, et en changer ensuite créerait une application distincte, sans
  mise à jour possible pour ceux qui auraient installé la précédente ;
- le renommage couvre le nom visible, l'identifiant Android
  (`com.ghostpunishr.foxllm`), les deux paquets Dart, la bibliothèque native
  (`libfoxllm_native.so`) et ses symboles C, les classes, les clés de stockage
  et la documentation. Les noms bâtis sur le renard seul (palette, thèmes,
  logo) sont inchangés : seul le sigle devait partir.

## [0.1.2] - 2026-09-13

Les quatre actions du composer deviennent réelles (pièces jointes, réflexion,
recherche web et dictée), les réponses s'affichent en Markdown complet, et
FoxLLM déclare sa licence. La suite de tests passe de 120 à 216 cas.

### Composer

- le menu « + » joint de vraies pièces jointes : un fichier, une photo de la
  galerie ou une prise de vue. Elles apparaissent dans le fil comme pièces
  jointes (aperçu pour une image, carte nommée pour un fichier) au lieu de
  déverser le texte du fichier dans le message. Une copie est rangée dans
  l'espace privé de l'application, ce qui permet de les retrouver en rouvrant
  la conversation, et elle est effacée avec elle ;
- les images partent aux API personnelles au format multimodal : morceaux
  `image_url` côté OpenAI, `inline_data` côté Gemini. Le moteur local ne lit
  pas les images et le dit avant d'envoyer, en nommant la pièce jointe ;
- « Réflexion » et « Rechercher » deviennent des interrupteurs : leur aplat dit
  lequel est actif, et le choix est conservé entre deux lancements. Réflexion
  ajoute une consigne de raisonnement aux instructions du modèle et élargit la
  marge de génération, sans quoi la conclusion serait coupée ; elle vaut pour
  tous les moteurs. Recherche active l'outil intégré du fournisseur ; ceux qui
  n'en ont pas le disent, plutôt que de laisser croire à une réponse sourcée ;
- la dictée vocale écrit la parole dans le champ, au fil des mots. Le bouton se
  maintient, comme l'annonçait déjà le champ de saisie, et reste offert même
  une fois le message commencé : dicter la fin d'une phrase est le cas le plus
  courant. Le texte reste modifiable avant envoi, rien ne part tout seul, et
  l'accès au micro n'est demandé qu'à la première dictée.

### Réponses

- le Markdown est rendu : titres dimensionnés selon leur niveau, listes à puces
  ou numérotées avec leur imbrication, traits de séparation, gras et italique.
  `### Titre` affichait ses dièses et `**réponse**` ses astérisques ;
- seuls les délimiteurs à astérisques sont reconnus, jamais ceux à tirets bas :
  `__init__` et `nom_de_variable` y perdraient les leurs. Une multiplication,
  une rangée d'astérisques ou un délimiteur non refermé restent du texte ;
- les liens `[texte](https://…)` s'ouvrent dans le navigateur du système. Seuls
  `http` et `https` sont acceptés : une réponse de modèle est du texte non
  vérifié, et tout autre schéma s'affiche tel qu'écrit plutôt que de masquer
  une destination sous un libellé ;
- les blocs de code sont colorés : commentaires, chaînes, nombres, mots-clés et
  appels se distinguent. Une vingtaine de langages sont reconnus d'après celui
  annoncé après les triples accents graves, avec repli sur un jeu commun quand
  il est absent ou inconnu : colorer large ferait passer des identifiants
  ordinaires pour des mots-clés. Les cinq couleurs viennent de la palette et
  gardent un contraste d'au moins 4,5:1 sur le fond des blocs.

### Fournisseurs

- OpenAI passe à son API Responses : c'est le seul format où ses outils
  intégrés existent, la recherche web comprise. Les messages y deviennent des
  éléments d'`input`, la consigne système un champ `instructions`, et la
  réponse arrive en évènements typés dont seuls les fragments de texte sont
  retenus. Les autres fournisseurs gardent `chat/completions`, le format
  qu'ils imitent.

### Paramètres et licence

- Paramètres → Modèles locaux affiche le modèle en place plutôt que
  « llama.cpp », qui nommait le moteur, information que l'écran des modèles
  donne déjà. Le nom est lu depuis le chemin mémorisé : interroger le moteur
  l'aurait construit, isolate et bibliothèque native compris, pour un
  sous-titre ;
- FoxLLM déclare sa licence : le texte intégral de la GNU Affero General Public
  License v3 est consultable dans À propos, chaque fichier source porte la
  notice sous forme d'identifiant SPDX (`AGPL-3.0-only`), et le README la
  notice de copyright complète. Le fichier `LICENSE` est celui de la FSF mot
  pour mot : la ligne de son annexe est un modèle à recopier dans les fichiers
  du programme, pas un champ à remplir ;
- À propos donne aussi l'adresse du code source et la page des licences
  tierces : l'AGPL demande que celui qui reçoit le programme puisse obtenir son
  code, encore faut-il qu'il sache où ;
- la politique de confidentialité couvre la dictée : FoxLLM ne transporte aucun
  son, mais le service de reconnaissance d'Android peut traiter l'audio sur
  l'appareil ou l'envoyer à ses propres serveurs selon les paquets de langue
  installés.

### Tests

- pièces jointes : copie rangée et relue, noms identiques sans écrasement,
  texte joint à la requête, image transformée en morceau multimodal, refus
  expliqué d'un binaire ou d'une image sur un moteur sans vision ;
- modes du composer : bascule et persistance, consigne et marge de réflexion,
  outil de recherche envoyé seulement quand le mode est actif, envoi refusé
  quand le moteur ne sait pas chercher ;
- dictée : parole écrite au fil des mots, ajout à un brouillon déjà saisi,
  micro refusé, appareil sans reconnaissance vocale ;
- API Responses : point d'entrée, champ `instructions`, rôles de l'historique,
  `max_output_tokens`, outil `web_search`, morceaux d'image, lecture du flux
  d'évènements et routage du fournisseur ;
- Markdown : découpage en blocs, gras et italique, liens et schémas refusés,
  découpage syntaxique du code et contraste WCAG de ses cinq couleurs ;
- licence : texte officiel de l'AGPL v3 clause 13 comprise, ressource
  réellement embarquée, et notice présente dans chaque fichier source.

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
  `libfoxllm_native.so`, qui embarque `llama.cpp`, étaient créés avant le
  premier frame et retardaient d'autant l'apparition de l'interface. Ils sont
  désormais construits à la première utilisation réelle (envoi d'un message,
  ouverture des modèles locaux) ;
- la fenêtre de lancement Android porte le logo FoxLLM sur le fond de la
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

- nouveau logo FoxLLM, partagé par l'écran de lancement, le chat et l'icône
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
  les puces d'outils du chat passent du bleu Material à l'orange FoxLLM ;
- nouvelle entrée Personnalisation, à la place de « Confidentialité » qui
  n'était qu'un libellé inerte : l'utilisateur y décrit comment FoxLLM doit
  répondre (ton, longueur, langue, rôle à tenir) avec des modèles prêts à
  l'emploi. Ces consignes ouvrent chaque requête en message système, aussi bien
  vers le moteur local que vers une API personnelle, et ne sont pas figées dans
  les conversations enregistrées ;
- l'entrée « À propos » ouvre un écran donnant accès aux conditions
  d'utilisation et à la politique de confidentialité ;
- suppression du pied de page des Paramètres (le libellé « FoxLLM » et son
  trait orange).

### Corrections

- une API personnelle activée était ignorée : le chat réclamait un modèle GGUF
  alors qu'il aurait dû interroger le fournisseur. L'override du backend était
  posé conditionnellement dans un `ProviderScope` imbriqué, or Riverpod
  n'accepte pas qu'un override apparaisse en cours de route ; les réglages
  étant lus de façon asynchrone, il arrivait toujours trop tard ;
- les écrans « Modèles locaux » et « API personnelle » ignoraient le thème
  choisi : leurs cartes et libellés suivent les rôles Material, qui n'étaient
  pas dérivés de la palette FoxLLM ;
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

Première version fonctionnelle de FoxLLM pour Android, avec exécution locale de modèles GGUF et prise en charge d'API personnelles BYOK.

### Interface et expérience utilisateur

- écran de chat FoxLLM utilisé comme écran d'accueil principal ;
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

### Identité visuelle FoxLLM

- nouveau logo renard orange dérivé directement de l'image de référence FoxLLM ;
- logo vectoriel commun utilisé dans le chat, le splash et les ressources Android ;
- icône APK sur fond blanc ;
- icône adaptive et icône ronde Android ;
- splash natif Android blanc avec le renard FoxLLM ;
- splash Flutter avec le même branding et une barre de chargement orange ;
- transition du splash vers le chat sans flash blanc parasite.

### Moteur local GGUF

- intégration réelle de `llama.cpp` pour Android arm64 ;
- version `llama.cpp` b10903 épinglée au commit `481c65f091f74c5e7089dd0a3a1cc6b50cced31e` ;
- cible Android arm64 / API 28+ ;
- package FFI `foxllm_native` avec ABI C stable ;
- contrat Dart commun `LlmBackend` pour les backends locaux et distants ;
- backend local `LocalLlmBackend` ;
- exécution des appels natifs bloquants dans un isolate worker longue durée ;
- chargement et déchargement réels de modèles GGUF ;
- sélection d'un fichier `.gguf` avec le picker système Android ;
- import des modèles dans le stockage privé de FoxLLM avec progression ;
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
- choix du modèle laissé à l'utilisateur, sans modèle imposé ou hardcodé par FoxLLM ;
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

- aucune clé API hardcodée dans FoxLLM ;
- aucune clé envoyée vers un serveur FoxLLM ;
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
