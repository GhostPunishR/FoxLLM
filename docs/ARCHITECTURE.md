# Architecture FoxGPT

## Objectif

FoxGPT est un client LLM Android hybride :

- **local** : modèles GGUF exécutés sur le téléphone par `llama.cpp` ;
- **BYOK** : l'utilisateur fournit sa propre clé API et le téléphone contacte directement le fournisseur.

## Couches

```text
Flutter / Dart
├── UI
├── état de conversation
├── sélection du backend
├── stockage sécurisé des clés BYOK
├── OpenAiCompatibleBackend
└── LocalLlmBackend
    └── foxgpt_native
        └── C ABI stable
            └── C++
                └── llama.cpp b10903
                    └── GGUF / CPU Android arm64
```

## Contrat Dart

Tous les moteurs implémentent `LlmBackend` et exposent une génération sous forme de `Stream<String>`.

Cela permet à l'interface de chat de ne pas dépendre du fournisseur ou du moteur local. Le backend local produit encore un seul bloc de texte dans cette étape ; le worker isolate et le streaming natif arrivent au jalon suivant.

## BYOK

Les clés API ne doivent jamais être ajoutées au dépôt, aux logs ou aux exports de conversations.

Deux modes de conservation sont prévus :

- `device` : clé chiffrée via `flutter_secure_storage` ;
- `session` : clé conservée uniquement en mémoire jusqu'à la fermeture de l'application.

Le backend `OpenAiCompatibleBackend` effectue directement la requête HTTPS depuis l'appareil.

## Moteur natif

Le package `packages/foxgpt_native` conserve une ABI C (`extern "C"`) stable devant l'implémentation C++.

Sur Android arm64, le build hook utilise CMake et lie statiquement `llama.cpp` b10903 (commit `481c65f091f74c5e7089dd0a3a1cc6b50cced31e`) dans `libfoxgpt_native.so`. Les options Android désactivent `GGML_NATIVE`, OpenMP, llamafile et OpenSSL afin de rester compatibles avec la chaîne NDK. Le baseline Android de FoxGPT est API 28.

Sur les autres architectures, le build hook conserve un stub léger. Cela permet aux tests FFI et au mode API de continuer à fonctionner sans compiler `llama.cpp` partout.

Fonctions natives disponibles :

- création/destruction du moteur ;
- chargement et déchargement d'un modèle GGUF ;
- état du modèle chargé ;
- description, taille et contexte entraîné du modèle ;
- génération locale bloquante ;
- arrêt coopératif ;
- remontée d'erreurs ;
- libération des chaînes allouées côté natif.

La génération locale actuelle utilise un sampler greedy et limite une réponse à 128 tokens. Ce chemin est volontairement minimal : il sert à valider le chargement, le contexte et l'inférence avant d'introduire le streaming asynchrone.

## Prochains jalons

1. Déplacer l'inférence dans un worker isolate dédié pour ne jamais bloquer l'UI Flutter.
2. Remplacer la génération monobloc par un callback/port natif pour streamer les tokens.
3. Ajouter les paramètres de sampling (température, top-p, max tokens) au contrat natif.
4. Ajouter la sélection de fichiers GGUF et le gestionnaire de modèles.
5. Construire l'écran de chat et le sélecteur Local/API.
6. Ajouter les adaptateurs spécifiques aux fournisseurs non OpenAI-compatible.
7. Évaluer Vulkan/KleidiAI une fois le chemin CPU de base stabilisé.
