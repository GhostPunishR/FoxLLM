# Changelog

Toutes les évolutions importantes de FoxLLM sont documentées dans ce fichier.

## [0.1.5] - 2026-09-19

Deux fournisseurs d'API de plus, une relecture des documents légaux, et les
correctifs d'un audit du dépôt. Le réseau ne peut plus attendre indéfiniment,
les erreurs de fournisseur se lisent en français dans le chat, et les copies
de pièces jointes ne s'accumulent plus sans fin. La suite de tests passe de
441 à 531 cas, auxquels s’ajoutent les contrôles C++ du cache.

### Ajouts

- **Anthropic en API personnelle** : l'API Messages, avec son propre
  adaptateur. Elle ne ressemble à aucune des deux autres : la clé voyage dans
  `x-api-key` et non dans `Authorization`, la version de l'API est exigée sur
  chaque appel, les consignes système ont leur propre champ hors des messages,
  et le flux est fait d'évènements nommés. Ni `temperature` ni `top_p` ne sont
  envoyés : les modèles récents d'Anthropic les refusent par une erreur. Une
  réponse coupée par la limite de longueur ou par un refus est signalée comme
  écourtée, comme chez les autres fournisseurs ;
- **DeepSeek en API personnelle**, par le format compatible OpenAI déjà en
  place.

### Modifications

- la liste des fournisseurs est **par ordre alphabétique**, et le restera :
  un contrôle le vérifie plutôt que de compter sur la relecture. « Personnalisé »
  ferme la marche, n'étant pas un fournisseur parmi les autres mais celui qu'on
  choisit quand aucun ne convient ;
- « Google Gemini » devient **Google**, et « Personnalisé (OpenAI-compatible) »
  devient **Personnalisé**. Les messages de l'application suivent, y compris
  celui qui explique quels fournisseurs savent consulter le web ;
- la recherche web n'est plus annoncée par défaut pour tout ce qui n'imite pas
  `chat/completions` : elle est nommée fournisseur par fournisseur. Anthropic a
  bien un outil de recherche, mais FoxLLM ne le déclare pas encore dans ses
  requêtes, et le proposer laisserait attendre des sources qui ne viendraient
  jamais.

### Corrections

- **le réseau pouvait attendre indéfiniment.** Il n'y avait pas un seul délai
  d'expiration dans l'application : un fournisseur qui acceptait la connexion
  puis se taisait laissait le rond tourner pour toujours, sans que rien
  n'indique que plus rien ne viendrait. Trois délais sont posés : l'ouverture
  de la réponse, le silence entre deux fragments d'un flux, et la liste des
  modèles. Celui du flux se recompte à chaque fragment : une réponse peut
  prendre dix minutes tant qu'elle avance, c'est le silence qui est borné ;
- **un battement de cœur suffisait à désarmer ce délai.** Le compte était
  relancé par chaque ligne reçue, or le `: ping` d'OpenRouter et les
  commentaires qu'un proxy intercale pour tenir la connexion ouverte en sont.
  Un fournisseur bloqué derrière un proxy bavard faisait donc tourner le rond
  indéfiniment, ce que ce délai venait précisément d'interdire. Seule une
  charge utile atteste d'un progrès, et seule une charge utile relance
  désormais le compte ;
- **le corps d'une réponse en échec échappait à tout délai.** Celui de la
  réponse s'arrête aux en-têtes : un fournisseur qui annonçait 500 puis se
  taisait en écrivant le détail laissait la lecture attendre sans fin, pour
  une requête déjà perdue. Cette lecture est bornée, et son expiration ne
  coûte que le détail de l'erreur, jamais son signalement ;
- **un modèle encodeur-décodeur au prompt un peu long arrêtait
  l'application.** Ces modèles lisent tout leur prompt d'un seul appel, et
  llama.cpp exige que le lot le tienne en entier : il le vérifie par une
  assertion, donc un arrêt net du processus et non une erreur rendue. Le
  micro-lot restant plafonné à 512 jetons, tout prompt au-dessus tombait.
  Pour ces modèles le lot suit maintenant le prompt ;
- **le chat versait les erreurs brutes dans le bandeau.** Un refus HTTP y
  déversait le corps entier de la réponse, page d'erreur de proxy ou pavé
  JSON compris. La traduction française existait déjà, mais n'était utilisée
  que sur l'écran des réglages : « La clé API est invalide ou a été révoquée »
  plutôt que quatre lignes d'anglais et d'accolades ;
- **les pièces jointes d'une version conservée n'étaient jamais effacées.**
  Supprimer une conversation ne parcourait que le fil visible : les copies
  citées par la seule version conservée restaient sur le disque, sans que
  rien ne puisse plus les rouvrir ni les effacer. Le parcours est désormais
  porté par la conversation elle-même, pour qu'une troisième liste, un jour,
  ne soit pas oubliée à son tour ;
