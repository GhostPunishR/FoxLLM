# Livraison

Comment produire un APK FoxLLM distribuable, et ce qu'il ne faut jamais faire.

## La règle qui prime sur toutes les autres

**La clé qui signe la première version publiée signe toutes les suivantes.**

Android identifie une application par son `applicationId` **et** par le
certificat qui la signe. Changer de clé après une publication produit une
application que le système considère comme différente : la mise à jour est
refusée, et l'utilisateur doit désinstaller, ce qui efface tout son historique.

Il n'existe aucun moyen de revenir en arrière. Sauvegardez la clé et ses mots
de passe hors du dépôt, en plusieurs exemplaires.

## Ce qui n'est pas distribuable

Le travail `Android Build` de l'intégration continue compile l'application à
chaque proposition de modification. Ses artefacts s'appellent
`foxllm-debug-non-distribuable` et `foxllm-release-non-distribuable` : ils
attestent que le code compile, rien de plus.

Sans clé de distribution, l'APK release sort **non signé**. C'est voulu. Il
était auparavant signé avec la clé de développement d'Android, qui est
publique et identique pour tout le monde : n'importe qui peut publier une mise
à jour d'une application signée ainsi. Une application installée avec cette clé
ne pourra jamais recevoir de mise à jour signée pour de bon.

Si vous avez installé un APK issu de l'intégration continue, désinstallez-le
avant d'installer une version signée. **Votre historique de conversations sera
perdu** : il vit dans le stockage privé de l'application, qu'Android supprime
avec elle.

## Créer la clé, une seule fois

```sh
keytool -genkey -v -keystore foxllm-release.jks \
  -keyalg RSA -keysize 4096 -validity 10000 -alias foxllm
```

Conservez le fichier `.jks`, le mot de passe du magasin, l'alias et le mot de
passe de la clé. Le dépôt ignore `*.jks`, `*.keystore` et
`android/key.properties` : rien de tout cela ne doit s'y retrouver.

## Construire en local

Créez `android/key.properties`, jamais versionné :

```properties
storeFile=/chemin/absolu/vers/foxllm-release.jks
storePassword=…
keyAlias=foxllm
keyPassword=…
```

Puis :

```sh
flutter build apk --release --target-platform android-arm64
```

Les mêmes valeurs peuvent venir de l'environnement, ce qu'utilise
l'intégration continue : `FOXLLM_RELEASE_KEYSTORE`,
`FOXLLM_RELEASE_STORE_PASSWORD`, `FOXLLM_RELEASE_KEY_ALIAS` et
`FOXLLM_RELEASE_KEY_PASSWORD`. Le fichier l'emporte sur l'environnement.

Les quatre sont exigés ensemble : une signature à moitié renseignée produit un
APK non signé, pas une erreur obscure en fin de compilation.

## Construire par l'intégration continue

Le travail `Android Release` (`.github/workflows/android-release.yml`) produit
l'APK signé. Il ne se déclenche que par un lancement manuel ou par une
étiquette `v*`, jamais sur une proposition de modification : les secrets ne
doivent pas être exposés à du code non vérifié.

Secrets à renseigner dans l'environnement GitHub `distribution` :

| Secret | Contenu |
|---|---|
| `FOXLLM_RELEASE_KEYSTORE_BASE64` | le fichier `.jks` encodé en base64 |
| `FOXLLM_RELEASE_STORE_PASSWORD` | mot de passe du magasin |
| `FOXLLM_RELEASE_KEY_ALIAS` | alias de la clé |
| `FOXLLM_RELEASE_KEY_PASSWORD` | mot de passe de la clé |

Pour encoder la clé :

```sh
base64 -w0 foxllm-release.jks
```

L'environnement `distribution` peut exiger une approbation manuelle avant
chaque signature. Le travail efface la clé du disque du runner même s'il
échoue, et n'affiche aucune valeur : seule la présence des secrets est
vérifiée.

## Vérifier avant de publier

L'intégration continue refuse l'APK s'il porte la clé de développement. À
faire aussi de votre côté :

```sh
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

Le certificat affiché doit être le vôtre. La présence de `CN=Android Debug`
signifie que l'APK n'est pas distribuable.

Vérifiez enfin la mise à jour sans désinstallation, avec l'APK précédemment
publié et le nouveau :

```sh
adb install ancien-app-release.apk
adb install -r nouveau-app-release.apk
```

La seconde commande doit réussir et l'historique des conversations doit être
encore là. Un échec `INSTALL_FAILED_UPDATE_INCOMPATIBLE` signale deux
certificats différents.

## Avant la première publication

- [ ] clé créée et sauvegardée hors du dépôt ;
- [ ] secrets renseignés dans l'environnement `distribution` ;
- [ ] `Android Release` exécuté et son APK vérifié avec `apksigner` ;
- [ ] mise à jour testée sur un appareil, sans désinstallation ;
- [ ] version du `CHANGELOG`, de `pubspec.yaml` et de `core/app_info.dart`
      cohérentes ;
- [ ] politique de confidentialité publiée à une adresse publique.
