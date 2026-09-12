# Architecture FoxGPT

## Objectif

FoxGPT est un client LLM Android hybride :

- **local** : modèles GGUF exécutés sur le téléphone par un moteur C++ ;
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
                └── llama.cpp (prochain jalon)
```

## Contrat Dart

Tous les moteurs implémentent `LlmBackend` et exposent une génération sous forme de `Stream<String>`.

Cela permet à l'interface de chat de ne pas dépendre du fournisseur ou du moteur local.

## BYOK

Les clés API ne doivent jamais être ajoutées au dépôt, aux logs ou aux exports de conversations.

Deux modes de conservation sont prévus :

- `device` : clé chiffrée via `flutter_secure_storage` ;
- `session` : clé conservée uniquement en mémoire jusqu'à la fermeture de l'application.

Le backend `OpenAiCompatibleBackend` effectue directement la requête HTTPS depuis l'appareil.

## Moteur natif

Le package `packages/foxgpt_native` utilise les build hooks FFI modernes de Dart/Flutter.

L'interface publique native reste une ABI C (`extern "C"`) afin de garder le pont Dart stable, tandis que son implémentation est en C++.

Fonctions actuelles :

- création/destruction du moteur ;
- chargement de modèle ;
- génération ;
- arrêt ;
- remontée d'erreurs ;
- libération des chaînes allouées côté natif.

Le moteur C++ est actuellement un **scaffold** : il refuse la génération tant que `llama.cpp` n'est pas intégré.

## Prochains jalons

1. Intégrer `llama.cpp` dans `foxgpt_native`.
2. Charger et décharger un fichier GGUF.
3. Déplacer l'inférence dans un worker isolate dédié pour ne jamais bloquer l'UI Flutter.
4. Remplacer la génération monobloc par un callback/port natif pour streamer les tokens.
5. Ajouter la sélection de fichiers GGUF et le gestionnaire de modèles.
6. Construire l'écran de chat et le sélecteur Local/API.
7. Ajouter les adaptateurs spécifiques aux fournisseurs non OpenAI-compatible.