- **au-delà de cent conversations, les plus anciennes disparaissaient en
  silence.** L'historique n'en enregistre que cent : les suivantes restaient
  à l'écran jusqu'à la fermeture, puis s'évanouissaient au lancement suivant
  en laissant leurs pièces jointes derrière elles. Le plafond est maintenant
  tenu en mémoire, et jamais au détriment de la conversation ouverte ;
- **les sources d'une génération abandonnée s'invitaient dans la suivante.**
  Quitter un fil pendant qu'il répond laisse l'ancienne génération se
  terminer après le départ de la nouvelle. Les relevés étant rangés sur le
  moteur, cette retardataire y versait ses sources : le fil ouvert se
  retrouvait avec des sources qu'il n'avait jamais demandées. Ils
  appartiennent désormais à la génération qui les a produits ;
- **un message pouvait fabriquer un faux tour de parole.** Dans le repli
  ChatML, utilisé quand un GGUF ne porte pas de gabarit de conversation, un
  message contenant `<|im_end|>` fermait son propre tour et ouvrait ce qu'il
  voulait derrière : de quoi faire passer une instruction pour une consigne
  système. Les balises sont neutralisées sans rien retirer au texte ;
- **le drapeau d'arrêt natif n'était pas remis à zéro** par la génération en
  flux, contrairement à la génération simple. Le worker s'en chargeait, mais
  faire dépendre la correction d'un appelant discipliné n'est pas une
  garantie : une réponse vide sans erreur pour l'expliquer était au bout.

### Modèles locaux

- **le cache KV est en place.** Le contexte d'inférence était créé puis jeté à
  chaque réponse : toute la conversation était relue depuis le début à chaque
  message, et le coût croissait avec sa longueur. Or une conversation ne fait
  qu'allonger son début, le prompt d'un tour commençant par celui du tour
  précédent. Le contexte est désormais gardé, avec la liste des jetons qu'il a
  lus ; seul ce qui a changé est relu. Un fil qui diverge, par une
  régénération ou une modification, voit la partie devenue fausse retirée du
  cache et relue, jamais réutilisée à tort ;
- **la mémoire n'est pas réservée d'avance pour autant.** Un contexte fixé à
  quelques milliers de jetons coûterait des centaines de mégaoctets qu'un
  téléphone n'a pas. Le contexte suit donc la conversation par doublements :
  assez rare pour que le cache serve entre deux agrandissements, assez souple
  pour qu'une question d'une ligne ne paie pas la mémoire d'un long fil ;
- le prompt se lit par lots de 512 jetons au lieu d'un seul lot de sa taille,
  ce qui borne les tampons de calcul et permet à un long fil de passer.

### Ajouts

- **la vitesse d'écriture s'affiche sous une réponse locale**, en jetons par
  seconde. Le pont natif la mesurait déjà et la jetait. C'est la façon de voir
  l'effet du cache KV, de comparer deux modèles ou de juger d'un réglage, sans
  rien avoir à refaire. Discrète à dessein, et enregistrée avec le message.
  Une réponse distante n'en porte aucune : un fournisseur ne donne pas ce
  compte, et l'inventer serait pire que de se taire ;
- **la recherche web fonctionne chez Anthropic.** L'outil était laissé de côté
  faute d'être déclaré dans les requêtes ; il l'est maintenant, et les sources
  reviennent par les deux chemins qu'Anthropic emploie : les pages consultées
  dès que la recherche aboutit, puis les citations au fil des phrases qu'elles
  appuient. Trois fournisseurs savent donc consulter le web, contre deux.

### Modèles locaux, suite

- **le cache KV tient dans la moitié de la mémoire.** En `q8_0` plutôt qu'en
  `f16`, c'est deux fois plus de conversation gardée à mémoire égale, pour une
  perte de qualité négligeable à huit bits. llama.cpp marque ces réglages
  comme expérimentaux et le cache V quantifié demande l'attention flash : un
  repli sur le cache ordinaire est prévu, pour qu'un téléphone qui la refuse
  garde son moteur local plutôt que de le perdre.

### Accessibilité, suite

- **l'accueil du chat tient à deux fois la taille de texte.** Le bloc de
  bienvenue était posé à 39 % de la hauteur avec une largeur fixe : agrandi,
  il débordait de 194 points et affichait la bande rayée par-dessus l'écran.
  L'espace au-dessus lui cède maintenant du terrain à mesure que le texte
  grandit, sa largeur suit l'écran, et il défile si cela ne suffit pas. Douze
  contrôles vérifient les quatre écrans principaux à une fois et demie, et
  deux fois, la taille ordinaire.

### Blocs de code

- **les couleurs sont celles de GitHub**, thème Primer, clair et sombre. Un
  extrait de code se lit partout ailleurs avec ces teintes : les reprendre
  évite d'avoir à réapprendre ce que veut dire un rouge ou un violet. Les
  douze valeurs sont vérifiées lisibles sur le fond des blocs de FoxLLM, qui
  n'est pas celui de GitHub, et un contrôle les compare une à une au thème
  d'origine ;
- le texte non coloré d'un bloc a désormais son propre rôle : le fil garde la
  chaleur de FoxLLM, le code prend le gris de GitHub.

### Performance et accessibilité

- **la coloration du code était quadratique.** La boucle recopiait tout le
  code restant à chaque caractère : sur un extrait de sept kilooctets, douze
  millions de caractères recopiés par passage. Mesuré avant et après sur le
  même extrait, vingt passages tombent de 107 ms à 7 ms, quinze fois moins.
  Un contrôle compare désormais la forme de la courbe plutôt qu'une vitesse :
  quatre fois plus de code ne doit pas coûter seize fois plus de temps ;
- **le fil était repeint à chaque fragment reçu.** Or afficher un message
  ré-analyse son markdown et recolore son code, pour tous les messages
  visibles : le travail croissait donc avec le carré de la longueur de la
  réponse, sur le fil principal, au moment précis où l'appareil produit la
  suite. Les fragments sont groupés sur cinquante millisecondes, ce qui
  laisse le texte paraître s'écrire. Ce qu'un groupement retient est poussé à
  l'écran à la fin du flux, échec compris : c'est justement après une coupure
  que le texte déjà reçu compte le plus ;
- **les cibles tactiles passent à 48 points.** La barre du haut était à 42, et
  les six boutons sous une réponse à 40, là où Android demande 48 pour ce qui
  se touche. Les dessins gardent leur taille : seule la zone sensible autour
  d'eux s'élargit, et la barre d'actions passe à la ligne plutôt que de
  déborder sur un écran étroit ;
- **le texte tertiaire clair remonte à 4,5 de contraste**, contre 3,36. Il
  sert aux dates de conversation, aux aides de réglage et à la mention de
  copyright, tous en douze ou treize points, où la règle WCAG demande 4,5. Le
  contrôle de palette l'exige désormais pour le texte secondaire comme pour le
  tertiaire, au lieu de se contenter de 3 ;
- **un import de modèle qui échoue dit pourquoi.** Le ménage qui suivait
  l'échec pouvait échouer à son tour sur un disque plein, et remplaçait alors
  la vraie cause par une erreur de suppression.

### Durcissement

- **l'analyseur passe en mode strict** (`strict-casts`, `strict-inference`,
  `strict-raw-types`). Le code relit du JSON en permanence, réponses de
  fournisseurs, historique, réglages : sans ces règles, une valeur `dynamic`
  se glisse dans un type déclaré sans un mot, et la faute ne se voit qu'à
  l'exécution, sur l'appareil de quelqu'un ;
- `pubspec.lock` est ignoré par git, ce qu'il n'était ni d'un côté ni de
  l'autre : chaque `flutter pub get` salissait l'arbre de travail ;
- la version du paquet natif s'aligne sur celle que la bibliothèque annonce.

### Correction d'une régression

- **l'application ne démarrait plus sur certains appareils.** Le correctif de
  mise à l'échelle du texte calculait la largeur du bloc d'accueil par une
  soustraction, sans la borner. Or la première image d'un lancement arrive
  avant que la fenêtre ait ses dimensions, donc avec une largeur nulle : la
  soustraction donnait une largeur négative, qu'un `SizedBox` refuse, et toute
  l'application tombait au démarrage. Le mode immersif allonge encore cet
  instant, le temps que les barres système cèdent la place.
- **aucun test ne pouvait l'attraper** : un banc de test pose toujours une
  taille d'écran, et ne voit donc jamais cette première image sans dimensions.
  Sept contrôles couvrent désormais les tailles qu'un appareil produit
  vraiment : la fenêtre encore vide, le plus petit écran Android courant, un
  écran partagé en hauteur, et l'enchaînement d'un lancement, du rien vers
  l'écran.

### Diagnostic

- **une version de débogage affiche désormais la première erreur**, et non la
  dernière. Quand une construction échoue, Flutter remplace le sous-arbre
  abîmé puis démonte ce qui l'entourait ; ce démontage échoue à son tour, et
  c'est cette seconde erreur, sans rapport avec la cause, qui reste à l'écran.
  On lit une conséquence pendant que la cause défile dans un journal qu'on n'a
  pas. L'écran donne maintenant l'erreur d'origine et le début de sa pile
  d'appels, de quoi nommer un fichier et une ligne depuis un téléphone, sans
  câble ni outil. Il tient sans thème, sans police et sans image, puisqu'il
  doit s'afficher quand tout le reste a échoué. Les versions de distribution
  gardent l'écran discret de Flutter.

### Travaux internes

Rien de visible à l'usage, mais l'écran de chat portait un état de trente-cinq
champs et quatre-vingt-quatre méthodes : de quoi rendre invérifiable ce qui
décide d'effacer un fichier ou d'écrire dans une conversation.

