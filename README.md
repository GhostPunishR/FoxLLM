<p align="center">
  <img src="docs/fox_logo.png" alt="" width="108" />
</p>

<h1 align="center">FoxLLM</h1>

<p align="center">
  Un chat IA pour Android, sans serveur et sans compte.<br />
  Les modèles tournent sur le téléphone, ou ta propre clé API
  parle au fournisseur de ton choix.
</p>

<p align="center">
  <img alt="Dart 3.10+" src="https://img.shields.io/badge/Dart-3.10%2B-0175C2?logo=dart&logoColor=white" />
  <img alt="Flutter 3.47" src="https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white" />
  <img alt="C++ 17" src="https://img.shields.io/badge/C%2B%2B-17-00599C?logo=cplusplus&logoColor=white" />
  <img alt="Android 9+ arm64" src="https://img.shields.io/badge/Android-9%2B%20arm64-3DDC84?logo=android&logoColor=white" />
  <a href="LICENSE"><img alt="Licence AGPL v3" src="https://img.shields.io/badge/Licence-AGPL%20v3-A42E2B?logo=gnu&logoColor=white" /></a>
</p>

---

## Ce que c'est

Une application de discussion avec un modèle de langage, écrite en Flutter avec
un moteur d'inférence C++. Elle n'a pas de serveur : il n'y a donc ni compte à
créer, ni file d'attente, ni données à nous confier.

Présentation complète, schémas et textes légaux sur le site du projet, dans
[`docs/`](docs/).

## Deux façons de répondre

**Modèle local.** Un fichier GGUF importé dans l'espace privé de l'application
et exécuté par `llama.cpp` sur le processeur du téléphone. Aucune connexion
réseau n'est utilisée : rien ne quitte l'appareil.

**API personnelle (BYOK).** Ta clé, ton fournisseur, ta facture. La requête part
du téléphone directement chez le fournisseur, sans relais. La clé est chiffrée
par le stockage sécurisé du système, ou gardée en mémoire pour la seule session.

Fournisseurs intégrés : OpenAI (API Responses), Google Gemini, Groq, Mistral AI,
OpenRouter, xAI, et toute API OpenAI-compatible saisie à la main.

## Fonctions

- historique de conversations conservé, avec recherche, renommage et suppression
- réponses en Markdown : titres, listes, gras, liens, blocs de code colorés et
  copiables
- pièces jointes depuis le composer : fichier, galerie, appareil photo
- images envoyées aux modèles multimodaux, au format attendu par le fournisseur
- dictée vocale maintenue au doigt, corrigeable avant envoi
- modes Réflexion et Recherche activables, avec l'outil web intégré d'OpenAI ou
  de Gemini
- consigne de personnalisation appliquée au moteur local comme à l'API
- deux déclinaisons, claire et sombre, jusqu'à la fenêtre de lancement Android

## Installer

L'APK se récupère sur la page [Releases](../../releases). Il vise **Android 9
(API 28) ou plus récent, en arm64**. Les autres architectures utilisent un stub
natif : le mode API personnelle reste disponible, pas le moteur local.

## Intégration continue

| Vérification | Ce qu'elle contrôle | État |
| --- | --- | --- |
| Dart Format | mise en forme de `lib/` et `test/` | [![Dart Format](https://github.com/GhostPunishR/FoxLLM/actions/workflows/format.yml/badge.svg)](https://github.com/GhostPunishR/FoxLLM/actions/workflows/format.yml) |
| Flutter Analyze | analyse statique de l'application | [![Flutter Analyze](https://github.com/GhostPunishR/FoxLLM/actions/workflows/flutter-analyze.yml/badge.svg)](https://github.com/GhostPunishR/FoxLLM/actions/workflows/flutter-analyze.yml) |
| Flutter Tests | la suite de tests complète | [![Flutter Tests](https://github.com/GhostPunishR/FoxLLM/actions/workflows/flutter-tests.yml/badge.svg)](https://github.com/GhostPunishR/FoxLLM/actions/workflows/flutter-tests.yml) |
| Native Dart Analyze | analyse du package FFI | [![Native Dart Analyze](https://github.com/GhostPunishR/FoxLLM/actions/workflows/native-analyze.yml/badge.svg)](https://github.com/GhostPunishR/FoxLLM/actions/workflows/native-analyze.yml) |
| C++ Compile | compilation du moteur en `-Wall -Wextra -Werror` | [![C++ Compile](https://github.com/GhostPunishR/FoxLLM/actions/workflows/cpp.yml/badge.svg)](https://github.com/GhostPunishR/FoxLLM/actions/workflows/cpp.yml) |
| FFI Smoke | cycle de vie du moteur natif de bout en bout | [![FFI Smoke](https://github.com/GhostPunishR/FoxLLM/actions/workflows/ffi-smoke.yml/badge.svg)](https://github.com/GhostPunishR/FoxLLM/actions/workflows/ffi-smoke.yml) |
| Android Build | APK arm64, moteur et symboles embarqués | [![Android Build](https://github.com/GhostPunishR/FoxLLM/actions/workflows/android-build.yml/badge.svg)](https://github.com/GhostPunishR/FoxLLM/actions/workflows/android-build.yml) |

## Licence

FoxLLM est un logiciel libre, distribué sous
[GNU Affero General Public License version 3](LICENSE), à l'exclusion de toute
version ultérieure. Il est fourni sans aucune garantie.

Copyright © 2026 GhostPunishR
