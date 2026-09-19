// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

package com.ghostpunishr.foxllm

import android.app.UiModeManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Relaie au système la déclinaison choisie dans Paramètres → Apparence.
 *
 * La fenêtre de lancement, celle qui porte le renard, est dessinée par Android
 * avant que le processus de l'application démarre : elle ne peut pas lire une
 * préférence Flutter. Depuis Android 12, `setApplicationNightMode` déclare le
 * mode de l'application au système, qui résout alors ses ressources, dont la
 * couleur du splash, dès le lancement suivant.
 *
 * Cette déclaration est faite deux fois, et les deux comptent : à l'ouverture
 * de l'activité, depuis une préférence ordinaire, pour qu'elle ne dépende ni
 * du moteur Flutter ni d'une lecture chiffrée ; puis à chaque choix de
 * l'utilisateur, par le canal.
 *
 * Avant Android 12, l'API n'existe pas : la fenêtre de lancement suit le mode
 * sombre du système, faute de mieux.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Avant `super.onCreate`, donc avant que l'activité choisisse son
        // thème : la fenêtre qui prend la suite du splash part déjà sur la
        // bonne déclinaison. Attendre le canal reviendrait à attendre le
        // démarrage du moteur, bien après l'affichage.
        //
        // `uiMode` figure dans les `configChanges` du manifeste : le
        // changement de configuration que cette déclaration peut provoquer ne
        // recrée donc pas l'activité.
        applyNightMode(preferences().getBoolean(DARK_KEY, false))
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setDarkMode" -> {
                        val dark = call.arguments as? Boolean ?: false
                        // Gardé côté natif pour être relu au lancement
                        // suivant, avant Flutter. Le stockage chiffré de
                        // l'application reste la référence du thème ; cette
                        // copie ne sert qu'à la fenêtre de lancement.
                        preferences().edit().putBoolean(DARK_KEY, dark).apply()
                        applyNightMode(dark)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun preferences() =
        getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun applyNightMode(dark: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return
        }
        val uiModeManager = getSystemService(UiModeManager::class.java) ?: return
        uiModeManager.setApplicationNightMode(
            if (dark) UiModeManager.MODE_NIGHT_YES else UiModeManager.MODE_NIGHT_NO,
        )
    }

    private companion object {
        const val CHANNEL = "foxllm/appearance"
        const val PREFERENCES = "foxllm.appearance"
        const val DARK_KEY = "dark"
    }
}