- **le moteur local est enfin exécuté par l'intégration continue.** Aucun
  travail ne chargeait de modèle : l'un ne compilait que le bouchon, l'autre
  ne traversait le pont qu'à vide. Tout ce qui fait le moteur local restait
  donc non vérifié à l'exécution, cache KV compris. Un modèle témoin est
  maintenant construit à chaque fois par un script de deux cents lignes, puis
  le pont est compilé contre la vraie bibliothèque et le cache mis à l'épreuve.

  Le modèle pèse sept cents kilooctets, porte des poids aléatoires et répond
  donc du charabia. C'est sans importance : avec un échantillonnage glouton,
  la réponse ne dépend que du prompt, et un cache correct n'en change pas un
  jeton. Quatre contrôles en découlent : un fil qui s'allonge, un cache cumulé
  sur trois tours, un message modifié en cours de route, et un témoin qui
  vérifie que deux prompts différents donnent bien deux réponses différentes,
  sans quoi les trois premiers ne prouveraient rien. Le tag de llama.cpp est
  lu dans le `CMakeLists` du pont plutôt que recopié, pour qu'une version
  épinglée à deux endroits ne diverge pas ;
- **le pont natif range ses vérifications au même endroit.** Le dépôt porte
  deux paquets Dart, donc deux dossiers `test` : celui de la racine appartient
  à l'application, celui de `packages/foxllm_native` au pont. Ce n'est pas un
  éparpillement mais la règle des paquets Dart, et y déroger empêcherait les
  tests de s'exécuter. En revanche le pont rangeait la moitié des siens dans
  `tool` : le test de fumée FFI et le banc AddressSanitizer rejoignent son
  `test`. Un contrôle refuse désormais qu'une vérification vive ailleurs, et
  qu'un travail d'intégration continue désigne un fichier déplacé ;
- **les deux décisions d'entretien de l'historique** sortent de l'écran :
  laquelle des conversations ne tient plus sous le plafond, et quelles pièces
  jointes plus personne ne cite. Elles ne dépendent que de leurs arguments, et
  douze contrôles les couvrent une à une, y compris la conversation ouverte
  qu'on épargne et les deux objets distincts qui désignent le même fichier ;
- **la règle d'identité d'un fil n'est plus écrite qu'une fois.** Quatre
  copies écrites à la main décidaient si une opération asynchrone avait encore
  le droit d'écrire, et deux d'entre elles étaient volontairement
  différentes : écrire dans une conversation par son identifiant n'exige pas
  qu'elle soit affichée, toucher au fil visible si. La distinction était
  correcte mais implicite, donc recopiable de travers ; elle porte désormais
  deux noms, et un contrôle du dépôt refuse qu'une cinquième copie
  réapparaisse. Trois des défauts les plus coûteux corrigés cette année
  venaient de là ;
- **l'envoi d'un message se lit en cinq phases** au lieu d'une méthode de
  trois cent vingt-sept lignes, qui en fait désormais cent quatre-vingt-quatre.
  La préparation, où rien n'est encore engagé et où tout peut être abandonné
  sans laisser de trace. La validation, à partir de laquelle le fil est
  modifié et chaque sortie doit le remettre d'aplomb. Le flux. Le bilan d'une
  génération terminée. Et la remise d'aplomb après un échec, dont les quatre
  situations deviennent lisibles d'un coup d'œil : du texte reçu ou non, une
  version remplacée ou non ;
- ce découpage a montré qu'une de ces quatre situations était vérifiée dans
  ses effets mais pas dans ce qu'elle dit à l'utilisateur. Une régénération
  qui échoue avant le premier mot remet le fil en place ; le test le
  vérifiait, mais aucun ne vérifiait qu'on le dise. Un rétablissement muet ne
  se distingue pourtant pas d'un oubli.

### Documents légaux

Relecture des conditions d'utilisation et de la politique de confidentialité
face à ce que l'application fait aujourd'hui.

- **une affirmation fausse corrigée** : la politique promettait que « la seule
  permission demandée est l'accès à Internet », alors que le manifeste déclare
  aussi le micro depuis l'arrivée de la dictée, que la politique décrit par
  ailleurs. Les permissions ont maintenant leur propre section, et un contrôle
  compare la liste du manifeste au texte : une permission ajoutée sans un mot
  dans la politique fait échouer la suite ;
- **pièces jointes** : photos, images et fichiers texte n'étaient décrits nulle
  part, alors qu'ils sont recopiés dans le stockage privé et partent chez le
  fournisseur. Une section dit où ils vont, ce que leur suppression efface, et
  qu'un modèle local ne reçoit pas d'image ;
- **recherche web** : une section dit que c'est le fournisseur qui consulte le
  web, que la question lui sert de recherche, et que rien de tel n'a lieu avec
  un modèle local ;
- **copie et partage** : le texte sorti vers le presse-papiers ou vers une
  autre application est annoncé plutôt que passé sous silence ;
- **conditions** : une section « Ce que tu envoies » rappelle la
  responsabilité de l'expéditeur sur les messages et les fichiers joints, et
  déconseille la recherche web pour un échange qu'on veut garder pour soi ;
- les deux pages du site reprennent mot pour mot les textes de l'application,
  comme le vérifie déjà la suite.

## [0.1.4] - 2026-09-14

