package com.example.shield_app

import android.content.Intent
import android.content.Context
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class ShieldQuickSettingsTileService : TileService() {
    private val preferencesName = "shield_prefs"
    private val stealthModeKey = "stealth_mode"

    override fun onStartListening() {
        super.onStartListening()
        val stealth = getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .getBoolean(stealthModeKey, false)
        qsTile?.apply {
            label = if (stealth) "Notes" else "SHIELD"
            subtitle = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (stealth) "Quick tools" else "Late travel help"
            } else {
                subtitle
            }
            state = Tile.STATE_ACTIVE
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            data = android.net.Uri.parse(
                "${ShortcutIntents.shortcutScheme}://${ShortcutIntents.shortcutHost}/${ShortcutIntents.quickOpen}"
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(android.app.PendingIntent.getActivity(
                this,
                ShortcutIntents.quickOpen.hashCode(),
                intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    android.app.PendingIntent.FLAG_IMMUTABLE
            ))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
