# FoxGPT

FoxGPT est un client LLM Android hybride construit avec Flutter/Dart et C++.

Objectifs du projet :

- exécuter des modèles locaux sur Android via un moteur C++ ;
- supporter les modèles GGUF via `llama.cpp` ;
- permettre le mode BYOK (Bring Your Own Key) pour les fournisseurs d'API ;
- stocker les clés API localement et de manière sécurisée ;
- fournir une interface de chat unique pour les modèles locaux et distants.

## Architecture cible

```text
Flutter / Dart
├── UI et navigation
├── Chat et historique
├── Fournisseurs API / BYOK
├── Stockage sécurisé des clés
└── LocalLlmBackend
    └── Dart FFI
        └── C++ / llama.cpp / GGUF
```

Le projet est en cours d'initialisation.