Correctifs d'un audit mené avant diffusion publique, puis de trois passages de
suivi sur les mêmes points. Dix-neuf défauts confirmés, dont onze pouvaient
perdre ou déplacer des données. La signature de distribution cesse de reposer
sur la clé de développement, et les sauvegardes Android cessent de contredire
la politique de confidentialité. La suite de tests passe de 347 à 441 cas.

### Corrections

- **sauvegarde pendant la relecture de l'historique** : les enregistrements
  étaient permis avant la fin de la relecture, alors que la liste en mémoire
  était encore vide. Un passage en arrière-plan à ce moment remplaçait le
  fichier par cette liste vide, et un premier message envoyé pendant la
  relecture était effacé par son arrivée. Les écritures sont désormais retenues
  jusqu'à la fin de la relecture, sans perdre les demandes reçues entre-temps,
  et les envois l'attendent. Un fichier illisible ne se confond plus avec un
  historique vide : la lecture échoue franchement, plus rien n'est écrit
  par-dessus, et l'utilisateur est averti ;
- **régénération ou modification destructive avant validation** : le fil était
  tronqué et enregistré avant qu'on sache si l'envoi était possible.
  Régénérer sans modèle chargé amputait donc définitivement une conversation
  sans même envoyer la demande. La coupe accompagne maintenant l'envoi et n'a
  lieu qu'une fois celui-ci validé, pièces jointes, citations et évaluations
  des messages conservés comprises ;
- **modification appliquée à une autre conversation** : l'édition n'était
  repérée que par un indice valable pour le fil affiché. Commencer à modifier
  un message dans un fil puis en ouvrir un autre faisait porter le texte saisi
  sur le message de même rang. L'édition est désormais liée à sa conversation
  et à son message, vérifiée à la validation, et abandonnée dès qu'on quitte le
  fil, qu'on ouvre un nouveau chat ou qu'on supprime la conversation ;
- **la file d'attente empruntait le brouillon** : le démarrage d'un message en
  attente remplaçait les pièces jointes du brouillon en cours d'écriture, et le
  message quittait la file avant qu'on sache si sa préparation aboutirait.
  Chaque envoi porte maintenant son propre objet figé, texte, pièces jointes et
  fil de destination ensemble. Un envoi refusé revient en tête de file plutôt
  que d'être perdu, sans réessai automatique ;
- **échecs ignorés dans le flux OpenAI** : une réponse acceptée en HTTP 200
  peut ensuite annoncer son échec par un évènement `error` ou
  `response.failed`. Le filtrage ne gardant que le texte les laissait passer,
  et l'échec se terminait comme une réponse vide mais réussie. Les deux formes
  sont désormais traitées, avec le message du fournisseur. Une réponse écourtée
  est distinguée d'une erreur, le texte partiel est conservé, une annulation
  volontaire n'est plus présentée comme une panne, et une réponse en échec
  n'enchaîne plus la file comme si elle avait abouti ;
- **l'arrêt vocal n'annulait pas une initialisation en cours** : la lecture
  partait malgré un arrêt survenu pendant la préparation de la voix, et le
  micro s'ouvrait après que l'utilisateur avait relâché le bouton, parce que
  l'arrêt ne trouvait rien à arrêter tant que l'écoute n'avait pas commencé.
  Chaque démarrage est maintenant identifié et invalidé par un arrêt, une
  nouvelle demande ou la fermeture de l'écran, y compris quand l'opération
  native aboutit trop tard ;
- **sauvegardes Android** : le manifeste ne fixait aucune règle, et Android
  sauvegarde par défaut tout le stockage privé d'une application vers le Google
  Drive de son utilisateur. L'historique, les pièces jointes et les réglages
  partaient donc là où la politique de confidentialité affirmait qu'ils
  n'allaient jamais. La sauvegarde cloud et le transfert entre appareils sont
  refusés, pour Android 12 et suivants comme pour les versions antérieures, et
  la politique annonce la contrepartie : changer de téléphone ne reprend pas
  les conversations ;
- **la voix continuait après le message** : quitter un fil pendant une lecture
  à voix haute n'arrêtait pas la synthèse d'Android. La bulle disparaissait,
  mais la voix poursuivait, et plus rien ne permettait de l'interrompre :
  le bouton qui l'aurait fait était parti avec le message. La lecture cesse
  désormais dès que le message lu quitte l'écran, par les quatre chemins qui
  l'y font disparaître : nouveau chat, ouverture d'un autre fil, suppression
  du fil affiché, et régénération ou modification qui remplace la réponse.
  Écouter une réponse plus haute dans le fil pendant qu'on en régénère une
  autre ne l'interrompt pas, faute de raison ;
- **bouton de lecture à voix haute bloqué** : une fois la réponse lue en
  entier, le bouton restait allumé comme si la voix parlait encore. L'écran
  gardait sa propre copie de l'état, posée au démarrage de la lecture, et rien
  ne la remettait à zéro : la lecture s'achève d'elle-même à la fin du texte,
  sans que personne n'appelle `stop()`. Le service prévenait bien de la fin,
  mais pour lui seul. Conséquence moins visible et plus gênante : rappuyer sur
  ce bouton bloqué relançait la lecture au lieu de l'arrêter, puisque le
  service, lui, se savait au repos. L'état du service est désormais observable
  et le bouton le suit, au lieu d'en garder une copie ;
- **threads du moteur local** : `llama_context_default_params` en pose quatre
  quel que soit l'appareil, et llama.cpp note lui-même « TODO: better default »
  à cet endroit. Le compte tombait juste par hasard sur un téléphone à huit
  cœurs, mais il sursouscrivait un appareil à deux cœurs et n'utilisait qu'un
  tiers d'une tablette à douze. La règle appliquée est celle de llama.cpp pour
  ARM et Android : tous les cœurs jusqu'à quatre, la moitié au delà. Rien ne
  change sur un téléphone à huit cœurs, qui reste à quatre.

### Corrections du second passage

- **une régénération en échec effaçait l'ancienne réponse** : le fil était bien
  remplacé au bon moment, mais plus rien ne rendait la version d'avant si la
  génération échouait ensuite. Une erreur survenue avant le premier fragment
  laissait la conversation amputée de la réponse qu'elle venait d'effacer, et
  de tout ce qui la suivait. La version antérieure est maintenant copiée avant
  la coupe : elle revient d'elle-même quand rien n'est arrivé du moteur, et
  reste récupérable d'un geste quand du texte est déjà à l'écran, lequel n'est
  pas jeté pour autant. Quitter le fil pendant une régénération ne l'abandonne
  plus sur une bulle vide. Toute restauration est encadrée par l'identité de la
  conversation et de l'opération : une réponse en retard ne touche jamais au fil
  ouvert ;
- **la file et le fil qui vient de naître** : un message mis en attente pendant
  la préparation du tout premier message d'un nouveau chat ne pouvait pas en
  connaître l'identifiant, puisque le fil n'existait pas encore. Il se faisait
  ensuite refuser pour cette raison, et revenait en file avec une destination
  devenue fausse. Les messages en attente sont désormais rattachés au fil dès
  sa création. Un refus n'est plus invisible non plus : la file s'affiche
  au-dessus du composeur, chaque message s'y réessaie, se reprend dans le
  champ ou se retire, sans avoir à envoyer un message sans rapport. Reprendre
  un message échange sa place avec le brouillon en cours, pièces jointes
  comprises, et une réinsertion tardive ne ressuscite plus une file abandonnée
  par la navigation ;
- **une opération vocale périmée arrêtait la suivante** : la lecture à voix
  haute et la dictée refermaient le moteur en se découvrant périmées, ce qui
  coupait celle qui venait de démarrer. Les démarrages passent maintenant un par
  un, et une opération ne referme le moteur que s'il lui appartient encore.
  Les rappels de la synthèse vocale ne disent pas de quelle phrase ils parlent,
  et le plugin n'en garde qu'un jeu : ils sont donc neutralisés le temps d'une
  bascule, faute de pouvoir les attribuer. L'arrêt, lui, n'attend plus la fin
  d'un démarrage qu'Android fait patienter, et la destruction du service
  n'ouvre plus rien ;
- **une réponse écourtée passait pour entière** : le moteur distant relevait
  bien la troncature annoncée par le fournisseur, mais personne ne la lisait.
  L'issue de chaque génération, allée au bout, écourtée, arrêtée ou en échec,
  accompagne maintenant la réponse jusqu'à l'écran et jusqu'au fichier : une
  réponse coupée le reste après un redémarrage, au lieu de se rouvrir comme une
  réponse complète. La file d'attente ne repart plus toute seule sur une
  réponse écourtée, et les historiques écrits avant cette notion se relisent
  inchangés ;
- **structure invalide et historique vide** : un fichier dont la racine n'était
  pas un objet, ou dont le champ `conversations` n'était pas une liste, rendait
  un historique vide au lieu d'une erreur. Le premier enregistrement suivant
  remplaçait alors le fichier par cette liste vide. Ces structures sont
  maintenant des échecs de restauration, au même titre qu'un fichier illisible,
  et les conversations inexploitables d'une liste par ailleurs correcte sont
  signalées plutôt que silencieusement jetées. Le fichier d'origine reste
  intact, quoi que l'utilisateur fasse ensuite, et le message d'erreur ne cite
  aucun morceau de conversation.

### Corrections du troisième passage

- **une version remplacée ne tenait qu'à un bandeau** : après une erreur
  survenue en cours de réponse, l'ancienne version du fil n'existait plus que
  dans l'action d'un message éphémère. Passé ce délai, après une navigation ou
  après un redémarrage, elle était perdue, et la reprendre effaçait au passage
  le texte partiel reçu. La version remplacée est désormais conservée avec la
  conversation, donc enregistrée : un bandeau permanent la propose tant qu'on
  ne l'a pas retirée, et la reprendre échange les deux versions au lieu d'en
  sacrifier une. Régénération et modification sont protégées de la même façon,
  pièces jointes, sources et évaluations comprises, et un remplacement qui
  aboutit ne propose rien ;
