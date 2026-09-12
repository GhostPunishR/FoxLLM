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

- exécuter des modèles locaux Android en GGUF via un moteur C++ / `llama.cpp` ;
- proposer un mode **BYOK (Bring Your Own Key)** pour les fournisseurs distants ;
- conserver les clés API sur l'appareil, avec un mode session sans persistance ;
- utiliser une seule interface de chat pour les moteurs locaux et les API.

## Architecture

```text
Flutter / Dart
├── UI et état de conversation
├── LlmBackend
│   ├── LocalLlmBackend
│   │   └── foxgpt_native
│   │       └── C ABI
│   │           └── C++ / llama.cpp / GGUF
│   └── OpenAiCompatibleBackend
│       └── HTTPS direct / BYOK
└── stockage sécurisé des clés
```

La documentation détaillée se trouve dans [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## État du bootstrap

Déjà présent :

- contrat Dart commun `LlmBackend` avec streaming ;
- modèles de messages et paramètres de génération ;
- backend OpenAI-compatible avec streaming SSE ;
- stockage sécurisé des clés API ou conservation en mémoire pour la session ;
- package FFI `foxgpt_native` ;
- ABI C stable devant une implémentation C++ ;
- shell Flutter initial permettant de vérifier le pont natif ;
- CI GitHub Actions séparées pour le formatage, l'analyse Flutter, les tests Flutter, l'analyse Dart native, la compilation C++, le smoke test FFI et le build Android.

Le moteur C++ est volontairement un scaffold : il signale que `llama.cpp` n'est pas encore intégré au lieu de simuler une génération.

## Prochain jalon

Le prochain travail est l'intégration de `llama.cpp`, le chargement GGUF et le worker isolate pour exécuter l'inférence hors du thread UI, puis le streaming token par token.
