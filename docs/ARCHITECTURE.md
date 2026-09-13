# Architecture FoxLLM

## Objectif

FoxLLM est un client LLM Android hybride :

- **local** : modèles GGUF exécutés sur le téléphone par `llama.cpp` ;
- **BYOK** : l'utilisateur fournit sa propre clé API et le téléphone contacte directement le fournisseur.

## Couches

```text
Flutter / Dart (isolate UI)
├── UI
├── état de conversation
├── sélection du backend
├── stockage sécurisé des clés BYOK
├── bibliothèque locale GGUF
│   └── Application Support / models
├── HttpStreamingBackend
│   ├── OpenAiCompatibleBackend
│   └── GeminiBackend
└── LocalLlmBackend
    └── FoxLlmNativeWorker (isolate dédié)
        └── foxllm_native
            └── C ABI stable + callback de tokens
                └── C++
                    └── llama.cpp b10903
                        └── GGUF / CPU Android arm64
```

## Contrat Dart

Tous les moteurs implémentent `LlmBackend` et exposent une génération sous forme de `Stream<String>`.

Le backend local démarre un isolate worker longue durée qui possède le moteur natif. Le chargement GGUF et l'inférence bloquante de `llama.cpp` se déroulent exclusivement dans ce worker : l'isolate Flutter reste disponible pour les animations, les entrées utilisateur et le rendu.

**Invariant d'architecture :** le code de l'application Flutter ne doit pas instancier `FoxLlmNativeEngine` directement. L'UI et les contrôleurs applicatifs passent par `LocalLlmBackend`, qui délègue à `FoxLlmNativeWorker`. Les appels directs au moteur restent réservés à l'implémentation du package natif et à ses smoke tests bas niveau.

`LocalLlmBackend` est partagé à l'échelle de l'application via Riverpod afin que l'écran d'accueil, le gestionnaire de modèles et le futur écran de chat utilisent le même worker et le même modèle chargé.

Pendant l'inférence, le C++ appelle un callback FFI pour chaque token. Le worker copie immédiatement les octets du token et les transmet à l'isolate principal par `SendPort`. Le décodage UTF-8 est incrémental afin de gérer correctement les séquences multi-octets pouvant traverser plusieurs tokens.

`stop()` est particulier : comme le worker peut être bloqué dans l'appel FFI, l'isolate principal appelle uniquement l'export natif thread-safe qui positionne un flag atomique. La boucle `llama.cpp` observe ce flag entre deux décodages et s'interrompt sans attendre que la file de messages du worker soit disponible.

## Bibliothèque de modèles GGUF

Le picker système sert uniquement à sélectionner la source. FoxLLM ne conserve pas un chemin temporaire fourni par le picker : le contenu du `.gguf` est copié par flux dans le dossier privé `models` sous le répertoire Application Support de l'application.

L'import écrit d'abord dans un fichier `.part-*`. Chaque chunk est écrit avec `RandomAccessFile.writeFrom()` et attendu avant de lire le suivant, ce qui applique une backpressure réelle et évite d'accumuler en mémoire plusieurs gigaoctets lorsque le stockage est plus lent que la source.

Le fichier ne prend son nom `.gguf` définitif qu'après fermeture complète du flux et validation de la taille lorsque celle-ci est connue. En cas d'erreur, le fichier partiel est supprimé. Au prochain scan de la bibliothèque, les `.part-*` orphelins laissés par un crash, un kill Android ou un redémarrage sont également supprimés ; les imports encore actifs dans le processus courant sont protégés de ce nettoyage.

Un nom déjà présent reçoit un suffixe `(2)`, `(3)`, etc. au lieu d'écraser un modèle existant. La bibliothèque est reconstruite en parcourant ce dossier privé : aucun registre séparé n'est nécessaire. La suppression est limitée aux fichiers `.gguf` présents directement dans ce dossier, et l'interface interdit de supprimer le modèle actuellement chargé.

Si le chargement d'un nouveau GGUF échoue après que `llama.cpp` a déchargé l'ancien modèle, `LocalLlmBackend` efface aussi son chemin chargé afin que l'état Flutter reste synchronisé avec l'état natif.

## BYOK

Les clés API ne doivent jamais être ajoutées au dépôt, aux logs ou aux exports de conversations.

Deux modes de conservation sont prévus :

- `device` : clé chiffrée via `flutter_secure_storage` ;
- `session` : clé conservée uniquement en mémoire jusqu'à la fermeture de l'application.

Le backend `OpenAiCompatibleBackend` effectue directement la requête HTTPS depuis l'appareil.

### Socle HTTP partagé

`OpenAiCompatibleBackend` et `GeminiBackend` dérivent tous deux de
`HttpStreamingBackend`. Ce socle porte tout ce qui ne dépend pas du fournisseur :
lecture de la clé API, création et fermeture du client HTTP, détection d'une
réponse non 2xx, découpage des lignes SSE, et cycle de vie `stop()`/`dispose()`
y compris l'annulation d'une génération encore en attente de sa clé API.

Une sous-classe ne décrit que deux choses : la requête à envoyer
(`buildRequest`) et la façon d'extraire les fragments de texte d'un évènement
SSE décodé (`extractDeltas`). Ajouter un protocole non OpenAI-compatible revient
donc à implémenter ces deux méthodes, sans réécrire la mécanique d'annulation.

Une réponse HTTP non 2xx lève toujours `PersonalApiHttpException`, que
`describePersonalApiError` traduit en message lisible pour l'interface.

## Moteur natif

Le package `packages/foxllm_native` conserve une ABI C (`extern "C"`) stable devant l'implémentation C++.

Sur Android arm64, le build hook utilise CMake et lie statiquement `llama.cpp` b10903 (commit `481c65f091f74c5e7089dd0a3a1cc6b50cced31e`) dans `libfoxllm_native.so`. Les options Android désactivent `GGML_NATIVE`, OpenMP, llamafile et OpenSSL afin de rester compatibles avec la chaîne NDK. Le baseline Android de FoxLLM est API 28.

Sur les autres architectures, le build hook conserve un stub léger. Cela permet aux tests FFI et au mode API de continuer à fonctionner sans compiler `llama.cpp` partout.

Fonctions natives disponibles :

- création/destruction du moteur ;
- chargement et déchargement d'un modèle GGUF ;
- état du modèle chargé ;
- description, taille et contexte entraîné du modèle ;
- génération locale historique monobloc pour compatibilité ;
- génération streaming par callback natif ;
- température, top-p et limite de tokens ;
- reset/arrêt coopératif via flag atomique ;
- remontée d'erreurs ;
- libération des chaînes allouées côté natif.

Lorsque `temperature <= 0`, le moteur utilise un sampler greedy. Sinon la chaîne applique top-p, température puis distribution aléatoire. `GenerationSettings.maxTokens` borne la génération, elle-même limitée par la fenêtre de contexte entraînée du modèle.

Le worker mesure également le nombre de tokens générés et la durée totale d'inférence pour exposer une estimation des tokens/s.

## Prochains jalons

1. Construire l'écran de chat et le sélecteur Local/API autour des streams existants.
2. Ajouter la persistance des conversations et les paramètres de génération dans l'UI.
3. Ajouter les adaptateurs spécifiques aux fournisseurs non OpenAI-compatible.
4. Ajouter le téléchargement de modèles avec reprise et vérification de checksum.
5. Évaluer Vulkan/KleidiAI une fois le chemin CPU de base stabilisé.