- **le brouillon écrit pendant la préparation d'un envoi** : le texte et les
  pièces jointes partaient figés, mais le composeur était ensuite vidé sans
  qu'on regarde ce qu'il contenait devenu. Le chargement d'un modèle durant
  plusieurs secondes, le message écrit pendant ce temps disparaissait à son
  terme. Le composeur n'est maintenant vidé que s'il porte encore exactement
  ce qui est parti. Les fichiers cités par un brouillon ou par la file
  d'attente ne sont plus effacés comme s'ils n'appartenaient à personne ;
- **rappels vocaux sans identité** : la lecture à voix haute s'appuyait sur des
  rappels du système qui ne disent pas de quelle phrase ils parlent, et dont
  le plugin ne garde qu'un jeu. Un rappel de la lecture précédente arrivant
  après le démarrage de la suivante éteignait donc la mauvaise. Le moteur est
  désormais réglé pour que la réponse de chaque énoncé ne revienne qu'à sa
  propre fin : c'est ce signal, rattaché à l'appel qui l'a lancé, qui fait foi.
  Les rappels anonymes ne servent plus que de secours, là où ce mode n'existe
  pas ;
- **réponse écourtée sans le moindre mot** : l'issue d'une génération n'était
  lue que si du texte était arrivé. Une réponse annoncée écourtée avant son
  premier fragment passait donc pour une réussite, sa bulle disparaissait sans
  explication et la file d'attente enchaînait. L'issue est maintenant lue quel
  que soit le texte reçu, dite à l'écran, enregistrée, et la file attend une
  reprise explicite ;
- **messages perdus en silence à la relecture** : un message de structure
  invalide, de contenu non textuel ou de rôle inconnu était écarté sans bruit,
  et la conversation acceptée telle quelle. Le premier enregistrement suivant
  réécrivait alors le fichier sans ces messages. Toute perte repérée pendant la
  relecture, y compris une pièce jointe ou une source, fait maintenant de la
  restauration une récupération partielle : ce qui est lisible s'affiche, plus
  rien n'est écrit, et le fichier d'origine reste intact. Un champ optionnel
  absent d'un ancien format n'est pas une perte, pas plus qu'une valeur écrite
  par une version plus récente.

### Corrections du quatrième passage

- **rétablir une version pendant qu'une réponse s'écrit** : le bouton du
  bandeau restait actif pendant la préparation d'un envoi et pendant la
  génération. Rétablir à ce moment remplaçait le fil sans arrêter l'opération
  en cours, et le fragment suivant écrasait le dernier message de la version
  qu'on venait de reprendre. Le bandeau s'éteint désormais tant que l'envoi
  dure, et le dit ; la même garde protège l'échange et l'oubli de la version
  conservée, pour qu'ils ne dépendent pas du seul bouton. Tout redevient
  disponible dès que la réponse est terminée, qu'elle ait abouti, échoué ou
  été arrêtée ;
- **quitter un fil après quelques fragments perdait la version remplacée** :
  la réparation du fil abandonné s'arrêtait dès que sa dernière bulle
  contenait du texte, c'est-à-dire précisément quand des fragments étaient
  arrivés. La conversation quittée gardait alors la réponse partielle et
  perdait celle qu'elle remplaçait. Les deux sont maintenant conservées, la
  partielle portant ce qui y a mis fin : interruption, troncature ou erreur.
  Quitter un fil en pleine réponse est noté comme une interruption et non
  comme une réponse achevée. La réparation ne touche que le fil visé, jamais
  celui qui est ouvert à sa place, ne ressuscite pas une conversation
  supprimée et s'efface devant une génération plus récente.

## [0.1.3] - 2026-09-14

Le fil de discussion devient utilisable au quotidien : chaque réponse porte sa
barre d'actions et ses sources, un message envoyé se modifie, la barre du haut
annonce le fil ouvert, le composeur ne fait plus surgir de bouton sous le doigt,
et le menu latéral date enfin les conversations pour ce qu'elles sont. La suite
de tests passe de 216 à 332 cas.

### Ajouts

- **titre du fil dans la barre du haut** : le fil ouvert est nommé sans avoir
  à ouvrir le menu latéral. Tant qu'aucun message n'a été envoyé, la barre
  affiche le nom de l'application : il n'y a pas encore de fil à nommer ;
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
  aucun son et n'en conserve aucun ;
- **mise en attente d'un message écrit pendant une réponse** : plutôt que de
  refuser l'envoi ou d'interrompre ce qui s'écrit, le message prend la file et
  part tout seul dès la réponse terminée. Plusieurs messages partent dans leur
  ordre. Quitter le fil abandonne sa file : les messages en attente
  appartiennent à la conversation où ils ont été écrits ;
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
  l'application.

### Modifications

- **le composeur garde deux boutons en toute circonstance.** Le bouton de
  droite prend le rôle du moment plutôt que d'en faire apparaître un
  troisième : micro au repos, envoi dès qu'on écrit, arrêt pendant une
  réponse, mise en attente si on écrit pendant une réponse. Un bouton
  surgissant à la première frappe déplaçait les deux autres sous le doigt,
  juste avant qu'on les vise. La dictée garde son bouton jusqu'au
  relâchement : la parole remplit le champ, et laisser le brouillon l'emporter
  aurait fait disparaître le bouton qui attend le relâchement, micro ouvert ;
