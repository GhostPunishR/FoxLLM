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

## Développer

```bash
flutter pub get
flutter test          # 221 cas
flutter analyze
flutter build apk --release
```

`llama.cpp` (b10903) est compilé et lié statiquement par le build hook du
package natif : rien à installer de plus que le SDK Flutter et le NDK Android.

La boucle de décodage native confie au batch un pointeur vers le jeton
échantillonné, que `llama_decode` relit au tour suivant. Ni la compilation ni
une génération sans modèle ne couvrent ce scénario :
`packages/foxllm_native/tool/asan/run.sh` compile llama.cpp et le moteur sous
AddressSanitizer, fabrique un GGUF de test et génère réellement des tokens. Une
dizaine de minutes, hors intégration continue, à lancer après toute retouche de
cette boucle.

```text
lib/
├── main.dart         amorçage et widget racine
├── core/             briques transverses, sans écran
│   ├── app_info.dart version, titulaire des droits, adresse du dépôt
│   ├── storage/      clé API et dernier modèle, en stockage sécurisé
│   ├── theme/        palette du renard et ses deux déclinaisons
│   └── ui/           widgets partagés par plusieurs écrans
├── llm/              moteurs et contrat commun, aucun widget
│   ├── model/        messages, pièces jointes, réglages de génération
│   ├── backend/      LlmBackend, socle HTTP, moteurs local et distants
│   └── personal_api/ fournisseurs BYOK, réglages, découverte des modèles
└── features/         un dossier par écran
    ├── chat/         chat, pièces jointes, conversations, Markdown
    ├── local_models/ bibliothèque GGUF et son écran
    └── settings/     apparence, API, personnalisation, à propos

packages/foxllm_native/
├── lib/              liaison FFI et isolate worker
├── src/              ABI C stable devant le C++
└── hook/             compilation de llama.cpp à la construction

test/                 miroir de lib/, plus repository/ pour le dépôt lui-même
docs/                 site public du projet
```

Les imports internes s'écrivent en `package:foxllm/...` plutôt qu'en chemins
relatifs : déplacer un fichier ne casse alors rien.

Le code Flutter ne crée jamais `FoxLlmNativeEngine` directement : il passe par
`LocalLlmBackend`, qui délègue à `FoxLlmNativeWorker`. C'est ce qui garde les
appels bloquants de `llama.cpp` hors de l'isolate d'interface.

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

Copyright © 2026 GhostPunishR

FoxLLM est un logiciel libre, distribué sous
[GNU Affero General Public License version 3](LICENSE), à l'exclusion de toute
version ultérieure. Il est fourni sans aucune garantie.

Chaque fichier source porte sa notice sous forme d'identifiant SPDX
(`AGPL-3.0-only`). Le texte intégral de la licence est aussi consultable dans
l'application, avec l'adresse du dépôt : l'AGPL demande que celui qui reçoit le
programme puisse en obtenir le code source. Les bibliothèques tierces gardent
leurs licences respectives, rassemblées dans Paramètres, À propos, Licences
tierces.
