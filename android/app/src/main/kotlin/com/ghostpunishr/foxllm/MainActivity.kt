// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

package com.ghostpunishr.foxllm

import android.app.UiModeManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Relaie au système la déclinaison choisie dans Paramètres → Apparence.
 *
 * La fenêtre de lancement, celle qui porte le renard, est dessinée par Android
 * avant que le processus de l'application démarre : elle ne peut pas lire une
 * préférence Flutter et restait donc figée. Depuis Android 12,
 * `setApplicationNightMode` déclare le mode de l'application au système, qui
 * résout alors ses ressources — dont la couleur du splash — en conséquence.
 *
 * Avant Android 12, l'API n'existe pas : la fenêtre de lancement suit le mode
 * sombre du système, faute de mieux.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setDarkMode" -> {
                        applyNightMode(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

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
    }
}