- **texte du champ de saisie** : « Demander à FoxLLM » au repos, « Mettre un
  message en attente… » pendant une réponse, « Parle, je t'écoute… » pendant
  la dictée ;
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

### Corrections

- **datation des conversations dans le menu latéral** : passé minuit, une
  conversation de la veille se retrouvait sous un intitulé annonçant « 7
  jours ». Le classement était juste, mais il n'y avait que trois tranches et
  celle du milieu ramassait tout ce qui n'était plus du jour, de la veille au
  septième jour. Il y en a maintenant cinq, dont chacune dit ce qu'elle
  couvre : Aujourd'hui, Hier, 7 derniers jours, 30 derniers jours, Plus tôt.
  Une tranche vide ne s'affiche plus : un « Aujourd'hui » sans rien dessous,
  posé au-dessus des fils d'hier, laissait croire qu'ils dataient du jour. Le
  bouton « + » garde son en-tête, désormais intitulé « Chats », qui ne prétend
  dater personne. Chaque ligne porte en outre sa date exacte : l'heure pour
  aujourd'hui et hier, le jour et le mois dans l'année, et l'année au delà ;
- les tranches se recalculent **au passage de minuit**. Une application laissée
  ouverte la nuit continuait de classer d'après la veille jusqu'à ce qu'autre
  chose provoque une reconstruction. Les jours se comptent de minuit à minuit
  et non par tranches de vingt-quatre heures, et l'heure n'est relevée qu'une
  fois par affichage : deux relevés encadrant minuit rangeaient deux
  conversations de la même minute dans deux tranches différentes ;
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
  disparu, au lieu d'empiler une exception par-dessus l'erreur d'origine ;
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
  panne plutôt qu'à chaque fragment ;
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

### Performances

- l'historique n'est plus réécrit intégralement à chaque fragment reçu. Les
  enregistrements intermédiaires sont regroupés, au plus un toutes les deux
  secondes, et l'état est relu au moment d'écrire plutôt que figé à la
  planification : une écriture différée ne peut donc pas ressusciter une
  conversation supprimée entre-temps. Fin de génération, arrêt, erreur,
  navigation, renommage, suppression et fermeture de l'écran écrivent tous
  sans attendre.

### Tests

- 216 à 332 cas sur l'ensemble de la version. Origine des clés API et migration
  des réglages, regroupement des écritures et propagation des échecs, envoi
  annulé par un changement de fil, pièces jointes liées au brouillon, barre
  d'actions absente pendant la génération, lecture des trois formats de
  citation, modification d'un message envoyé, rangée du composeur dans ses
  quatre états, file d'attente, titre de la barre du haut, tranches de dates du
  menu latéral et date portée par chaque conversation. Les tests d'écran
  ont été vérifiés contre le code d'origine : ils échouent bien là où le
  correctif manque ;
- `packages/foxllm_native/tool/asan/run.sh` rejoue la vérification native :
  llama.cpp et le moteur compilés sous AddressSanitizer, un GGUF de test
  fabriqué sur place, et une génération réelle. Hors intégration continue, la
  compilation instrumentée durant une dizaine de minutes.

### Modifications

- **signature de distribution séparée de celle de développement.** Le build
  release utilisait `signingConfigs.getByName("debug")` : la clé de
  développement d'Android est publique, identique pour tout le monde, et une
  application installée avec elle ne peut jamais être mise à jour par une
  version signée pour de bon. Sans clé de distribution, l'APK release sort
  désormais non signé plutôt que signé avec celle-là. La clé et ses mots de
  passe viennent d'un fichier ignoré par git ou de l'environnement, jamais du
  dépôt ;
- l'intégration continue sépare les deux : les propositions de modification
  vérifient la compilation sans aucun secret et produisent des artefacts
  nommés « non distribuable », tandis qu'un travail distinct, déclenché
  seulement à la main ou par une étiquette de version, produit l'APK signé et
  refuse de livrer un APK portant la clé de développement. La marche à suivre
  est décrite dans `RELEASING.md` ;
- la politique de confidentialité décrit la **lecture à voix haute**, qui
  manquait : selon la voix installée, le texte de la réponse peut être confié
  aux serveurs du fournisseur de la synthèse, y compris quand la réponse vient
  d'un modèle local.

### Notes

- le pouce haut et le pouce bas restent **sur l'appareil** : FoxLLM n'a pas de
  serveur à qui transmettre un avis, et n'en aura pas. C'est un repère
  personnel, conservé avec la conversation, pour retrouver une bonne réponse
  dans un long fil ;
- conséquence des deux boutons : la dictée ne démarre plus que sur un champ
  vide, puisque le micro cède sa place à l'envoi dès qu'il y a du texte.
  Compléter une phrase déjà écrite passe désormais par le micro du clavier
  Android.

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
