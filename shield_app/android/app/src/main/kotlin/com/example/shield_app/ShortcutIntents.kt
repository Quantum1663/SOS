package com.example.shield_app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri

object ShortcutIntents {
    const val shortcutScheme = "shield"
    const val shortcutHost = "shortcut"

    const val quickOpen = "quick_open"
    const val fullPanic = "full_panic"
    const val silentSos = "silent_sos"
    const val checkIn = "check_in"
    const val checkInExpired = "check_in_expired"

    fun createActivityPendingIntent(
        context: Context,
        action: String?
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_NEW_TASK
            if (action != null) {
                data = Uri.parse("$shortcutScheme://$shortcutHost/$action")
            }
        }

        return PendingIntent.getActivity(
            context,
            action?.hashCode() ?: 0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun extractShortcutAction(intent: Intent?): String? {
        val data = intent?.data ?: return null
        if (data.scheme != shortcutScheme || data.host != shortcutHost) {
            return null
        }

        return when (data.lastPathSegment) {
            quickOpen -> quickOpen
            fullPanic -> fullPanic
            silentSos -> silentSos
            checkIn -> checkIn
            checkInExpired -> checkInExpired
            else -> null
        }
    }
}
