# FoxGPT

[![Dart Format](https://github.com/GhostPunishR/FoxGPT/actions/workflows/format.yml/badge.svg)](https://github.com/GhostPunishR/FoxGPT/actions/workflows/format.yml)
[![Flutter Analyze](https://github.com/GhostPunishR/FoxGPT/actions/workflows/flutter-analyze.yml/badge.svg)](https://github.com/GhostPunishR/FoxGPT/actions/workflows/flutter-analyze.yml)
[![Flutter Tests](https://github.com/GhostPunishR/FoxGPT/actions/workflows/flutter-tests.yml/badge.svg)](https://github.com/GhostPunishR/FoxGPT/actions/workflows/flutter-tests.yml)
[![Native Dart Analyze](https://github.com/GhostPunishR/FoxGPT/actions/workflows/native-analyze.yml/badge.svg)](https://github.com/GhostPunishR/FoxGPT/actions/workflows/native-analyze.yml)
[![C++ Compile](https://github.com/GhostPunishR/FoxGPT/actions/workflows/cpp.yml/badge.svg)](https://github.com/GhostPunishR/FoxGPT/actions/workflows/cpp.yml)
[![FFI Smoke](https://github.com/GhostPunishR/FoxGPT/actions/workflows/ffi-smoke.yml/badge.svg)](https://github.com/GhostPunishR/FoxGPT/actions/workflows/ffi-smoke.yml)
[![Android Build](https://github.com/GhostPunishR/FoxGPT/actions/workflows/android-build.yml/badge.svg)](https://github.com/GhostPunishR/FoxGPT/actions/workflows/android-build.yml)

FoxGPT est un client LLM Android hybride construit avec **Flutter/Dart + C++**.

## Vision

- exécuter des modèles locaux Android en GGUF via `llama.cpp` ;
- proposer un mode **BYOK (Bring Your Own Key)** pour les fournisseurs distants ;
- conserver les clés API sur l'appareil, avec un mode session sans persistance ;
- utiliser une seule interface de chat pour les moteurs locaux et les API.

## Architecture

```text
Flutter / Dart
├── UI et état de conversation
├── LlmBackend
│   ├── LocalLlmBackend
│   │   └── worker isolate
│   │       └── foxgpt_native
│   │           └── C ABI / callbacks
│   │               └── C++ / llama.cpp / GGUF
│   └── OpenAiCompatibleBackend
│       └── HTTPS direct / BYOK
├── bibliothèque GGUF privée de l'application
└── stockage sécurisé des clés
```

Le code applicatif Flutter ne crée jamais `FoxGptNativeEngine` directement : l'accès local passe par `LocalLlmBackend` puis `FoxGptNativeWorker`, afin de garder les appels bloquants hors de l'isolate UI.

La documentation détaillée se trouve dans [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## État actuel

Déjà présent :

- écran de chat FoxGPT affiché dès le lancement, sans écran intermédiaire ;
- identité renard orange tracée depuis la référence visuelle officielle FoxGPT et partagée entre chat et icône Android ;
- icône APK/adaptive icon sur fond blanc ;
- démarrage sans écran de marque : la fenêtre de lancement Android reprend le fond du chat ;
- menu latéral avec recherche de conversations, regroupement temporel et accès aux paramètres ;
- historique de conversations disponible pendant la session avec retour vers un chat précédent ;
- écran Paramètres avec accès aux modèles locaux et aux sections FoxGPT ;
- composer responsive avec Réflexion, Rechercher, ajout, voix/envoi et Stop ;
- chat local branché sur le streaming du `LocalLlmBackend` ;
- contrat Dart commun `LlmBackend` ;
- backend OpenAI-compatible avec streaming SSE et BYOK ;
- stockage sécurisé des clés API ou conservation en mémoire pour la session ;
- package FFI `foxgpt_native` avec ABI C stable ;
- `llama.cpp` b10903 épinglé pour le moteur Android arm64 ;
- chargement/déchargement réel de modèles GGUF ;
- sélection d'un fichier `.gguf` via le picker système ;
- import par flux dans le stockage privé de FoxGPT avec progression et fichier temporaire `.part` ;
- bibliothèque persistante des modèles importés, gestion des doublons et suppression ;
- écran de gestion des modèles avec état chargé/déchargé et métadonnées ;
- métadonnées du modèle : description, taille et contexte entraîné ;
- inference locale exécutée dans un isolate worker dédié ;
- streaming token par token C++ → Dart → Flutter ;
- décodage UTF-8 incrémental des morceaux natifs ;
- arrêt coopératif immédiat via flag atomique ;
- paramètres natifs température, top-p et max tokens ;
- métriques de génération : tokens, durée et tokens/s ;
- diagnostic du moteur local routé lui aussi par le worker isolate ;
- smoke tests du cycle de vie worker, y compris erreur de génération et dispose idempotent ;
- APK Android arm64 construit en CI avec vérification du moteur llama.cpp et des symboles de streaming embarqués.

Le moteur local réel est actuellement ciblé sur **Android arm64 / API 28+**. Les autres architectures utilisent un stub natif afin que le mode API et les tests FFI restent disponibles.

## Prochain jalon

La prochaine étape est de rendre l'historique des conversations persistant entre les redémarrages, de brancher la sélection Local/API directement dans le chat, puis d'ajouter les paramètres de génération dans l'interface.
