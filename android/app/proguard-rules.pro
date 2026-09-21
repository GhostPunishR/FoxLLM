# Règles de conservation pour la distribution minifiée.
#
# R8 supprime ce qu'il croit inatteignable. Tout ce qui n'est atteint que par
# réflexion, par un canal de plateforme ou depuis le code natif lui paraît
# donc mort, et disparaît sans avertissement : l'application compile, puis
# échoue à l'exécution, sur l'appareil de l'utilisateur.
#
# Le pont FFI de FoxLLM n'est pas concerné : il passe par `DynamicLibrary` et
# ne traverse jamais la machine virtuelle Java. Ce fichier protège ce qui,
# lui, la traverse.

# Flutter et ses canaux de plateforme.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.embedding.**

# L'activité de FoxLLM, nommée dans le manifeste, et le gestionnaire du canal
# `foxllm/appearance` qui teinte la fenêtre de lancement.
-keep class com.ghostpunishr.foxllm.** { *; }

# Reconnaissance et synthèse vocales : les deux services du système rappellent
# l'application par des écouteurs instanciés par réflexion.
-keep class android.speech.** { *; }
-dontwarn android.speech.**

# Le stockage sécurisé s'appuie sur le trousseau d'Android, dont les classes
# de chiffrement sont chargées par leur nom.
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**

# Les annotations servent à R8 lui-même et aux bibliothèques qui les lisent.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Les traces d'erreur restent lisibles : sans cela, un incident rapporté par
# un utilisateur ne désignerait que des noms d'une lettre.
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile
